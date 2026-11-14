import Foundation
import Darwin

// Only the exact historical process, never global service absence or native
// completion. A PID reused by another process means the original exited; the
// replacement is unrelated and must not be adopted, signalled or removed.
enum RecordedServiceProcessState:Equatable,Sendable {
    case current(ServiceIdentity),exited,unknown
}
struct RecordedServiceProcessSample:Sendable {
    let receipt:ServiceRecordedLaunch
    let state:RecordedServiceProcessState
    let sampledAt:Int64
}

// Read-only, off-loop reconciliation input. The caller supplies its reviewed
// fixed executable/profile and a journal-produced receipt, not an IPC PID.
// This probe grants no ownership/adoption, namespace lease or lifecycle permit.
struct RecordedServiceProcessProbe {
    private let service:ManagedService
    private let executable:VerifiedExecutable
    private let profileHash:String
    init(service:ManagedService,executable:VerifiedExecutable,profileHash:String)throws {
        guard WireScalar.sha256(profileHash) else {throw ServiceError.invalid}
        self.service=service;self.executable=executable;self.profileHash=profileHash
    }
    func capture(_ receipt:ServiceRecordedLaunch)->RecordedServiceProcessSample {
        let began=ProcessInfo.processInfo.systemUptime,stamp=HostResources.nowMilliseconds()
        var state:RecordedServiceProcessState = .unknown
        if receipt.service==service,receipt.identity.valid,WireScalar.uuid(receipt.id),WireScalar.uuid(receipt.boot),
           receipt.profileHash==profileHash,receipt.identity.sha256==executable.sha256 {
            do {
                if try HostBoot.identity() != receipt.boot {
                    state = .exited // Original local boot ended, NOT native terminality.
                } else if let entry=try KernelServiceProcessCensus().entry(pid:receipt.identity.pid) {
                    if entry.start != receipt.identity.start {state = .exited}
                    else if entry.uid==geteuid(),entry.realUID==geteuid(),entry.savedUID==geteuid() {
                        let peer=NativeControlPeer(pid:receipt.identity.pid,start:receipt.identity.start,executable:executable)
                        let observed=try ServiceIdentity.verified(peer:peer,expectedUID:geteuid(),deadline:began+1)
                        if observed==receipt.identity {state = .current(observed)}
                    }
                } else {state = .exited}
            } catch {state = .unknown}
        }
        let ended=HostResources.nowMilliseconds(),elapsed=ProcessInfo.processInfo.systemUptime-began
        guard geteuid()>0,getuid()==geteuid(),stamp>=0,ended>=stamp,ended<=ActivityPolicy.maximumTimestamp,
              elapsed.isFinite,elapsed>=0,elapsed<1 else {
            return RecordedServiceProcessSample(receipt:receipt,state:.unknown,sampledAt:stamp)
        }
        return RecordedServiceProcessSample(receipt:receipt,state:state,sampledAt:stamp)
    }
}
