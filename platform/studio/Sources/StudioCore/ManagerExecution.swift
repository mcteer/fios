import Foundation

// Trusted code-only composition, never decoded from IPC/CLI/environment.
// Snapshot closures must only read bounded caches: no CLI, network, database
// or model work on the serialized manager loop. The public entry supplies nil;
// installed execution still requires the native/profile/enrollment issuer.
enum ManagerVMSource {case unavailable,cached,ownedContainer}

struct ManagerExecutionPorts {
    let runtime:DockerRuntime?
    let approvedImages:Set<String>
    let workerFactory:PythonWorkerFactory?
    let vmSource:ManagerVMSource
    private let bindingSource:(String,String)->WorkerDispatchBinding?
    let nativeCapacityProven:()->Bool
    let admissionOpen:()->Bool
    private let resources:(Int64,Double?)->ResourceSample?
    private let resourceReader:(any VMResourceReading)?
    init(runtime:DockerRuntime?=nil,approvedImages:Set<String>,workerFactory:PythonWorkerFactory?=nil,
         vmSource:ManagerVMSource = .unavailable,resourceReader:(any VMResourceReading)?=nil,
         resources:@escaping (Int64,Double?)->ResourceSample?,
         binding:@escaping (String,String)->WorkerDispatchBinding?={_,_ in nil},
         nativeCapacityProven:@escaping ()->Bool={false},admissionOpen:@escaping ()->Bool={false})throws {
        guard approvedImages.count<=8,(!approvedImages.isEmpty || workerFactory != nil),
              approvedImages.isEmpty || runtime != nil,
              approvedImages.allSatisfy({$0.hasPrefix("sha256:") && $0.utf8.count==71 && WireScalar.sha256(String($0.dropFirst(7)))}) else {throw RuntimeError.invalid}
        self.runtime=runtime;self.approvedImages=approvedImages;self.workerFactory=workerFactory
        self.vmSource=vmSource;self.resourceReader=resourceReader;self.resources=resources
        self.bindingSource=binding;self.nativeCapacityProven=nativeCapacityProven;self.admissionOpen=admissionOpen
    }
    func binding(_ model:String,managerEpoch:String)->WorkerDispatchBinding? {
        guard WireScalar.uuid(managerEpoch),WireScalar.model(model),let value=bindingSource(model,managerEpoch),
              value.managerEpoch==managerEpoch,WireScalar.exactModel(value.canonicalModel,model) else {return nil}
        return value
    }
    func sample(now:Int64,cpu:Double?)->ResourceSample {
        guard let value=resources(now,cpu) else {
            // Losing an enrolled snapshot cannot substitute a different source
            // or infer free VM/native capacity from local process liveness.
            return ResourceSample(sampledAt:now,physical:ProcessInfo.processInfo.physicalMemory,
                available:nil,vmAvailable:nil,diskFree:nil,cpu:nil,pressure:.unknown,thermal:.unknown)
        }
        // The source kind is fixed by trusted composition. A supplied value
        // cannot silently become a VM envelope when its source is unavailable.
        return vmSource == .cached ? value:value.replacingVM(nil)
        // Admission independently validates freshness and resource limits.
    }
    func makeExecutor()throws->any SandboxExecuting {
        guard let runtime,!approvedImages.isEmpty else {return UnavailableSandboxRuntime()}
        return try SandboxExecutor(runtime:runtime,allowedImages:approvedImages,resourceReader:resourceReader)
    }
}
