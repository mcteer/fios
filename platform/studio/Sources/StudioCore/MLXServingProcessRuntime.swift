import Foundation
import Darwin

// Physical, code-only process start/observation primitive. This is not a
// service-intent interpreter or a native authority issuer. The installed
// factory/controller must retain and revalidate its reviewed native start
// reservation; no production issuer is wired. Never call this on the manager
// heartbeat. A source fixture supplies only its private, model-free process.
final class MLXServingProcessRuntime:@unchecked Sendable {
    private enum Phase {case idle,validating,spawning,running,uncertain}
    private let executable:VerifiedExecutable
    private let arguments:[String]
    private let environment:[String:String]
    private let profileHash:String
    private let validateReservation:@Sendable(ServiceLaunchCommand)throws->Void
    private let lock=NSLock()
    private var phase:Phase = .idle
    private var busy=false
    private var revoked=false
    private var activeID:String?
    private var process:Process?
    private var identity:ServiceIdentity?
    private var records:[String:SessionLaunchResult]=[:]
    private var delivery:(String,SessionLaunchResult)?

    convenience init(profile:MLXServingProcessProfile,arguments:[String],environment:[String:String],serviceProfileHash:String,
                     validateReservation:@escaping @Sendable(ServiceLaunchCommand)throws->Void)throws {
        // The caller supplies a separately reviewed preserved launch profile;
        // task/operator IPC cannot supply argv or environment values here.
        guard arguments.first=="serve" || (arguments.first?.hasPrefix("--")==true && arguments.contains("--serve")) else {throw RuntimeError.invalid}
        try self.init(executable:profile.server,arguments:arguments,environment:environment,serviceProfileHash:serviceProfileHash,validateReservation:validateReservation)
    }
    private init(executable:VerifiedExecutable,arguments:[String],environment:[String:String],serviceProfileHash:String,
                 validateReservation:@escaping @Sendable(ServiceLaunchCommand)throws->Void)throws {
        guard WireScalar.sha256(serviceProfileHash),arguments.count<=128,
              arguments.allSatisfy({!$0.contains("\0") && $0.utf8.count<=4096}),
              environment.count<=16,environment.allSatisfy({key,value in
                  ["PATH","HOME","LANG","LC_ALL","DYLD_LIBRARY_PATH","MLX_METAL_PATH","FIOS_MLX_SERVING_API_KEY"].contains(key) &&
                  !value.contains("\0") && value.utf8.count<=4096
              }),environment["PATH"]=="/usr/bin:/bin",environment["LANG"]=="C",environment["LC_ALL"]=="C" else {throw RuntimeError.invalid}
        guard let home=environment["HOME"],(try? CommandEnvironment.sanitized(["HOME":home])) != nil,
              arguments.reduce(0,{$0+$1.utf8.count+1})+environment.reduce(0,{$0+$1.key.utf8.count+$1.value.utf8.count+2})<=65536 else {throw RuntimeError.invalid}
        self.executable=executable;self.arguments=arguments;self.environment=environment
        profileHash=serviceProfileHash;self.validateReservation=validateReservation
    }
    func begin(_ command:ServiceLaunchCommand,deadline:TimeInterval)throws {
        let now=ProcessInfo.processInfo.systemUptime
        guard command.service == .mlx,WireScalar.uuid(command.id),command.expectedSHA256==executable.sha256,
              command.profileHash==profileHash,deadline.isFinite,deadline>now,deadline-now<=10 else {throw RuntimeError.invalid}
        lock.lock()
        guard !busy,delivery==nil,phase == .idle,process==nil,records.count<256,records[command.id]==nil else {lock.unlock();throw RuntimeError.capacity}
        busy=true;revoked=false;activeID=command.id;phase = .validating
        lock.unlock()
        Thread.detachNewThread { [self] in
            autoreleasepool {start(command,deadline:deadline)}
            // Retain the one worker slot through Foundation pool teardown.
            lock.lock();busy=false;lock.unlock()
        }
    }
    // Positive non-dispatch is possible only before the spawn edge. Keep the
    // real validation slot until its worker returns; cancellation cannot rearm it.
    @discardableResult func cancelValidation(id:String)->Bool {
        lock.lock();defer {lock.unlock()}
        guard activeID==id,phase == .validating,!revoked else {return false}
        revoked=true
        records[id] = .notSent;delivery=(id,.notSent)
        return true
    }
    func poll()->(id:String,result:SessionLaunchResult)? {
        lock.lock();defer {lock.unlock()}
        guard let found=delivery else {return nil};delivery=nil
        return (found.0,found.1)
    }
    func lookup(id:String)->SessionLaunchResult {
        lock.lock();defer {lock.unlock()}
        return records[id] ?? .uncertain
    }
    func accepts(_ command:ServiceLaunchCommand)->Bool {
        command.service == .mlx && WireScalar.uuid(command.id) && command.expectedSHA256==executable.sha256 && command.profileHash==profileHash
    }
    // A correlated controller lookup may consume the notification, never the
    // immutable receipt. Missing history remains uncertain across reconstruction.
    func acknowledgeResult(id:String)->SessionLaunchResult {
        lock.lock();defer {lock.unlock()}
        if delivery?.0==id {delivery=nil}
        return records[id] ?? .uncertain
    }
    var validationPending:Bool {
        lock.lock();defer {lock.unlock()};return busy
    }
    private func finish(_ id:String,_ result:SessionLaunchResult,phase next:Phase) {
        lock.lock();defer {lock.unlock()}
        if records[id]==nil {records[id]=result;delivery=(id,result)}
        phase=next
    }
    private func start(_ command:ServiceLaunchCommand,deadline:TimeInterval) {
        do {
            try executable.verify(deadline:deadline)
            try validateReservation(command)
        } catch {finish(command.id,.notSent,phase:.idle);return}
        lock.lock()
        guard !revoked,activeID==command.id,phase == .validating,ProcessInfo.processInfo.systemUptime<deadline else {
            lock.unlock();finish(command.id,.notSent,phase:.idle);return
        }
        let child=Process()
        child.executableURL=URL(fileURLWithPath:executable.path);child.arguments=arguments;child.environment=environment
        child.standardInput=FileHandle.nullDevice;child.standardOutput=FileHandle.nullDevice;child.standardError=FileHandle.nullDevice
        // Retain before the possibly blocking spawn call. Once entered, failure,
        // timeout or local reaping cannot manufacture a non-dispatch receipt.
        process=child;phase = .spawning
        lock.unlock()
        do {
            try child.run()
            let start=try WorkerResources.startIdentifier(pid:child.processIdentifier)
            let peer=NativeControlPeer(pid:child.processIdentifier,start:start,executable:executable)
            let observed=try ServiceIdentity.verified(peer:peer,expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+2)
            lock.lock();identity=observed;lock.unlock()
            finish(command.id,.started(observed),phase:.running)
        } catch {finish(command.id,.uncertain,phase:.uncertain)}
    }
    // Local capacity observation only. The caller's journal/native inference
    // claims and its next start reservation remain independent and unchanged.
    @discardableResult func retireKnownExited()->Bool {
        lock.lock();defer {lock.unlock()}
        guard !busy,phase == .running,let process,let identity,!process.isRunning else {return false}
        let absent:Bool
        if let current=try? WorkerResources.startIdentifier(pid:identity.pid) {absent=current != identity.start}
        else {errno=0;absent=kill(identity.pid,0)<0 && errno==ESRCH}
        guard absent else {return false}
        self.process=nil;self.identity=nil;activeID=nil;phase = .idle
        return true
    }
    // Intentionally no deinit signal, PID-only stop, automatic restart or
    // uncertainty reset. Disruptive control needs its separate native permit.
}
