import Foundation
import CoreFoundation

enum SandboxExecutionValue:Sendable { case created(String),observed(SandboxPresence,exitCode:Int? = nil,oom:Bool = false),acknowledged }
enum SandboxExecutionFailure:Error,Sendable { case unavailable,identity,unapprovedImage }
struct SandboxExecution:Sendable {
    let job:String
    let result:Result<SandboxExecutionValue,SandboxExecutionFailure>
}
protocol SandboxExecuting:AnyObject {
    func submit(job:String,command:SandboxCommand) throws
    func drain()->[SandboxExecution]
    func submitResources(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws
    func drainResources()->[VMReadResult]
    var active:Int { get }
}
extension SandboxExecuting {
    func submitResources(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws {throw SandboxExecutionFailure.unavailable}
    func drainResources()->[VMReadResult] {[]}
}

// The only asynchronous daemon adapter. Fixed typed commands,2 subprocess
// slots,queue0, reviewed immutable images and explicit private Unix endpoint.
// SQLite/lifecycle state is touched only by the serialized caller, never here.
final class SandboxExecutor:SandboxExecuting,@unchecked Sendable {
    private let runtime:DockerRuntime
    private let allowedImages:Set<String>
    private let lock=NSLock()
    private let queue=DispatchQueue(label:"fios.studio.runtime",attributes:.concurrent)
    private var pending=Set<String>()
    private var completed:[SandboxExecution]=[]
    private var completedResources:[VMReadResult]=[]
    private let resourceReader:any VMResourceReading
    private var identities:[String:(id:String,image:String)]=[:]
    init(runtime:DockerRuntime,allowedImages:Set<String>,resourceReader:(any VMResourceReading)? = nil) throws {
        guard !allowedImages.isEmpty,allowedImages.count<=8,
              allowedImages.allSatisfy({$0.hasPrefix("sha256:") && $0.utf8.count==71 && $0.dropFirst(7).utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})}) else { throw RuntimeError.invalid }
        self.runtime=runtime;self.allowedImages=allowedImages
        self.resourceReader=try resourceReader ?? OwnedVMResourceReader(runtime:runtime,approvedImages:allowedImages)
    }
    func submit(job:String,command:SandboxCommand) throws {
        guard UUID(uuidString:job)?.uuidString.lowercased()==job else { throw RuntimeError.invalid }
        switch command {
        case .create(let config),.inspect(let config,_),.remove(let config,_):
            guard config.job==job else { throw SandboxExecutionFailure.identity }
        case .start(let id),.stop(let id):
            lock.lock();let identity=identities[job];lock.unlock()
            guard identity?.id==id else { throw SandboxExecutionFailure.identity }
            if case .start=command { guard allowedImages.contains(identity?.image ?? "") else { throw SandboxExecutionFailure.unapprovedImage } }
        }
        lock.lock()
        guard pending.count+completed.count+completedResources.count<2,!pending.contains(job),!completed.contains(where:{$0.job==job}),!completedResources.contains(where:{$0.job==job}) else { lock.unlock();throw AdmissionError.capacity }
        pending.insert(job);lock.unlock()
        queue.async { [self] in
            let result:Result<SandboxExecutionValue,SandboxExecutionFailure>
            do { result = .success(try execute(command,job:job)) }
            catch let failure as SandboxExecutionFailure { result = .failure(failure) }
            catch RuntimeError.identity { result = .failure(.identity) }
            catch { result = .failure(.unavailable) }
            lock.lock();pending.remove(job);completed.append(SandboxExecution(job:job,result:result));lock.unlock()
        }
    }
    // Resource reads share the lifecycle executor's two operation/result slots;
    // they never create a separate pool or enter the lifecycle result channel.
    func submitResources(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws {
        guard allowedImages.contains(configuration.image) else {throw SandboxExecutionFailure.unapprovedImage}
        try fullID(id)
        let job=configuration.job
        lock.lock()
        guard pending.count+completed.count+completedResources.count<2,!pending.contains(job),!completed.contains(where:{$0.job==job}),!completedResources.contains(where:{$0.job==job}) else {lock.unlock();throw AdmissionError.capacity}
        pending.insert(job);lock.unlock()
        queue.async { [self] in
            let result:Result<VMKernelSample,VMReadFailure>
            do {result = .success(try resourceReader.read(configuration:configuration,id:id,leaseUntil:leaseUntil))}
            catch {result = .failure(.unavailable)}
            lock.lock();pending.remove(job);completedResources.append(VMReadResult(job:job,runtimeID:id,result:result));lock.unlock()
        }
    }
    func drainResources()->[VMReadResult] {
        lock.lock();defer {lock.unlock()};let results=completedResources;completedResources.removeAll();return results
    }
    var active:Int { lock.lock();defer { lock.unlock() };return pending.count }
    func drain()->[SandboxExecution] {
        lock.lock();defer { lock.unlock() };let results=completed;completed.removeAll();return results
    }
    private func fullID(_ id:String) throws {
        guard id.utf8.count==64,id.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else { throw SandboxExecutionFailure.identity }
    }
    private func remember(job:String,id:String,image:String) {
        lock.lock();identities[job]=(id,image);lock.unlock()
    }
    private func execute(_ command:SandboxCommand,job:String) throws -> SandboxExecutionValue {
        switch command {
        case .create(let configuration):
            guard allowedImages.contains(configuration.image) else { throw SandboxExecutionFailure.unapprovedImage }
            let id=try runtime.create(configuration)
            remember(job:job,id:id,image:configuration.image)
            return .created(id)
        case .inspect(let configuration,let saved):
            if let saved { try fullID(saved) }
            let filter=saved.map {"id="+$0} ?? "name=^/"+configuration.name+"$"
            let listing=try runtime.command(["container","ls","--all","--no-trunc","--filter",filter,"--format","{{.ID}}"],timeout:2)
            guard listing.status==0 else { throw SandboxExecutionFailure.unavailable }
            let text=String(decoding:listing.output,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            if text.isEmpty {
                if let saved {resourceReader.releaseAfterVerifiedAbsence(id:saved)}
                lock.lock();identities.removeValue(forKey:job);lock.unlock()
                return .observed(.absent)
            }
            let ids=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
            guard ids.count==1,let id=ids.first else { throw SandboxExecutionFailure.identity }
            try fullID(id)
            guard saved==nil || saved==id else { throw SandboxExecutionFailure.identity }
            let inspected=try runtime.command(["inspect","--type=container",id],timeout:2)
            guard inspected.status==0 else { throw SandboxExecutionFailure.unavailable }
            try StrictJSON.validate(inspected.output,maximum:1<<20)
            guard let objects=try JSONSerialization.jsonObject(with:inspected.output) as? [[String:Any]],objects.count==1,
                  let object=objects.first,configuration.verifies(inspect:object,savedID:id),
                  let state=object["State"] as? [String:Any],let runningNumber=state["Running"] as? NSNumber,
                  CFGetTypeID(runningNumber)==CFBooleanGetTypeID(),let running=state["Running"] as? Bool,
                  let code=state["ExitCode"] as? NSNumber,CFGetTypeID(code) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:code.objCType)),(Double(Int32.min)...Double(Int32.max)).contains(code.doubleValue),
                  let oomNumber=state["OOMKilled"] as? NSNumber,CFGetTypeID(oomNumber)==CFBooleanGetTypeID(),
                  let oom=state["OOMKilled"] as? Bool else { throw SandboxExecutionFailure.identity }
            remember(job:job,id:id,image:configuration.image)
            return .observed(.present(id:id,name:"/"+configuration.name,image:configuration.image,nonce:configuration.nonce,running:running),exitCode:code.intValue,oom:oom)
        case .start(let id):
            try fullID(id)
            let result=try runtime.command(["start",id])
            guard result.status==0 else { throw SandboxExecutionFailure.unavailable }
            return .acknowledged
        case .stop(let id):
            try fullID(id)
            let result=try runtime.command(["stop","--time=10",id])
            guard result.status==0 else { throw SandboxExecutionFailure.unavailable }
            return .acknowledged
        case .remove(let configuration,let id):
            try fullID(id);try runtime.removeOwned(configuration,savedID:id)
            lock.lock();identities.removeValue(forKey:job);lock.unlock()
            return .acknowledged
        }
    }
}
