import Foundation
import Darwin

struct ServingStopCommand:Sendable {
    let id:String
    let launchID:String
    let identity:ServiceIdentity
    let profileHash:String
}
// This describes only the owned local process, never native/device terminality.
enum ServingStopResult:Equatable,Sendable {case notSent,localExited,uncertain}

// Code-issued intent only, not native authority. There is no installed issuer.
// The private helper fixture can construct it in this file; future native
// issuance must retain the separate lifecycle reservation before doing so.
final class ServingStopIntent:@unchecked Sendable {
    let id:String
    let receipt:ServiceRecordedLaunch
    let desired:ServiceDesired
    private let lock=NSLock()
    private var consumed=false
    fileprivate init(receipt:ServiceRecordedLaunch,desired:ServiceDesired) {
        id=UUID().uuidString.lowercased();self.receipt=receipt;self.desired=desired
    }
    func consumeReservation()->Bool {
        lock.lock();defer {lock.unlock()};guard !consumed else {return false};consumed=true;return true
    }
}

// Physical, code-only process start/observation primitive. This is not a
// service-intent interpreter or a native authority issuer. The installed
// factory/controller must retain and revalidate its reviewed native start
// reservation; no production issuer is wired. Never call this on the manager
// heartbeat. A source fixture supplies only its private, model-free process.
final class MLXServingProcessRuntime:ServingProcessControlling,@unchecked Sendable {
    private enum Phase {case idle,validating,spawning,running,validatingStop,stopping,uncertain}
    private let executable:VerifiedExecutable
    private let arguments:[String]
    private let environment:[String:String]
    private let workingDirectory:String
    private let profileHash:String
    private let baseProfileHash:String
    var recoveryProfileHash:String {profileHash}
    private let validateReservation:@Sendable(ServiceLaunchCommand)throws->Void
    private let validateStopReservation:@Sendable(ServingStopCommand)throws->Void
    private let lock=NSLock()
    private var phase:Phase = .idle
    private var busy=false
    private var revoked=false
    private var activeID:String?
    private var process:ServingOwnedProcess?
    private var identity:ServiceIdentity?
    private var records:[String:SessionLaunchResult]=[:]
    private var delivery:(String,SessionLaunchResult)?
    private var activeStopID:String?
    private var stopRecords:[String:ServingStopResult]=[:]
    private var stopReceipts:[String:ServiceRecordedLaunch]=[:]
    private var stopDelivery:(String,ServingStopResult)?

    // Only protected installed metadata supplies native launch configuration.
    // Both independent retained-reservation validators remain mandatory. This
    // constructor neither obtains native authority nor starts the child.
    convenience init(configuration:NativeServingReviewedConfiguration,credential:String,serviceProfileHash:String,
                     validateReservation:@escaping @Sendable(ServiceLaunchCommand)throws->Void,
                     validateStopReservation:@escaping @Sendable(ServingStopCommand)throws->Void)throws {
        guard configuration.role == .supervisor else {throw ControlError.unauthorized}
        let inputs=try configuration.document.resolvingCredential(credential)
        try self.init(executable:configuration.processProfile.server,arguments:inputs.arguments,environment:inputs.environment,
            workingDirectory:inputs.workingDirectory,serviceProfileHash:serviceProfileHash,reviewedConfigurationSHA256:configuration.policySHA256,
            validateReservation:validateReservation,validateStopReservation:validateStopReservation)
    }
    // Same-file validation fixture only; ordinary code cannot substitute a bare
    // process profile for protected reviewed launch metadata.
    private convenience init(profile:MLXServingProcessProfile,arguments:[String],environment:[String:String],workingDirectory:String,serviceProfileHash:String,
                     validateReservation:@escaping @Sendable(ServiceLaunchCommand)throws->Void,
                     validateStopReservation:@escaping @Sendable(ServingStopCommand)throws->Void)throws {
        // The caller supplies a separately reviewed preserved launch profile;
        // task/operator IPC cannot supply argv, environment or working directory.
        guard arguments.first=="serve" || (arguments.first?.hasPrefix("--")==true && arguments.contains("--serve")) else {throw RuntimeError.invalid}
        let inputs=try NativeServingLaunchInputs(arguments:arguments,environment:environment,workingDirectory:workingDirectory)
        try self.init(executable:profile.server,arguments:inputs.arguments,environment:inputs.environment,workingDirectory:inputs.workingDirectory,serviceProfileHash:serviceProfileHash,validateReservation:validateReservation,validateStopReservation:validateStopReservation)
    }
    private init(executable:VerifiedExecutable,arguments:[String],environment:[String:String],workingDirectory:String,serviceProfileHash:String,reviewedConfigurationSHA256:String?=nil,
                 validateReservation:@escaping @Sendable(ServiceLaunchCommand)throws->Void,
                 validateStopReservation:@escaping @Sendable(ServingStopCommand)throws->Void)throws {
        guard WireScalar.sha256(serviceProfileHash),arguments.count<=128,
              workingDirectory.hasPrefix("/"),workingDirectory.utf8.count<Int(MAXPATHLEN),!workingDirectory.contains("\0"),
              !workingDirectory.contains("//"),(workingDirectory=="/" || !workingDirectory.hasSuffix("/")),
              !workingDirectory.split(separator:"/").contains(where:{$0=="." || $0==".."}),
              arguments.allSatisfy({!$0.contains("\0") && $0.utf8.count<=4096}),
              environment.count<=16,environment.allSatisfy({key,value in
                  ["PATH","HOME","LANG","LC_ALL","DYLD_LIBRARY_PATH","MLX_METAL_PATH","FIOS_MLX_SERVING_API_KEY"].contains(key) &&
                  !value.contains("\0") && value.utf8.count<=4096
              }),environment["PATH"]=="/usr/bin:/bin",environment["LANG"]=="C",environment["LC_ALL"]=="C" else {throw RuntimeError.invalid}
        guard let home=environment["HOME"],(try? CommandEnvironment.sanitized(["HOME":home])) != nil,
              workingDirectory.utf8.count+executable.path.utf8.count+1+arguments.reduce(0,{$0+$1.utf8.count+1})+environment.reduce(0,{$0+$1.key.utf8.count+$1.value.utf8.count+2})<=65536 else {throw RuntimeError.invalid}
        self.executable=executable;self.arguments=arguments;self.environment=environment;self.workingDirectory=workingDirectory
        baseProfileHash=serviceProfileHash
        profileHash=try ServiceLaunchProfile.nativeDigest(base:serviceProfileHash,arguments:arguments,environment:environment,workingDirectory:workingDirectory,reviewedConfigurationSHA256:reviewedConfigurationSHA256)
        self.validateReservation=validateReservation;self.validateStopReservation=validateStopReservation
    }
    func begin(_ command:ServiceLaunchCommand,deadline:TimeInterval)throws {
        let now=ProcessInfo.processInfo.systemUptime
        guard command.service == .mlx,WireScalar.uuid(command.id),command.expectedSHA256==executable.sha256,
              command.profileHash==profileHash,deadline.isFinite,deadline>now,deadline-now<=10 else {throw RuntimeError.invalid}
        lock.lock()
        guard !busy,delivery==nil,stopDelivery==nil,phase == .idle,process==nil,records.count<256,records[command.id]==nil,stopRecords[command.id]==nil else {lock.unlock();throw RuntimeError.capacity}
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
    func acceptsBaseProfile(_ base:String,expectedSHA256:String)->Bool {baseProfileHash==base && executable.sha256==expectedSHA256}
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
        let child=ServingOwnedProcess(executable:executable,arguments:arguments,environment:environment,workingDirectory:workingDirectory)
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

    // Internal code-only entry, with no caller-selected PID/path/force. The
    // installed issuer must retain its identity-bound admission-closed native
    // lifecycle reservation through the operation. Its callback is read-only
    // validation of that retained reservation, never an actuator/acquirer.
    // No production issuer exists.
    func acceptsStopReceipt(_ receipt:ServiceRecordedLaunch)->Bool {
        receipt.service == .mlx && receipt.profileHash==profileHash && receipt.identity.valid &&
        receipt.identity.sha256==executable.sha256 && WireScalar.uuid(receipt.id) && WireScalar.uuid(receipt.boot)
    }
    func beginStop(id:String,matching receipt:ServiceRecordedLaunch,deadline:TimeInterval)throws {
        let now=ProcessInfo.processInfo.systemUptime
        guard WireScalar.uuid(id),deadline.isFinite,deadline>now,deadline-now<=10,acceptsStopReceipt(receipt),
              receipt.boot == (try HostBoot.identity()) else {throw RuntimeError.invalid}
        lock.lock()
        guard !busy,delivery==nil,stopDelivery==nil,phase == .running,
              let child=process,let identity,let launchID=activeID,id != launchID,
              identity==receipt.identity,launchID==receipt.id,
              stopReceipts.count<256,stopReceipts[id]==nil,stopRecords[id]==nil,records[id]==nil else {lock.unlock();throw RuntimeError.capacity}
        let command=ServingStopCommand(id:id,launchID:launchID,identity:identity,profileHash:profileHash)
        stopReceipts[id]=receipt
        activeStopID=id;revoked=false;busy=true;phase = .validatingStop
        lock.unlock()
        Thread.detachNewThread { [self] in
            autoreleasepool {stop(command,child:child,deadline:deadline)}
            lock.lock();busy=false;lock.unlock()
        }
    }
    @discardableResult func cancelStopValidation(id:String,matching receipt:ServiceRecordedLaunch)->Bool {
        lock.lock();defer {lock.unlock()}
        guard stopReceipts[id]==receipt,activeStopID==id,phase == .validatingStop,!revoked else {return false}
        revoked=true;stopRecords[id] = .notSent;stopDelivery=(id,.notSent)
        return true // Retain the real validator slot until its worker returns.
    }
    func pollStop()->(id:String,result:ServingStopResult)? {
        lock.lock();defer {lock.unlock()}
        guard let found=stopDelivery else {return nil};stopDelivery=nil
        return (found.0,found.1)
    }
    func lookupStop(id:String)->ServingStopResult {
        lock.lock();defer {lock.unlock()};return stopRecords[id] ?? .uncertain
    }
    func acknowledgeStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult {
        lock.lock();defer {lock.unlock()}
        guard stopReceipts[id]==receipt else {return .uncertain}
        if stopDelivery?.0==id {stopDelivery=nil}
        return stopRecords[id] ?? .uncertain
    }
    // Used only after beginStop rejected before entering a new operation.
    // Seal the ID so that the same rejected request cannot materialize later.
    func rejectedStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult {
        guard acceptsStopReceipt(receipt),WireScalar.uuid(id),id != receipt.id else {return .uncertain}
        lock.lock();defer {lock.unlock()}
        if let original=stopReceipts[id],original != receipt {return .uncertain}
        if let known=stopRecords[id] {return known}
        guard activeStopID != id,records[id]==nil,stopReceipts.count<256 else {return .uncertain}
        stopReceipts[id]=receipt;stopRecords[id] = .notSent;return .notSent
    }
    private func finishStop(_ id:String,_ result:ServingStopResult,phase next:Phase) {
        lock.lock();defer {lock.unlock()}
        if stopRecords[id]==nil {stopRecords[id]=result;stopDelivery=(id,result)}
        phase=next;activeStopID=nil
        if result == .localExited {process=nil;identity=nil;activeID=nil}
    }
    private func stop(_ command:ServingStopCommand,child:ServingOwnedProcess,deadline:TimeInterval) {
        do {
            let peer=NativeControlPeer(pid:command.identity.pid,start:command.identity.start,executable:executable)
            guard try ServiceIdentity.verified(peer:peer,expectedUID:geteuid(),deadline:ProcessInfo.processInfo.systemUptime+1)==command.identity else {throw RuntimeError.identity}
            try validateStopReservation(command)
        } catch {finishStop(command.id,.notSent,phase:.running);return}
        lock.lock()
        guard !revoked,phase == .validatingStop,activeStopID==command.id,activeID==command.launchID,
              process === child,identity==command.identity,ProcessInfo.processInfo.systemUptime<deadline else {
            lock.unlock();finishStop(command.id,.notSent,phase:.running);return
        }
        phase = .stopping
        lock.unlock()
        do {try child.terminate(expected:command.identity,deadline:deadline)}
        catch {finishStop(command.id,.uncertain,phase:.uncertain);return}
        let end=min(deadline,ProcessInfo.processInfo.systemUptime+2)
        while ProcessInfo.processInfo.systemUptime<end {
            if !child.isRunning {finishStop(command.id,.localExited,phase:.idle);return}
            Thread.sleep(forTimeInterval:0.005)
        }
        // No SIGKILL/retry/reset: the child and native reservation may remain
        // live. A timeout cannot release capacity or independent native claims.
        finishStop(command.id,.uncertain,phase:.uncertain)
    }
    // Local capacity observation only. The caller's journal/native inference
    // claims and its next start reservation remain independent and unchanged.
    @discardableResult func retireKnownExited()->Bool {
        lock.lock();defer {lock.unlock()}
        guard !busy,(phase == .running || phase == .uncertain),let process else {return false}
        let locallyExited = !process.isRunning // WNOHANG for this original child only.
        // Reap local resources even after an uncertain operation, but keep its
        // phase, capacity, original records and independent native uncertainty.
        guard phase == .running,let identity,locallyExited else {return false}
        let absent:Bool
        if let current=try? WorkerResources.startIdentifier(pid:identity.pid) {absent=current != identity.start}
        else {errno=0;absent=kill(identity.pid,0)<0 && errno==ESRCH}
        guard absent else {return false}
        self.process=nil;self.identity=nil;activeID=nil;phase = .idle
        return true
    }
    // No deinit signal, PID-only stop, automatic restart or uncertainty reset.
    // A fresh start always revalidates its independent native reservation.
}
