import Foundation
import CoreFoundation
import Darwin
import CryptoKit

enum ServiceLaunchProfile {
    static func digest(_ hashes:[ManagedService:String])throws->String {
        guard Set(hashes.keys)==Set(ManagedService.allCases),hashes.values.allSatisfy(WireScalar.sha256) else {throw ServiceError.invalid}
        let canonical=ManagedService.allCases.map {$0.rawValue+":"+hashes[$0]!}.sorted().joined(separator:"\n")
        return SHA256.hash(data:Data(("fios-service-recovery-v1\n"+canonical).utf8)).map {String(format:"%02x",$0)}.joined()
    }
}
// A fixed command for a separately identity-checked session transport. No
// executable, environment, endpoint, arbitrary argv or operator force field.
struct ServiceLaunchCommand:Sendable {
    let service:ManagedService
    let id:String
    let expectedSHA256:String
    let profileHash:String
}
final class ServiceRecoveryRequest:@unchecked Sendable {
    let operation:SessionClientOperation
    let command:ServiceLaunchCommand
    private let lock=NSLock()
    private var consumed=false
    fileprivate init(operation:SessionClientOperation,command:ServiceLaunchCommand) {
        self.operation=operation;self.command=command
    }
    // Only a new controller reservation can create a launch object. Retaining
    // or copying its reference cannot turn transport failure into a retry.
    func consumeTransport()->Bool {
        guard operation == .launch else {return true} // Lookups have no effect.
        lock.lock();defer {lock.unlock()}
        guard !consumed else {return false};consumed=true;return true
    }
}

// Serialized by the journal's one manager owner. Planning durably reserves a
// launch BEFORE returning a command. It never executes anything itself and is
// not an IPC decoder/production enrollment issuer. Transport timeout, fresh
// absence, elapsed time and restart cannot prove an old launch was not sent.
final class ServiceRecoveryController {
    private struct Entry:Codable {
        let service:ManagedService
        var starts:[Int64]=[]
        var pending:String?
    }
    private struct State:Codable {
        let version:Int
        let profile:String
        var boot:String
        var previousWall:Int64
        var previousTick:Int64
        var fenced:Bool
        var entries:[Entry]
    }
    private let owner:Journal // Retain the exclusive writer for this lifetime.
    private let file:URL
    private let pins:[ManagedService:String]
    private var state:State

    init(journal:Journal,approvedHashes:[ManagedService:String]) throws {
        guard geteuid() != 0,Set(approvedHashes.keys)==Set(ManagedService.allCases),
              approvedHashes.values.allSatisfy(WireScalar.sha256) else {throw ServiceError.invalid}
        owner=journal;pins=approvedHashes
        file=journal.directory.appendingPathComponent("service-recovery.json")
        let profile=try ServiceLaunchProfile.digest(approvedHashes)
        let boot=try HostBoot.identity()
        if var loaded=try Self.read(file) {
            guard loaded.profile==profile else {throw ServiceError.invalid}
            if loaded.boot != boot {
                // A new OS boot can reset only the local start-rate clock.
                // A queued/unknown old launch remains fenced, never refunded.
                if loaded.entries.contains(where:{$0.pending != nil}) {loaded.fenced=true}
                else {
                    for index in loaded.entries.indices {loaded.entries[index].starts=[]}
                    loaded.previousTick=0
                }
                loaded.boot=boot
            }
            state=loaded
        } else {
            state=State(version:1,profile:profile,boot:boot,previousWall:0,previousTick:0,fenced:false,
                entries:ManagedService.allCases.map {Entry(service:$0)})
        }
    }

    private static func read(_ file:URL)throws->State? {
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        if fd<0,errno==ENOENT {return nil}
        guard fd>=0 else {throw ServiceError.invalid};defer {close(fd)}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_uid==geteuid(),
              info.st_mode&0o7777==0o600,info.st_nlink==1,(1...4096).contains(info.st_size) else {throw ServiceError.invalid}
        var bytes=[UInt8](repeating:0,count:4097),offset=0
        while offset<bytes.count {
            let count=bytes.withUnsafeMutableBytes {Darwin.read(fd,$0.baseAddress!.advanced(by:offset),$0.count-offset)}
            if count<0,errno==EINTR {continue}
            guard count>=0 else {throw ServiceError.invalid};if count==0 {break};offset+=count
        }
        guard offset<=4096 else {throw ServiceError.invalid}
        let data=Data(bytes.prefix(offset))
        do {
            try StrictJSON.validate(data,maximum:4096)
            guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  Set(root.keys)==Set(["version","profile","boot","previousWall","previousTick","fenced","entries"]),
                  WireScalar.integer(root["version"],maximum:1)==1,
                  WireScalar.integer(root["previousWall"]) != nil,WireScalar.integer(root["previousTick"]) != nil,
                  let flag=root["fenced"] as? NSNumber,CFGetTypeID(flag)==CFBooleanGetTypeID(),
                  let entries=root["entries"] as? [[String:Any]],entries.count==2,
                  entries.allSatisfy({entry in
                      guard Set(entry.keys).isSubset(of:["service","starts","pending"]),Set(["service","starts"]).isSubset(of:Set(entry.keys)),
                            let starts=entry["starts"] as? [Any] else {return false}
                      return starts.allSatisfy {WireScalar.integer($0) != nil}
                  }) else {throw ServiceError.invalid}
            let value=try JSONDecoder().decode(State.self,from:data)
            guard value.version==1,WireScalar.sha256(value.profile),WireScalar.uuid(value.boot),
                  (0...WireScalar.maximumTimestamp).contains(value.previousWall),
                  (0...WireScalar.maximumTimestamp).contains(value.previousTick),
                  Set(value.entries.map(\.service))==Set(ManagedService.allCases),
                  value.entries.allSatisfy({entry in
                      entry.starts.count<=3 && entry.starts==entry.starts.sorted() &&
                      entry.starts.allSatisfy {(0...value.previousTick).contains($0)} &&
                      (entry.pending.map(WireScalar.uuid) ?? true)
                  }) else {throw ServiceError.invalid}
            return value
        } catch {throw ServiceError.invalid}
    }
    private func persist(_ value:State)throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let bytes=try encoder.encode(value)
        guard bytes.count<=4096 else {throw ServiceError.invalid}
        try AtomicState.write(bytes,to:file)
    }
    private func persist()throws {try persist(state)}
    func isPending(_ service:ManagedService)->Bool {
        state.entries.first(where:{$0.service==service})?.pending != nil
    }

    private func observeClock(now:Int64,tick:Int64)throws->Bool {
        guard (0...WireScalar.maximumTimestamp).contains(now),(0...WireScalar.maximumTimestamp).contains(tick) else {throw ServiceError.invalid}
        if now<state.previousWall || tick<state.previousTick {
            state.fenced=true;try persist();return false
        }
        state.previousWall=now;state.previousTick=tick
        return !state.fenced
    }
    // Reconciliation never replays an effect. It remains useful with stopped,
    // maintenance, missing observations or a clock fence: a lookup cannot
    // launch, and missing helper history remains uncertain.
    func next(service:ManagedService,desired:ServiceDesired,observation:ServiceObservation?,now:Int64,tick:Int64)throws->ServiceRecoveryRequest? {
        if let id=state.entries.first(where:{$0.service==service})?.pending {
            _=try observeClock(now:now,tick:tick)
            return ServiceRecoveryRequest(operation:.lookup,command:ServiceLaunchCommand(service:service,id:id,expectedSHA256:pins[service]!,profileHash:state.profile))
        }
        return try plan(service:service,desired:desired,observation:observation,now:now,tick:tick).map {ServiceRecoveryRequest(operation:.launch,command:$0)}
    }
    func receive(_ request:ServiceRecoveryRequest,result:SessionLaunchResult)throws {
        let command=request.command
        guard command.profileHash==state.profile,command.expectedSHA256==pins[command.service],
              state.entries.first(where:{$0.service==command.service})?.pending==command.id else {throw ServiceError.invalid}
        switch result {
        case .notSent:try notSent(service:command.service,id:command.id)
        case .started(let identity):try started(service:command.service,id:command.id,identity:identity)
        case .uncertain,.busy,.wrongInstance:break
        }
    }
    func plan(service:ManagedService,desired:ServiceDesired,observation:ServiceObservation?,now:Int64,tick:Int64)throws->ServiceLaunchCommand? {
        guard try observeClock(now:now,tick:tick),desired == .running,let observation else {return nil}
        if let identity=observation.identity,identity.sha256 != pins[service] {throw ServiceError.invalid}
        guard try ServicePolicy().action(service:service,desired:desired,observation:observation,now:now) == .launch,
              let index=state.entries.firstIndex(where:{$0.service==service}),state.entries[index].pending==nil else {return nil}
        state.entries[index].starts=state.entries[index].starts.filter {tick-$0<600_000}
        guard state.entries[index].starts.count<3,
              state.entries[index].starts.last.map({tick-$0>=10_000}) ?? true else {return nil}
        let id=UUID().uuidString.lowercased()
        state.entries[index].pending=id;state.entries[index].starts.append(tick)
        try persist()
        return ServiceLaunchCommand(service:service,id:id,expectedSHA256:pins[service]!,profileHash:state.profile)
    }
    // Trusted transport proof only, never a model/task/operator JSON claim.
    // Non-dispatch means no asynchronous launch may still materialize later.
    func notSent(service:ManagedService,id:String)throws {
        guard let index=state.entries.firstIndex(where:{$0.service==service}),state.entries[index].pending==id else {throw ServiceError.invalid}
        var candidate=state
        candidate.entries[index].pending=nil
        // Keep the original live intent held if writing or parent fsync fails.
        // An uncertain write is never permission to issue another launch.
        try persist(candidate)
        state=candidate
    }
    // A mere presence sample is insufficient. The authenticated transport must
    // correlate its acknowledgement with this exact verified launched process.
    func started(service:ManagedService,id:String,identity:ServiceIdentity)throws {
        guard identity.valid,identity.sha256==pins[service] else {throw ServiceError.invalid}
        try notSent(service:service,id:id)
    }
}
