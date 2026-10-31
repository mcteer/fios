import Foundation
import Darwin
import CryptoKit

public enum ManagerRuntime {
    // Local developer/installed entry point. Production installation must pin
    // reviewed binaries and use a private operator-owned state directory.
    public static func run(directory:URL,telemetry:any PlatformTelemetry=NoopPlatformTelemetry()) throws {
        try run(directory:directory,nativeControl:nil,telemetry:telemetry)
    }
    // No production issuer yet: only reviewed native enrollment may supply
    // this internal client. Never construct it from operator/model payloads.
    static func run(directory:URL,nativeControl:NativeControlClient?,serviceObservations:ServiceObservationCache?=nil,serviceControl:SessionControlClient?=nil,drainObservations:ServiceDrainObservationCache?=nil,execution:ManagerExecutionPorts?=nil,telemetry:any PlatformTelemetry=NoopPlatformTelemetry()) throws {
        guard geteuid() != 0 else { throw ControlError.unauthorized }
        umask(0o077)
        let journal=try Journal(directory:directory)
        try journal.recoverWorkerMetadata()
        let migrationHeld=journal.migrationHeld
        let activeExecution=migrationHeld ? nil:execution
        let activeServiceControl=migrationHeld ? nil:serviceControl
        let activeNativeControl=migrationHeld ? nil:nativeControl
        // Trusted code-only injection. The public entry point has no issuer;
        // missing observations never become absence or a launch permission.
        let serviceRecovery=try activeServiceControl.map {try ServiceRecoveryController(journal:journal,approvedHashes:$0.applicationHashes)}
        let serviceQueue=activeServiceControl.map {AsyncSessionControl(client:$0)}
        var serviceCursor=0,serviceTransportUnavailable=false
        var nativeMaintenance=NativeMaintenanceCoordinator(journal:journal)
        let nativeQueue=activeNativeControl.map {AsyncNativeControl(client:$0)}
        let nativeCoverage:NativeCoverage = nativeQueue == nil ? .unsupported:.unknown
        var nativeDiagnostics=NativeControlDiagnostics(configured:nativeQueue != nil)
        func enqueueNative(_ command:NativeMaintenanceCommand) {
            guard let nativeQueue else {return}
            do {try nativeQueue.submit(command);nativeDiagnostics.begin()} catch {nativeMaintenance.failed(id:command.id);nativeDiagnostics.failed()}
        }
        if nativeQueue != nil,let command=try nativeMaintenance.beginReconciliation() {enqueueNative(command)}
        var admission=AdmissionPolicy()
        let workerRecovery=try WorkerReconciler(journal:journal,admission:&admission)
        let audit=try AuditLog(directory:directory.appendingPathComponent("audit"),telemetry:telemetry)
        let artifacts=AsyncArtifacts(store:try ArtifactStore(directory:directory.appendingPathComponent("artifacts")))
        let tasks=TaskController(journal:journal,broker:ModelBroker(journal:journal,factory:activeExecution?.workerFactory))
        let executor:any SandboxExecuting = try activeExecution?.makeExecutor() ?? UnavailableSandboxRuntime()
        let jobs=JobController(journal:journal,executor:executor,collectVM:activeExecution?.vmSource == .ownedContainer)
        let sandboxes=SandboxTaskController(journal:journal,jobs:jobs,tasks:tasks,artifacts:artifacts,
            socket:activeExecution?.runtime?.socket ?? "/var/empty/fios-runtime-unenrolled.sock",peerUID:geteuid(),endpointPolicy:activeExecution?.runtime?.endpointPolicy)
        let taskCommands=TaskCommands(journal:journal,tasks:tasks,sandbox:sandboxes,artifacts:artifacts,
            approvedImages:activeExecution?.approvedImages ?? [],enrolled:activeExecution != nil,peerUID:geteuid(),admissionOpen:activeExecution?.admissionOpen ?? {false})
        func applyingVM(to sample:ResourceSample,now:Int64)->ResourceSample {
            if activeExecution?.vmSource == .cached {return sample}
            return jobs.applyingVM(to:sample,now:now)
        }
        func timestamp()->Int64 { Int64(Date().timeIntervalSince1970*1000) }
        try audit.record(.started,now:timestamp())
        defer { try? audit.record(.stopped,now:timestamp()) }
        let observation=try UnixControlSocket(path:directory.appendingPathComponent("observe.sock").path)
        let control=try UnixControlSocket(path:directory.appendingPathComponent("control.sock").path)
        let taskSocket=try UnixControlSocket(path:directory.appendingPathComponent("task.sock").path)
        let listeners=[observation,control,taskSocket]
        let roles:[ControlRole]=[.observer,.operator,.task]
        let epoch=UUID().uuidString.lowercased()
        let drainer=try (migrationHeld ? nil:drainObservations).map {try ServiceDrainController(journal:journal,tasks:tasks,managerEpoch:epoch,observations:$0)}
        func binding(_ model:String)->WorkerDispatchBinding? {activeExecution?.binding(model,managerEpoch:epoch)}
        func bindingForJob(_ id:String)->WorkerDispatchBinding? {
            guard let model=tasks.canonicalModel(forJob:id) else {return nil}
            return binding(model)
        }
        func digest(_ value:String)->String { SHA256.hash(data:Data(value.utf8)).map { String(format:"%02x",$0) }.joined() }
        let endpointHash=digest("http://127.0.0.1:11234/v1")
        let profileHash=digest("fios009-development-native-unsupported")
        var sequence=0
        var sampledAt:Int64=0
        var activitySequence:Int64=0
        let progress=directory.appendingPathComponent("progress.json")
        let start=ProcessInfo.processInfo.systemUptime
        let boot=try HostBoot.identity()
        var lastHeartbeat:TimeInterval = -2
        var cpuSampler=CPUSampler()
        var resourceSample=activeExecution?.sample(now:timestamp(),cpu:nil) ?? HostResources.sample(statePath:directory.path)
        telemetry.resources(resourceSample)
        var gpuSampledAt:Int64?=timestamp()
        var gpuSample=GPUResources.sample()
        if gpuSample == nil {gpuSampledAt=nil}
        telemetry.gpu(gpuSample,sampledAt:gpuSampledAt)
        let termination=Termination()
        var clients:[PendingControl]=[]
        while !termination.requested {
            // CLI run loops have no AppKit autorelease-pool turn.
            try autoreleasepool {
            let now=ProcessInfo.processInfo.systemUptime
            if let result=serviceQueue?.poll(),let serviceRecovery {
                switch result.value {
                case .success(let value):
                    try serviceRecovery.receive(result.request,result:value)
                    serviceTransportUnavailable=false
                case .failure:serviceTransportUnavailable=true // Preserve pending intent.
                }
            }
            if let result=nativeQueue?.poll() {
                switch result.value {
                case .success(let value):
                    do {
                        let command=try nativeMaintenance.receive(id:result.id,value:value)
                        nativeDiagnostics.completed(value,receivedAt:result.receivedAt)
                        if let command {enqueueNative(command)}
                    } catch {nativeMaintenance.failed(id:result.id);nativeDiagnostics.failed()}
                case .failure: nativeMaintenance.failed(id:result.id);nativeDiagnostics.failed()
                }
            }
            try workerRecovery.poll(now:Int64(now*1000),admission:&admission,failedLaunches:tasks.failedLaunches)
            try drainer?.pollAll(now:timestamp(),uptime:Int64(now*1000))
            resourceSample=applyingVM(to:resourceSample,now:timestamp())
            let updates=try sandboxes.tick(now:timestamp(),uptime:now,sample:artifacts.reservingDisk(in:resourceSample),admission:&admission,source:bindingForJob,nativeCapacityProven:activeExecution?.nativeCapacityProven() ?? false)
            resourceSample=applyingVM(to:resourceSample,now:timestamp())
            try taskCommands.tick(now:timestamp(),uptime:Int64(now*1000),artifactResults:updates.artifactResults,output:updates.output,model:updates.model,finished:updates.finished)
            if now - lastHeartbeat >= 2 {
                sequence+=1;sampledAt=timestamp()
                if let serviceRecovery,let serviceQueue,serviceQueue.available {
                    let services=ManagedService.allCases
                    for offset in 0..<services.count {
                        let index=(serviceCursor+offset)%services.count,service=services[index]
                        guard let desired=ServiceDesired(rawValue:try journal.desired(service:service.rawValue)) else {throw ServiceError.invalid}
                        if let request=try serviceRecovery.next(service:service,desired:desired,observation:serviceObservations?.snapshot(for:service),now:sampledAt,tick:Int64(now*1000)) {
                            try serviceQueue.submit(request)
                            serviceCursor=(index+1)%services.count
                            break // One exchange, no hidden queue or replay.
                        }
                    }
                }
                let cpu=cpuSampler.observe(ticks:CPUSampler.readTicks(),now:sampledAt)
                resourceSample=applyingVM(to:activeExecution?.sample(now:sampledAt,cpu:cpu) ?? HostResources.sample(statePath:directory.path,measuredCPU:cpu),now:sampledAt)
                telemetry.resources(resourceSample)
                gpuSampledAt=timestamp()
                gpuSample=GPUResources.sample()
                if gpuSample == nil {gpuSampledAt=nil}
                telemetry.gpu(gpuSample,sampledAt:gpuSampledAt)
                do {try artifacts.expire(request:UUID().uuidString.lowercased(),now:timestamp())}
                catch ArtifactServiceFailure.capacity {} // Finite I/O slots, retry maintenance next cycle.
                try journal.expireTerminalJobs(now:timestamp())
                try journal.recoverWorkerMetadata()
                let artifactUsage=artifacts.statistics
                let cleanup=jobs.cleanupObservation(now:timestamp())
                telemetry.workload(WorkloadTelemetry.sample(journal:journal,artifactBytes:artifactUsage.bytes,
                    artifactJobs:artifactUsage.jobs,now:timestamp(),cleanupPending:cleanup.pending,cleanupWaitMilliseconds:cleanup.wait))
                let body:[String:Any] = ["version":1,"epoch":epoch,"pid":getpid(),"progress":now]
                try JSONSerialization.data(withJSONObject:body,options:[.sortedKeys]).write(to:progress,options:.atomic)
                lastHeartbeat=now
            }
            var polls=listeners.map {pollfd(fd:$0.fd,events:Int16(POLLIN),revents:0)}
            let n=poll(&polls,nfds_t(polls.count),100)
            if n < 0 && errno == EINTR { return }
            guard n >= 0 else { throw ControlError.internal_error }
            for index in polls.indices where polls[index].revents & Int16(POLLIN) != 0 {
                let socket=listeners[index]
                guard let fd=try socket.acceptPeer() else { continue }
                if clients.count>=16 { close(fd);continue }
                clients.append(PendingControl(fd:fd,role:roles[index],now:ProcessInfo.processInfo.systemUptime))
            }
            for client in clients {
                do {
                    guard let bytes=try client.read(now:ProcessInfo.processInfo.systemUptime) else {
                        try client.flush(now:ProcessInfo.processInfo.systemUptime);continue
                    }
                    let request=try ControlRequest.decode(bytes)
                    guard client.role.allows(request.operation) else { throw ControlError.unauthorized }
                    let requestedAt=timestamp(),requestResources=artifacts.reservingDisk(in:applyingVM(to:resourceSample,now:requestedAt))
                    var response:[String:Any] = ["version":1,"id":request.id,"ok":true,"epoch":epoch]
                    switch request.operation {
                    case .status:
                        guard request.payload.isEmpty else { throw ControlError.invalid_request }
                        let session=SessionState.read(directory:directory,boot:boot,now:Int64(now*1000))
                        response["session"]=["state":session?.console == true ? "available" : "waiting_session",
                                             "lifecycle_enabled":false]
                        response["state"]="ready"
                        response["observability"]=["instrumentation":telemetry.instrumentation]
                        response["uptime_ms"]=Int((now-start)*1000)
                        response["unresolved_requests"]=try journal.unresolvedCount()
                        response["worker_reservations"]=try journal.activeLaunchCount()
                        response["worker_recovery"]=workerRecovery.degraded ? "degraded" : (workerRecovery.pending>0 ? "recovering" : "ready")
                        response["capabilities"]=["local_status","resources","desired_state","owner_task_status","owner_artifact_streams"]
                        response["service_recovery"]=serviceQueue == nil ? "disabled":(serviceTransportUnavailable ? "degraded":"configured")
                        var serviceStates:[String:Any]=[:]
                        for service in ManagedService.allCases {
                            let desired=try journal.desired(service:service.rawValue)
                            guard let typed=ServiceDesired(rawValue:desired) else {throw ControlError.invalid_request}
                            // No production observation issuer is enrolled. A
                            // failed/missing adapter remains unknown, not absent.
                            var details=ServiceStatusPolicy.summary(desired:typed,observation:serviceObservations?.snapshot(for:service),launchPending:serviceRecovery?.isPending(service) ?? false,now:requestedAt)
                            if let progress=drainer?.status(service:service) {details["drain"]=ServiceDrainController.summary(progress)}
                            serviceStates[service.rawValue]=details
                        }
                        response["services"]=serviceStates
                        response["native_admissions"]=nativeQueue == nil ? "unsupported":nativeMaintenance.phase.rawValue
                        response["native_control"]=nativeDiagnostics.summary(now:requestedAt)
                        response["migration_maintenance"]=migrationHeld
                        response["native_activity"]=nativeCoverage.rawValue
                        response["sandbox_admission"]=activeExecution == nil ? "disabled":"configured"
                        response["artifact_bytes"]=artifacts.statistics.bytes
                        response["artifact_jobs"]=artifacts.statistics.jobs
                        response["runtime_cleanup"]=jobs.cleanupStatus(now:requestedAt)
                    case .resources:
                        guard request.payload.isEmpty else { throw ControlError.invalid_request }
                        let telemetry=try ResourceObservationExport.encode(sample:requestResources,gpu:gpuSample,gpuSampledAt:gpuSampledAt,
                            now:requestedAt,epoch:epoch,sequence:Int64(sequence),vmEpoch:jobs.vmEpoch(now:requestedAt))
                        response["resources"]=telemetry.resources
                        response["resource_observation"]=telemetry.observation
                    case .activity:
                        guard request.payload.isEmpty else { throw ControlError.invalid_request }
                        guard activitySequence<WireScalar.maximumTimestamp else {throw ControlError.internal_error}
                        activitySequence+=1
                        response["coverage"]=nativeCoverage.rawValue; response["activity"]="unknown"
                        let ownership=try journal.activityOwnership()
                        var context=ActivityObservationContext(sampledAt:requestResources.sampledAt,pressure:requestResources.pressure,thermal:requestResources.thermal)
                        for service in ManagedService.allCases {
                            guard let desired=ServiceDesired(rawValue:try journal.desired(service:service.rawValue)) else {throw ControlError.internal_error}
                            let observed=ServiceStatusPolicy.observed(desired:desired,observation:serviceObservations?.snapshot(for:service),launchPending:serviceRecovery?.isPending(service) ?? false,now:requestedAt)
                            if service == .mlx {context.mlx=observed}else {context.orbstack=observed}
                        }
                        let capture=nativeDiagnostics.capture(now:requestedAt)
                        let metadata=ActivityObservationMetadata(host:ProcessInfo.processInfo.hostName,endpointHash:endpointHash,profileHash:profileHash,managerEpoch:epoch,
                            nativeEpoch:capture?.instance ?? "unknown:"+epoch,sequence:activitySequence,sampledAt:requestedAt,
                            nativeSequence:capture.map{Int64($0.sequence)},nativeSampledAt:capture?.sampledAt)
                        let frame=try ActivityObservationExport.encode(metadata:metadata,coverage:nativeCoverage,sourceCoverage:nativeCoverage,
                            localModels:ownership.models,localUncertain:ownership.uncertain,context:context)
                        response["observation"]=try JSONSerialization.jsonObject(with:frame)
                    case .jobCreate,.jobStatus,.jobRenew,.jobCancel,.modelRequest,.artifactRead:
                        response["result"]=try taskCommands.handle(request,role:client.role,sample:requestResources,admission:&admission,
                            binding:binding,nativeCapacityProven:activeExecution?.nativeCapacityProven() ?? false,now:requestedAt,uptime:Int64(now*1000))
                    case .serviceDrain:
                        guard OperatorServiceCommand.valid(operation:request.operation,payload:request.payload),
                              let raw=request.payload["service"] as? String,let service=ManagedService(rawValue:raw) else {throw ControlError.invalid_request}
                        guard let drainer else {
                            response["ok"]=false;response["error"]="native_unsupported";response["applied"]=false;break
                        }
                        do {
                            let progress=try drainer.begin(service:service,role:client.role,now:requestedAt,uptime:Int64(now*1000))
                            if service == .mlx,nativeQueue != nil,let command=try nativeMaintenance.beginReconciliation() {enqueueNative(command)}
                            response["drain"]=ServiceDrainController.summary(progress)
                            response["maintenance_applied"]=true;response["native_action_applied"]=false
                        }catch ServiceError.stale {
                            response["ok"]=false;response["error"]="native_unsupported";response["applied"]=false
                        }catch ServiceError.invalid {
                            response["ok"]=false;response["error"]="native_unsupported";response["applied"]=false
                        }
                    case .serviceForce:
                        guard OperatorServiceCommand.valid(operation:request.operation,payload:request.payload) else {throw ControlError.invalid_request}
                        // No trusted all-backend scope issuer/actuator is enrolled.
                        // Never mint confirmations from caller-supplied hashes or
                        // convert observation/timeout into native action authority.
                        response["ok"]=false;response["error"]="native_unsupported";response["applied"]=false
                    case .serviceDesired:
                        guard OperatorServiceCommand.valid(operation:request.operation,payload:request.payload),
                              Set(request.payload.keys) == Set(["service","desired"]),
                              let service=request.payload["service"] as? String,
                              let desired=request.payload["desired"] as? String else { throw ControlError.invalid_request }
                        if service==ManagedService.mlx.rawValue,let typed=ServiceDesired(rawValue:desired) {
                            try nativeMaintenance.setDesired(typed,role:client.role)
                            if nativeQueue != nil,let command=try nativeMaintenance.beginReconciliation() {enqueueNative(command)}
                        } else {try journal.setDesired(service:service,desired:desired)}
                        if desired == ServiceDesired.running.rawValue,let typed=ManagedService(rawValue:service) {drainer?.supersede(service:typed)}
                        try audit.record(.desiredChanged,now:timestamp())
                        response["desired"]=desired
                        // Persisting intent is not a claim that a native action occurred.
                        response["applied"]=false
                    default:
                        response["ok"]=false; response["error"]="native_unsupported"
                    }
                    try client.respond(JSONSerialization.data(withJSONObject:response),now:ProcessInfo.processInfo.systemUptime)
                    try client.flush(now:ProcessInfo.processInfo.systemUptime)
                } catch {
                    let code:String
                    switch error {
                    case let error as ControlError:code=error.rawValue
                    case let error as TaskCommandError:code=error.rawValue
                    case JournalError.conflict:code="job_conflict"
                    case JournalError.trackingLimit:code="tracking_limit"
                    case AdmissionError.expired:code="lease_expired"
                    case AdmissionError.stale:code="stale_observation"
                    case AdmissionError.capacity:code="resource_limit"
                    case ArtifactError.unauthorized:code="unauthorized"
                    case ArtifactError.unavailable:code="invalid_request"
                    case ArtifactServiceFailure.capacity,ArtifactError.capacity:code="resource_limit"
                    case ArtifactError.invalid,TransferError.invalid,TransferError.hash,TransferError.expired:code="invalid_request"
                    case PolicyError.invalidObservation:code="native_unsupported"
                    default:code="internal"
                    }
                    let data=try JSONSerialization.data(withJSONObject:["version":1,"ok":false,"error":code])
                    if !client.closed {
                        do {
                            try client.respond(data,now:ProcessInfo.processInfo.systemUptime)
                            try client.flush(now:ProcessInfo.processInfo.systemUptime)
                        } catch { client.close() }
                    }
                }
            }
            clients.removeAll(where:{$0.closed})
            }
        }
    }
}
