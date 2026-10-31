import Foundation
import Darwin

extension ServiceIdentity {
    // Trusted enrolled profile input only, never IPC-selected PID/path/UID.
    // Read-only precondition: does NOT grant lifecycle/force/terminal authority
    // or attest an installed signing/profile/immutable-artifact enrollment.
    static func verified(peer:NativeControlPeer,expectedUID:uid_t,deadline:TimeInterval) throws -> ServiceIdentity {
        let now=ProcessInfo.processInfo.systemUptime
        guard peer.pid>1,expectedUID>0,expectedUID==getuid(),getuid()==geteuid(),
              deadline.isFinite,deadline>now,deadline-now<=2 else {throw ServiceError.invalid}
        func checkPrincipal() throws {
            var info=proc_bsdinfo()
            let size=Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(peer.pid,PROC_PIDTBSDINFO,0,&info,size)==size,
                  info.pbi_pid==UInt32(peer.pid),info.pbi_uid==expectedUID,
                  info.pbi_ruid==expectedUID,info.pbi_svuid==expectedUID else {throw ServiceError.invalid}
        }
        try checkPrincipal()
        // Existing no-follow bounded FD hash/path/kernel-start verification.
        // Caller must retain the reviewed immutable artifact/profile binding;
        // a path hash alone must not be promoted to loaded-code attestation.
        try peer.verify(deadline:deadline)
        try checkPrincipal()
        guard try WorkerResources.startIdentifier(pid:peer.pid)==peer.start,
              ProcessInfo.processInfo.systemUptime<deadline else {throw ServiceError.invalid}
        return ServiceIdentity(pid:peer.pid,start:peer.start,sha256:peer.executable.sha256)
    }
}
