import Foundation
import CoreFoundation
import Darwin
import CryptoKit

enum ServiceLaunchProfile {
    // Configuration binding, never native authority. Credentials retain their
    // named slot/channel but their values must not become journal verifiers.
    static func nativeDigest(base:String,arguments:[String],environment:[String:String],workingDirectory:String)throws->String {
        guard WireScalar.sha256(base) else {throw ServiceError.invalid}
        var args=arguments
        for index in args.indices {
            if index>0,arguments[index-1]=="--api-key" {args[index]="<credential-slot>"}
            else if args[index].hasPrefix("--api-key=") {args[index]="--api-key=<credential-slot>"}
        }
        var values=environment
        if values["FIOS_MLX_SERVING_API_KEY"] != nil {values["FIOS_MLX_SERVING_API_KEY"]="<credential-slot>"}
        let bytes=try JSONSerialization.data(withJSONObject:["version":1,"base":base,"arguments":args,"environment":values,"working_directory":workingDirectory],options:[.sortedKeys,.withoutEscapingSlashes])
        return SHA256.hash(data:Data("fios-native-launch-inputs-v1\n".utf8)+bytes).map {String(format:"%02x",$0)}.joined()
    }
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
// Historical correlated launch acknowledgement, not current presence, native
// terminality, child adoption or a stop/start permit. Retain it across manager
// reconstruction so lifecycle engineering does not lose the exact process.
struct ServiceRecordedLaunch:Equatable,Sendable {
    let service:ManagedService
    let id:String
    let identity:ServiceIdentity
    let boot:String
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
        guard operation == .launch else {return true} // Lookups and revocations never grant a launch.
        lock.lock();defer {lock.unlock()}
        guard !consumed else {return false};consumed=true;return true
    }
}

enum ServingStopOperation:Equatable,Sendable {case stop,lookup,cancel}
final class ServingStopRequest:@unchecked Sendable {
    let operation:ServingStopOperation
    let id:String
    let receipt:ServiceRecordedLaunch
    private let lock=NSLock()
    private var consumed=false
    fileprivate init(operation:ServingStopOperation,id:String,receipt:ServiceRecordedLaunch) {
        self.operation=operation;self.id=id;self.receipt=receipt
    }
    func consumeTransport()->Bool {
        guard operation == .stop else {return true}
        lock.lock();defer {lock.unlock()};guard !consumed else {return false};consumed=true;return true
    }
}

// Serialized by the journal's one manager owner. Planning durably reserves a
// launch BEFORE returning a command. It never executes anything itself and is
// not an IPC decoder/production enrollment issuer. Transport timeout, fresh
// absence, elapsed time and restart cannot prove an old launch was not sent.
final class ServiceRecoveryController {
    private struct Receipt:Codable,Equatable {
        let id:String
        let pid:Int32
        let start:String
        let sha256:String
        let boot:String
        var valid:Bool {
            WireScalar.uuid(id) && pid>1 && WireScalar.sha256(sha256) && WireScalar.uuid(boot) &&
            UInt64(start).map {$0>0 && String($0)==start} == true
        }
    }
    private struct PendingStop:Codable {
        let id:String
        let receipt:Receipt
        let desired:ServiceDesired
    }
    private struct Entry:Codable {
        let service:ManagedService
        var starts:[Int64]=[]
        var pending:String?
        var lastStarted:Receipt?
        var stops:[Int64]?=[]
        var stopPending:PendingStop?
    }
    private struct State:Codable {
        var version:Int
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

    init(journal:Journal,approvedHashes:[ManagedService:String],recoveryProfileHash:String?=nil) throws {
        guard geteuid() != 0,Set(approvedHashes.keys)==Set(ManagedService.allCases),
              approvedHashes.values.allSatisfy(WireScalar.sha256) else {throw ServiceError.invalid}
        owner=journal;pins=approvedHashes
        file=journal.directory.appendingPathComponent("service-recovery.json")
        let profile=try recoveryProfileHash ?? ServiceLaunchProfile.digest(approvedHashes)
        guard WireScalar.sha256(profile) else {throw ServiceError.invalid}
        let boot=try HostBoot.identity()
        if var loaded=try Self.read(file) {
            guard loaded.profile==profile,loaded.entries.allSatisfy({entry in entry.lastStarted.map {$0.sha256==approvedHashes[entry.service]} ?? true}) else {throw ServiceError.invalid}
            loaded.version=3
            for index in loaded.entries.indices {if loaded.entries[index].stops==nil {loaded.entries[index].stops=[]}}
            if loaded.boot != boot {
                // A new OS boot can reset only the local start-rate clock.
                // A queued/unknown old launch remains fenced, never refunded.
                if loaded.entries.contains(where:{$0.pending != nil || $0.stopPending != nil}) {loaded.fenced=true}
                else {
                    for index in loaded.entries.indices {loaded.entries[index].starts=[];loaded.entries[index].stops=[]}
                    loaded.previousTick=0
                }
                loaded.boot=boot
            }
            state=loaded
        } else {
            state=State(version:3,profile:profile,boot:boot,previousWall:0,previousTick:0,fenced:false,
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
                  let version=WireScalar.integer(root["version"],maximum:3),(1...3).contains(version),
                  WireScalar.integer(root["previousWall"]) != nil,WireScalar.integer(root["previousTick"]) != nil,
                  let flag=root["fenced"] as? NSNumber,CFGetTypeID(flag)==CFBooleanGetTypeID(),
                  let entries=root["entries"] as? [[String:Any]],entries.count==2,
                  entries.allSatisfy({entry in
                      let allowed:Set<String>=version==1 ? ["service","starts","pending"]:version==2 ? ["service","starts","pending","lastStarted"]:["service","starts","pending","lastStarted","stops","stopPending"]
                      guard Set(entry.keys).isSubset(of:allowed),Set(["service","starts"]).isSubset(of:Set(entry.keys)),
                            let starts=entry["starts"] as? [Any] else {return false}
                      func validReceipt(_ object:Any)->Bool {
                          guard let fields=object as? [String:Any],Set(fields.keys)==Set(["id","pid","start","sha256","boot"]),
                                let pid=WireScalar.integer(fields["pid"],maximum:Int64(Int32.max)),pid>1 else {return false}
                          return true
                      }
                      if let receipt=entry["lastStarted"] {
                          guard validReceipt(receipt) else {return false}
                      }
                      if version==3 {
                          guard let stops=entry["stops"] as? [Any],stops.allSatisfy({WireScalar.integer($0) != nil}) else {return false}
                      }
                      if let pending=entry["stopPending"] {
                          guard let fields=pending as? [String:Any],Set(fields.keys)==Set(["id","receipt","desired"]),
                                let receipt=fields["receipt"],validReceipt(receipt) else {return false}
                      }
                      return starts.allSatisfy {WireScalar.integer($0) != nil}
                  }) else {throw ServiceError.invalid}
            let value=try JSONDecoder().decode(State.self,from:data)
            guard (1...3).contains(value.version),WireScalar.sha256(value.profile),WireScalar.uuid(value.boot),
                  (0...WireScalar.maximumTimestamp).contains(value.previousWall),
                  (0...WireScalar.maximumTimestamp).contains(value.previousTick),
                  Set(value.entries.map(\.service))==Set(ManagedService.allCases),
                  value.entries.allSatisfy({entry in
                      entry.starts.count<=3 && entry.starts==entry.starts.sorted() &&
                      entry.starts.allSatisfy {(0...value.previousTick).contains($0)} &&
                      (entry.pending.map(WireScalar.uuid) ?? true) && (entry.lastStarted?.valid ?? true) &&
                      (entry.stops.map {$0.count<=3 && $0==$0.sorted() && $0.allSatisfy {(0...value.previousTick).contains($0)}} ?? (value.version<3)) &&
                      (entry.stopPending.map {stop in entry.service == .mlx && entry.pending==nil &&
                          WireScalar.uuid(stop.id) && stop.receipt.valid && stop.receipt==entry.lastStarted &&
                          stop.id != stop.receipt.id && stop.desired != .maintenance} ?? true)
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
    func recordedLaunch(_ service:ManagedService)->ServiceRecordedLaunch? {
        guard let receipt=state.entries.first(where:{$0.service==service})?.lastStarted,
              receipt.valid,let start=UInt64(receipt.start) else {return nil}
        return ServiceRecordedLaunch(service:service,id:receipt.id,identity:ServiceIdentity(pid:receipt.pid,start:start,sha256:receipt.sha256),boot:receipt.boot,profileHash:state.profile)
    }
    func isStopPending()->Bool {state.entries.first(where:{$0.service == .mlx})?.stopPending != nil}

    // Durable intent only. The opaque code-issued intent has no installed
    // producer, and the physical runtime independently validates native authority.
    func planStop(_ intent:ServingStopIntent,now:Int64,tick:Int64)throws->ServingStopRequest? {
        guard try observeClock(now:now,tick:tick),intent.desired != .maintenance,
              try owner.desired(service:"mlx")==intent.desired.rawValue,
              intent.receipt==recordedLaunch(.mlx),intent.receipt.boot==state.boot,
              let index=state.entries.firstIndex(where:{$0.service == .mlx}),state.entries[index].pending==nil,
              state.entries[index].stopPending==nil else {return nil}
        let attempts=(state.entries[index].stops ?? []).filter {tick-$0<600000}
        guard attempts.count<3,attempts.last.map({tick-$0>=10000}) ?? true,intent.consumeReservation(),
              let receipt=state.entries[index].lastStarted else {return nil}
        state.entries[index].stops=attempts+[tick]
        state.entries[index].stopPending=PendingStop(id:intent.id,receipt:receipt,desired:intent.desired)
        try persist() // Retain the live pending ID even after an uncertain write.
        return ServingStopRequest(operation:.stop,id:intent.id,receipt:intent.receipt)
    }
    func nextStop(now:Int64,tick:Int64)throws->ServingStopRequest? {
        guard let pending=state.entries.first(where:{$0.service == .mlx})?.stopPending,
              let receipt=recordedLaunch(.mlx) else {return nil}
        _=try observeClock(now:now,tick:tick)
        let desired=try owner.desired(service:"mlx")
        return ServingStopRequest(operation:desired==pending.desired.rawValue ? .lookup:.cancel,id:pending.id,receipt:receipt)
    }
    func receiveStop(_ request:ServingStopRequest,result:ServingStopResult)throws {
        guard let index=state.entries.firstIndex(where:{$0.service == .mlx}),
              state.entries[index].stopPending?.id==request.id,recordedLaunch(.mlx)==request.receipt else {throw ServiceError.invalid}
        guard result != .uncertain else {return}
        var candidate=state
        candidate.entries[index].stopPending=nil
        try persist(candidate)
        state=candidate // No native inference claims or launch receipts changed.
    }

    // Read-only local restart-budget diagnostics. Available budget does not
    // establish service absence/session readiness or authorize a launch.
    func summary(service:ManagedService,tick:Int64)->[String:Any] {
        var result:[String:Any]=["budget_state":"unknown","starts_in_window":NSNull(),
            "budget_wait_ms":NSNull(),"window_ms":600000,"maximum_starts":3,"minimum_spacing_ms":10000]
        guard let entry=state.entries.first(where:{$0.service==service}) else {return result}
        if state.fenced {result["budget_state"]="clock_fenced";return result}
        guard (0...WireScalar.maximumTimestamp).contains(tick),tick>=state.previousTick else {return result}
        let starts=entry.starts.filter{tick-$0<600000}
        result["starts_in_window"]=starts.count
        if entry.pending != nil || entry.stopPending != nil {result["budget_state"]="pending";return result}
        let spacing=starts.last.map{max(0,10000-(tick-$0))} ?? 0
        let window=starts.count>=3 ? max(0,600000-(tick-starts[0])):0
        let wait=max(spacing,window)
        result["budget_state"]=wait>0 ? "rate_limited":"available"
        result["budget_wait_ms"]=wait
        return result
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
    // maintenance, missing observations or a clock fence. Non-running intent
    // requests revocation of still-read-only validation; dispatched/missing
    // helper history remains uncertain and never becomes a new launch.
    func next(service:ManagedService,desired:ServiceDesired,observation:ServiceObservation?,now:Int64,tick:Int64)throws->ServiceRecoveryRequest? {
        if let id=state.entries.first(where:{$0.service==service})?.pending {
            _=try observeClock(now:now,tick:tick)
            return ServiceRecoveryRequest(operation:desired == .running ? .lookup:.cancel,command:ServiceLaunchCommand(service:service,id:id,expectedSHA256:pins[service]!,profileHash:state.profile))
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
              let index=state.entries.firstIndex(where:{$0.service==service}),state.entries[index].pending==nil,state.entries[index].stopPending==nil else {return nil}
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
        guard identity.valid,identity.sha256==pins[service],
              let index=state.entries.firstIndex(where:{$0.service==service}),state.entries[index].pending==id else {throw ServiceError.invalid}
        var candidate=state
        candidate.entries[index].lastStarted=Receipt(id:id,pid:identity.pid,start:String(identity.start),sha256:identity.sha256,boot:state.boot)
        candidate.entries[index].pending=nil
        try persist(candidate)
        state=candidate
    }
}
