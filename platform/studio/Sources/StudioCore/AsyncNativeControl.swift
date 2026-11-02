import Foundation

struct NativeControlResult:Sendable {
    let id:String
    let value:Result<NativeIngressStatus,NativeControlError>
    let receivedAt:Int64
    let backendFences:Result<NativeBackendFenceSample,NativeControlError>?
    let primaryActivity:Result<NativePrimaryActivitySample,NativeControlError>?
    init(id:String,value:Result<NativeIngressStatus,NativeControlError>,receivedAt:Int64=HostResources.nowMilliseconds(),backendFences:Result<NativeBackendFenceSample,NativeControlError>?=nil,primaryActivity:Result<NativePrimaryActivitySample,NativeControlError>?=nil) {
        self.id=id;self.value=value;self.receivedAt=receivedAt;self.backendFences=backendFences;self.primaryActivity=primaryActivity
    }
}
// One bounded native connection/hash operation off the manager heartbeat loop.
// No automatic retry, result queue growth, native process launch or fallback.
final class AsyncNativeControl:@unchecked Sendable {
    private let client:NativeControlClient
    private let lock=NSLock()
    private var busy=false
    private var result:NativeControlResult?
    init(client:NativeControlClient) {self.client=client}
    func submit(_ command:NativeMaintenanceCommand) throws {
        lock.lock()
        guard !busy,result==nil else {lock.unlock();throw RuntimeError.capacity}
        busy=true;lock.unlock()
        Thread.detachNewThread { [self] in
            let value:Result<NativeIngressStatus,NativeControlError>
            var receivedAt=HostResources.nowMilliseconds()
            var primaryActivity:Result<NativePrimaryActivitySample,NativeControlError>?
            var backendFences:Result<NativeBackendFenceSample,NativeControlError>?
            do {
                let ingress=try client.request(operation:command.operation,instance:command.instance,sequence:command.sequence)
                receivedAt=HostResources.nowMilliseconds() // A later backend query cannot refresh this receipt.
                if client.observesPrimaryActivity,command.operation == .observe {
                    do {
                        guard client.version==3,let sequence=ingress.nativeSampleSequence else {throw NativeControlError.invalid}
                        primaryActivity = .success(try client.primaryActivity(instance:ingress.instance,after:sequence))
                    } catch let error as NativeControlError {primaryActivity = .failure(error)}
                    catch {primaryActivity = .failure(.unavailable)}
                }
                if client.observesBackendFences,command.operation == .observe {
                    do {
                        guard client.version==3,let sequence=ingress.nativeSampleSequence else {throw NativeControlError.invalid}
                        backendFences = .success(try client.backendFences(instance:ingress.instance,after:sequence))
                    } catch let error as NativeControlError {backendFences = .failure(error)}
                    catch {backendFences = .failure(.unavailable)}
                }
                value = .success(ingress)
            } catch let error as NativeControlError {value = .failure(error)}
            catch {value = .failure(.unavailable)}
            lock.lock();result=NativeControlResult(id:command.id,value:value,receivedAt:receivedAt,backendFences:backendFences,primaryActivity:primaryActivity);busy=false;lock.unlock()
        }
    }
    func poll()->NativeControlResult? {
        lock.lock();defer {lock.unlock()}
        let value=result;result=nil;return value
    }
}
