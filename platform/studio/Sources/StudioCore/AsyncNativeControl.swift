import Foundation

struct NativeControlResult:Sendable {
    let id:String
    let value:Result<NativeIngressStatus,NativeControlError>
    let receivedAt:Int64 = HostResources.nowMilliseconds()
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
            do {value = .success(try client.request(operation:command.operation,instance:command.instance,sequence:command.sequence))}
            catch let error as NativeControlError {value = .failure(error)}
            catch {value = .failure(.unavailable)}
            lock.lock();result=NativeControlResult(id:command.id,value:value);busy=false;lock.unlock()
        }
    }
    func poll()->NativeControlResult? {
        lock.lock();defer {lock.unlock()}
        let value=result;result=nil;return value
    }
}
