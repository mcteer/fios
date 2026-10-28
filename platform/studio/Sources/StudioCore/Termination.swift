import Foundation
import Dispatch
import Darwin

public final class Termination: @unchecked Sendable {
    private let lock=NSLock()
    private var stopped=false
    private var sources:[DispatchSourceSignal]=[]
    public init() {
        for number in [SIGTERM,SIGINT] {
            signal(number,SIG_IGN)
            let source=DispatchSource.makeSignalSource(signal:number,queue:.global())
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.lock.lock(); self.stopped=true; self.lock.unlock()
            }
            sources.append(source); source.resume()
        }
    }
    public var requested:Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    deinit { for source in sources { source.cancel() } }
}
