import Foundation

enum SessionTransportFailure:Error,Sendable {case unavailable}
struct SessionRecoveryResult:Sendable {
    let request:ServiceRecoveryRequest
    let value:Result<SessionLaunchResult,SessionTransportFailure>
}

// One finite connection/hash exchange off the manager heartbeat. No automatic
// retry, fallback, queue growth or absent-service/terminal inference on error.
final class AsyncSessionControl:@unchecked Sendable {
    private let client:SessionControlClient
    private let lock=NSLock()
    private var busy=false
    private var result:SessionRecoveryResult?
    init(client:SessionControlClient) {self.client=client}
    var available:Bool {
        lock.lock();defer {lock.unlock()};return !busy && result==nil
    }
    func submit(_ request:ServiceRecoveryRequest)throws {
        lock.lock()
        guard !busy,result==nil else {lock.unlock();throw RuntimeError.capacity}
        guard client.accepts(request.command),request.consumeTransport() else {lock.unlock();throw RuntimeError.invalid}
        busy=true;lock.unlock()
        Thread.detachNewThread { [self] in
            let value:Result<SessionLaunchResult,SessionTransportFailure>
            do {value = .success(try client.request(request))}
            catch {value = .failure(.unavailable)}
            lock.lock();result=SessionRecoveryResult(request:request,value:value);busy=false;lock.unlock()
        }
    }
    func poll()->SessionRecoveryResult? {
        lock.lock();defer {lock.unlock()}
        let found=result;result=nil;return found
    }
}
