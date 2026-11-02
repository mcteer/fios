import Foundation

enum NativeHealthConfigurationOutcome:Sendable {
    case configured(ServiceHealthCollector),unconfigured,unavailable
}
// One retained off-loop metadata load. No credential, native control, launch,
// model request or retry. A stalled read retains its single original worker.
final class AsyncNativeHealthConfiguration:@unchecked Sendable {
    private let lock=NSLock()
    private var pending=true
    private var result:NativeHealthConfigurationOutcome?
    init(load:@escaping @Sendable()throws->ServiceHealthCollector?) {
        Thread.detachNewThread { [self] in
            let outcome:NativeHealthConfigurationOutcome
            do {
                if let collector=try load() {
                    outcome=collector.service == .mlx ? .configured(collector):.unavailable
                } else {outcome = .unconfigured}
            } catch {outcome = .unavailable} // Never expose raw policy/error data.
            lock.lock();result=outcome;pending=false;lock.unlock()
        }
    }
    var isPending:Bool {lock.lock();defer {lock.unlock()};return pending}
    func poll()->NativeHealthConfigurationOutcome? {
        lock.lock();defer {lock.unlock()};let value=result;result=nil;return value
    }
}
