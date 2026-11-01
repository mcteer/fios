import Foundation
import Darwin

// Lifetime belongs to the existing supervisor, independently of any manager
// connection. Source-only: no public startup or installed issuer is wired.
// Call handle off-loop: peer identity verification may hash an executable.
final class ServingCustodyGate:@unchecked Sendable {
    private struct Entry {let isStop:Bool;let receipt:ServiceRecordedLaunch?}
    let instance=UUID().uuidString.lowercased()
    let profile:String
    private let runtime:any ServingProcessControlling
    private let manager:VerifiedExecutable
    private let imageSHA256:String
    private let lock=NSLock()
    private var boundManager:NativeControlPeer?
    private var generation=UUID().uuidString.lowercased()
    private var entries:[String:Entry]=[:]
    init(runtime:any ServingProcessControlling,manager:VerifiedExecutable,imageSHA256:String)throws {
        guard WireScalar.sha256(imageSHA256),WireScalar.sha256(runtime.recoveryProfileHash),
              runtime.accepts(ServiceLaunchCommand(service:.mlx,id:UUID().uuidString.lowercased(),expectedSHA256:imageSHA256,profileHash:runtime.recoveryProfileHash)) else {throw ServiceError.invalid}
        self.runtime=runtime;self.manager=manager;self.imageSHA256=imageSHA256;profile=runtime.recoveryProfileHash
    }
    // Only the supervisor's own child tracking supplies this binding. There
    // is no packet that enrolls a manager or changes its executable identity.
    func bindManager(_ peer:NativeControlPeer?)throws {
        if let peer {
            guard peer.pid>1,peer.start>0,peer.executable.path==manager.path,peer.executable.sha256==manager.sha256 else {throw ControlError.unauthorized}
        }
        lock.lock();defer {lock.unlock()}
        if let current=boundManager,let peer,current.pid==peer.pid,current.start==peer.start {return}
        if boundManager==nil,peer==nil {return}
        boundManager=peer;generation=UUID().uuidString.lowercased()
        // Seal only work still in read-only validation. Dispatch/timeout and
        // known child custody survive manager loss; nothing clears native work.
        for (id,entry) in entries {
            if let receipt=entry.receipt {_=runtime.cancelStopValidation(id:id,matching:receipt)}
            else {_=runtime.cancelValidation(id:id)}
        }
    }
    private func matches(_ peer:NativeControlPeer)->Bool {
        guard let current=boundManager else {return false}
        return current.pid==peer.pid && current.start==peer.start && peer.executable.path==manager.path && peer.executable.sha256==manager.sha256
    }
    func handle(_ command:ServingCustodyCommand,peer:NativeControlPeer,uid:uid_t)throws->ServingCustodyValue {
        guard uid>0,uid==geteuid(),getuid()==geteuid(),command.profile==profile,
              command.imageSHA256==imageSHA256,command.instance==instance else {throw ControlError.unauthorized}
        lock.lock()
        guard matches(peer) else {lock.unlock();throw ControlError.unauthorized}
        let admittedGeneration=generation
        lock.unlock()
        _=try ServiceIdentity.verified(peer:peer,expectedUID:uid,deadline:ProcessInfo.processInfo.systemUptime+2)
        lock.lock();defer {lock.unlock()}
        guard generation==admittedGeneration,matches(peer) else {throw ControlError.unauthorized}
        let alreadyConsumed=entries[command.id] != nil
        if let entry=entries[command.id] {
            guard entry.isStop==command.operation.isStop,entry.receipt==command.receipt else {throw ControlError.invalid_request}
        } else if command.operation.isAction {
            guard entries.count<512 else {return command.operation.isStop ? .stop(.uncertain):.launch(.busy)}
            // Consume before entering the runtime. Missing old history never
            // becomes a positive non-dispatch or local-exit acknowledgement.
            entries[command.id]=Entry(isStop:command.operation.isStop,receipt:command.receipt)
        } else {return command.operation.isStop ? .stop(.uncertain):.launch(.uncertain)}
        switch command.operation {
        case .launch:
            if alreadyConsumed {return .launch(runtime.acknowledgeResult(id:command.id))}
            // The runtime's immutable ID history prevents action replay even
            // while an earlier spawn is still unresolved.
            _=runtime.retireKnownExited()
            do {try runtime.begin(command.launchCommand,deadline:command.deadline!)}
            catch {return .launch(runtime.acknowledgeResult(id:command.id))}
            return .launch(.uncertain)
        case .lookupLaunch:return .launch(runtime.acknowledgeResult(id:command.id))
        case .cancelLaunch:
            _=runtime.cancelValidation(id:command.id)
            return .launch(runtime.acknowledgeResult(id:command.id))
        case .stop:
            if alreadyConsumed {return .stop(runtime.acknowledgeStopResult(id:command.id,matching:command.receipt!))}
            let receipt=command.receipt!
            do {try runtime.beginStop(id:command.id,matching:receipt,deadline:command.deadline!)}
            catch RuntimeError.capacity {return .stop(runtime.rejectedStopResult(id:command.id,matching:receipt))}
            catch {return .stop(.uncertain)}
            return .stop(.uncertain)
        case .lookupStop:return .stop(runtime.acknowledgeStopResult(id:command.id,matching:command.receipt!))
        case .cancelStop:
            _=runtime.cancelStopValidation(id:command.id,matching:command.receipt!)
            return .stop(runtime.acknowledgeStopResult(id:command.id,matching:command.receipt!))
        }
    }
}
