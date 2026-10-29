import Foundation
import Darwin
import CryptoKit

enum SessionOperation:String,Codable { case launch, quit }
enum SessionPlan:Equatable {
    case launchApplication(path:String)
    case quitApplication(bundle:String)
    static func fixed(service:ManagedService,operation:SessionOperation)->SessionPlan {
        switch (service,operation) {
        case (.mlx,.launch):return .launchApplication(path:"/Applications/MLX-Serve.app")
        case (.orbstack,.launch):return .launchApplication(path:"/Applications/OrbStack.app")
        case (.mlx,.quit):return .quitApplication(bundle:"com.dalcu.mlx-core")
        case (.orbstack,.quit):return .quitApplication(bundle:"dev.kdrag0n.MacVirt")
        }
    }
}

enum SessionLaunchResult:Equatable,Sendable {
    case notSent,uncertain,wrongInstance,busy
    case started(ServiceIdentity)
}

struct SessionLaunchRequest {
    let id:String
    let operation:String
    let service:ManagedService
    let instance:String
    let profile:String
    init(_ data:Data)throws {
        try StrictJSON.validate(data,maximum:1024)
        guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(value.keys)==Set(["version","id","operation","service","instance","profile"]),
              WireScalar.integer(value["version"],maximum:1)==1,
              let id=value["id"] as? String,WireScalar.uuid(id),
              let operation=value["operation"] as? String,["launch","lookup"].contains(operation),
              let raw=value["service"] as? String,let service=ManagedService(rawValue:raw),
              let instance=value["instance"] as? String,WireScalar.uuid(instance),
              let profile=value["profile"] as? String,WireScalar.sha256(profile) else {throw ControlError.invalid_request}
        self.id=id;self.operation=operation;self.service=service;self.instance=instance;self.profile=profile
    }
}

// Dispatcher for the enrolled session transport. Its manager/executable inputs
// in the installed helper come only from root-protected enrollment and must
// come from reviewed immutable installation policy, never a request/session
// observation file. Approved applications bind exact kernel paths and hashes.
// No operation can select an executable, argv, URL or role.
final class SessionLaunchGate {
    private struct Entry {let service:ManagedService;var result:SessionLaunchResult;var dispatched=false}
    let instance=UUID().uuidString.lowercased()
    let profile:String
    private let manager:VerifiedExecutable
    private let applications:[ManagedService:VerifiedExecutable]
    private var entries:[String:Entry]=[:]
    private var previous:Int64=0
    private var fenced=false

    init(manager:VerifiedExecutable,approvedApplications:[ManagedService:VerifiedExecutable])throws {
        let approvedHashes=approvedApplications.mapValues(\.sha256)
        guard geteuid()>0,getuid()==geteuid(),Set(approvedHashes.keys)==Set(ManagedService.allCases),
              approvedHashes.values.allSatisfy(WireScalar.sha256) else {throw ControlError.unauthorized}
        self.manager=manager;applications=approvedApplications
        let canonical=ManagedService.allCases.map {$0.rawValue+":"+approvedHashes[$0]!}.sorted().joined(separator:"\n")
        profile=SHA256.hash(data:Data(("fios-service-recovery-v1\n"+canonical).utf8)).map {String(format:"%02x",$0)}.joined()
    }

    func handle(_ data:Data,peer:NativeControlPeer,uid:uid_t,consoleReady:Bool,now:Int64,
                launch:(ManagedService,String)throws->SessionLaunchResult)throws->SessionLaunchResult {
        guard uid>0,uid==geteuid(),getuid()==geteuid() else {throw ControlError.unauthorized}
        let request=try SessionLaunchRequest(data)
        // Socket integration must obtain UID/PID from kernel peer credentials,
        // not packet fields. Verify the fixed enrolled image and kernel start.
        guard peer.executable.path==manager.path,peer.executable.sha256==manager.sha256 else {throw ControlError.unauthorized}
        do {
            _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:peer.pid,start:peer.start,executable:manager),
                expectedUID:uid,deadline:ProcessInfo.processInfo.systemUptime+2)
        } catch {throw ControlError.unauthorized}
        guard request.profile==profile else {throw ControlError.unauthorized}
        guard request.instance==instance else {return .wrongInstance}
        guard (0...WireScalar.maximumTimestamp).contains(now) else {throw ControlError.invalid_request}
        guard observeClock(now) else {return .uncertain}
        if let existing=entries[request.id] {
            guard existing.service==request.service else {throw ControlError.invalid_request}
            return existing.result
        }
        // Missing cache state cannot prove an old helper did not dispatch.
        if request.operation=="lookup" {return .uncertain}
        guard entries.count<256,!entries.values.contains(where:{$0.service==request.service && $0.result == .uncertain}) else {return .busy}
        if !consoleReady {
            entries[request.id]=Entry(service:request.service,result:.notSent)
            return .notSent
        }
        // Consume before effects; errors/timeouts and malformed callback data
        // stay uncertain. This memory cache is generation-bound; the manager's
        // durable launch intent is required across helper restart/cache loss.
        entries[request.id]=Entry(service:request.service,result:.uncertain)
        let outcome:SessionLaunchResult
        do {outcome=try launch(request.service,request.id)} catch {return .uncertain}
        switch outcome {
        case .notSent:
            if entries[request.id]?.dispatched == false {entries[request.id]?.result = .notSent}
        case .started(let identity):
            entries[request.id]?.dispatched=true
            if try verifiedStarted(identity,service:request.service,uid:uid) {entries[request.id]?.result = outcome}
        case .uncertain,.wrongInstance,.busy:break
        }
        return entries[request.id]!.result
    }

    // Called only by the helper's own completion closure on this serialized
    // gate, never by IPC or a presence observer. Unknown IDs, other services,
    // already-final results and another helper generation cannot resolve it.
    @discardableResult
    func acknowledgeStarted(id:String,service:ManagedService,identity:ServiceIdentity)throws->Bool {
        guard !fenced,getuid()>0,getuid()==geteuid(),
              let entry=entries[id],entry.service==service,entry.dispatched,entry.result == .uncertain,
              try verifiedStarted(identity,service:service,uid:geteuid()) else {return false}
        entries[id]?.result = .started(identity)
        return true
    }
    // Local pre-effect completion only. The actuator must prove it never
    // called the application API and no continuation can still do so. Neither
    // elapsed time nor an AppKit error after dispatch supplies that proof.
    @discardableResult
    func acknowledgeNotSent(id:String,service:ManagedService)->Bool {
        guard !fenced,getuid()>0,getuid()==geteuid(),let entry=entries[id],
              entry.service==service,!entry.dispatched,entry.result == .uncertain else {return false}
        entries[id]?.result = .notSent
        return true
    }
    // Local one-use edge immediately before the application API, after
    // read-only validation. In particular, a clock-fenced helper cannot let a
    // delayed validation continuation begin native work.
    @discardableResult
    func claimDispatch(id:String,service:ManagedService,now:Int64)->Bool {
        guard !fenced,getuid()>0,getuid()==geteuid(),let entry=entries[id],
              entry.service==service,!entry.dispatched,entry.result == .uncertain,observeClock(now) else {return false}
        entries[id]?.dispatched=true
        return true
    }
    private func observeClock(_ now:Int64)->Bool {
        guard (0...WireScalar.maximumTimestamp).contains(now) else {return false}
        if now<previous {fenced=true}
        previous=max(previous,now)
        return !fenced
    }

    private func verifiedStarted(_ identity:ServiceIdentity,service:ManagedService,uid:uid_t)throws->Bool {
        guard identity.valid,let executable=applications[service],identity.sha256==executable.sha256 else {return false}
        var bytes=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(identity.pid,&bytes,UInt32(bytes.count))>0,
              let path=String(bytes:bytes.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8),
              path==executable.path else {return false}
        do {
            let verified=try ServiceIdentity.verified(peer:NativeControlPeer(pid:identity.pid,start:identity.start,executable:executable),
                expectedUID:uid,deadline:ProcessInfo.processInfo.systemUptime+2)
            return verified==identity
        } catch {return false}
    }
}
