import Foundation

struct ServingStopResponse:Sendable {
    let request:ServingStopRequest
    let value:Result<ServingStopResult,SessionTransportFailure>
}
// One code-only exchange off-loop, without a session/GUI fallback or public
// packet decoder. A restored pending operation can only look up or revoke its
// original ID. The native runtime remains the separate authority checkpoint.
final class AsyncServingStop:@unchecked Sendable {
    private let runtime:MLXServingProcessRuntime
    private let lock=NSLock()
    private var busy=false
    private var result:ServingStopResponse?
    init(runtime:MLXServingProcessRuntime) {self.runtime=runtime}
    var available:Bool {lock.lock();defer {lock.unlock()};return !busy && result==nil}
    func submit(_ request:ServingStopRequest)throws {
        lock.lock()
        guard !busy,result==nil else {lock.unlock();throw RuntimeError.capacity}
        guard runtime.acceptsStopReceipt(request.receipt),request.consumeTransport() else {lock.unlock();throw RuntimeError.invalid}
        busy=true;lock.unlock()
        Thread.detachNewThread { [self] in
            let value:Result<ServingStopResult,SessionTransportFailure>
            do {
                switch request.operation {
                case .stop:
                    do {
                        try runtime.beginStop(id:request.id,matching:request.receipt,deadline:ProcessInfo.processInfo.systemUptime+10)
                        value = .success(.uncertain)
                    } catch RuntimeError.capacity {value = .success(runtime.rejectedStopResult(id:request.id))}
                case .lookup:value = .success(runtime.acknowledgeStopResult(id:request.id))
                case .cancel:
                    _=runtime.cancelStopValidation(id:request.id)
                    value = .success(runtime.acknowledgeStopResult(id:request.id))
                }
            } catch {value = .failure(.unavailable)}
            lock.lock();result=ServingStopResponse(request:request,value:value);busy=false;lock.unlock()
        }
    }
    func poll()->ServingStopResponse? {
        lock.lock();defer {lock.unlock()};let found=result;result=nil;return found
    }
}
