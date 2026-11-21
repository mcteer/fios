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
    private let source:any ServiceProcessCensusReading
    private let now:()->Int64
    private let uptime:()->TimeInterval
    init(service:ManagedService,executable:VerifiedExecutable,profileHash:String,
         source:any ServiceProcessCensusReading=KernelServiceProcessCensus(),
         now:@escaping ()->Int64=HostResources.nowMilliseconds,
         uptime:@escaping ()->TimeInterval={ProcessInfo.processInfo.systemUptime})throws {
        guard WireScalar.sha256(profileHash) else {throw ServiceError.invalid}
        self.service=service;self.executable=executable;self.profileHash=profileHash
        self.source=source;self.now=now;self.uptime=uptime
    }
    func capture(_ receipt:ServiceRecordedLaunch)->RecordedServiceProcessSample {
        let began=uptime(),stamp=now()
        var state:RecordedServiceProcessState = .unknown
        var lastWall=stamp,lastTick=began
        func checkpoint()->Bool {
            let wall=now(),tick=uptime()
            guard wall>=lastWall,wall<=ActivityPolicy.maximumTimestamp,wall-stamp<=1000,
                  tick.isFinite,tick>=lastTick,tick-began<1 else {return false}
            lastWall=wall;lastTick=tick
            return true
        }
        if geteuid()>0,getuid()==geteuid(),(0...ActivityPolicy.maximumTimestamp).contains(stamp),began.isFinite,began>=0,
           receipt.service==service,receipt.identity.valid,WireScalar.uuid(receipt.id),WireScalar.uuid(receipt.boot),
           receipt.profileHash==profileHash,receipt.identity.sha256==executable.sha256 {
            do {
                let boot=try HostBoot.identity()
                guard checkpoint() else {return RecordedServiceProcessSample(receipt:receipt,state:.unknown,sampledAt:stamp)}
                if boot != receipt.boot {
                    state = .exited // Original local boot ended, NOT native terminality.
                } else if let entry=try source.entry(pid:receipt.identity.pid) {
                    guard checkpoint(),entry.pid==receipt.identity.pid,entry.start>0 else {
                        return RecordedServiceProcessSample(receipt:receipt,state:.unknown,sampledAt:stamp)
                    }
                    if entry.start != receipt.identity.start {state = .exited}
                    else if entry.uid==geteuid(),entry.realUID==geteuid(),entry.savedUID==geteuid() {
                        let observed=try source.verify(entry,executable:executable,uid:geteuid(),deadline:began+1)
                        if observed==receipt.identity {state = .current(observed)}
                    }
                } else {state = .exited}
            } catch {state = .unknown}
        }
        guard (0...ActivityPolicy.maximumTimestamp).contains(stamp),began.isFinite,began>=0,checkpoint() else {
            return RecordedServiceProcessSample(receipt:receipt,state:.unknown,sampledAt:stamp)
        }
        return RecordedServiceProcessSample(receipt:receipt,state:state,sampledAt:stamp)
    }
}
