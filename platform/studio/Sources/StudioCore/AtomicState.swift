import Foundation
import Darwin

public enum AtomicState {
    public static func write(_ data:Data,to target:URL) throws {
        let temporary=target.deletingLastPathComponent().appendingPathComponent(".state-"+UUID().uuidString)
        let fd=open(temporary.path,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard fd >= 0 else { throw JournalError.storage }
        defer { close(fd); unlink(temporary.path) }
        var offset=0
        while offset < data.count {
            let count=data.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!.advanced(by:offset),data.count-offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw JournalError.storage }; offset += count
        }
        guard fsync(fd) == 0, rename(temporary.path,target.path) == 0 else { throw JournalError.storage }
        let parent=open(target.deletingLastPathComponent().path,O_RDONLY | O_CLOEXEC)
        guard parent >= 0 else { throw JournalError.storage }; defer { close(parent) }
        guard fsync(parent) == 0 else { throw JournalError.storage }
    }
}
