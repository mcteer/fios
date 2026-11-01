import Foundation

// One read-only collection off the manager loop. The slot stays occupied
// until its real producer returns; elapsed time cannot create a second probe.
// Only the serialized manager consumes results and updates its status cache.
final class AsyncServiceHealth:@unchecked Sendable {
    struct Result {let observation:ServiceObservation?}
    private let collector:MLXServiceHealthCollector
    private let lock=NSLock()
    private var busy=false
    private var result:Result?
    init(collector:MLXServiceHealthCollector) {self.collector=collector}
    func begin(sessionReady:Bool,credentialsReady:Bool) {
        lock.lock()
        guard !busy,result==nil else {lock.unlock();return}
        busy=true;lock.unlock()
        Thread.detachNewThread { [self] in
            let observation=autoreleasepool {collector.capture(sessionReady:sessionReady,credentialsReady:credentialsReady)}
            lock.lock();result=Result(observation:observation);busy=false;lock.unlock()
        }
    }
    func poll()->Result? {
        lock.lock();defer {lock.unlock()}
        let found=result;result=nil;return found
    }
}
