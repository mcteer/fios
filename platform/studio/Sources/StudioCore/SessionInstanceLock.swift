import Foundation

// Single writer for GUI observation metadata; no lifecycle authority.
// Separate from supervisor/manager/SQLite writer locks.
public final class SessionInstanceLock {
    private let lock:PrivateWriterLock
    public init(directory:URL)throws {lock=try PrivateWriterLock(directory:directory,kind:.session)}
    public func release() {lock.release()}
}
