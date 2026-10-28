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

enum SessionLaunchResult:Equatable {
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

// Source-only dispatcher for a future enrolled session transport. The real
// helper does not instantiate this yet. Its manager/executable inputs must
// come from reviewed immutable installation policy, never a request/session
// observation file. No operation can select an executable, argv, URL or role.
final class SessionLaunchGate {
    private struct Entry {let service:ManagedService;var result:SessionLaunchResult}
    let instance=UUID().uuidString.lowercased()
    let profile:String
    private let manager:VerifiedExecutable
    private let pins:[ManagedService:String]
    private var entries:[String:Entry]=[:]
    private var previous:Int64=0
    private var fenced=false

    init(manager:VerifiedExecutable,approvedHashes:[ManagedService:String])throws {
        guard geteuid()>0,getuid()==geteuid(),Set(approvedHashes.keys)==Set(ManagedService.allCases),
              approvedHashes.values.allSatisfy(WireScalar.sha256) else {throw ControlError.unauthorized}
        self.manager=manager;pins=approvedHashes
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
        if now<previous {fenced=true}
        previous=max(previous,now)
        guard !fenced else {return .uncertain}
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
        case .notSent:entries[request.id]?.result = .notSent
        case .started(let identity):
            if try verifiedStarted(identity,service:request.service,uid:uid) {entries[request.id]?.result = outcome}
        case .uncertain,.wrongInstance,.busy:break
        }
        return entries[request.id]!.result
    }

    private func verifiedStarted(_ identity:ServiceIdentity,service:ManagedService,uid:uid_t)throws->Bool {
        guard identity.valid,identity.sha256==pins[service] else {return false}
        var bytes=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(identity.pid,&bytes,UInt32(bytes.count))>0,
              let path=String(bytes:bytes.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {return false}
        do {
            let executable=try VerifiedExecutable(path:path,sha256:identity.sha256)
            let verified=try ServiceIdentity.verified(peer:NativeControlPeer(pid:identity.pid,start:identity.start,executable:executable),
                expectedUID:uid,deadline:ProcessInfo.processInfo.systemUptime+2)
            return verified==identity
        } catch {return false}
    }
}
