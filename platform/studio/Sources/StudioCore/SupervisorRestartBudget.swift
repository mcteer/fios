import Foundation
import Darwin

// Existing boot/starts wire layout; unknown future layouts are never rewritten.
struct SupervisorRestartBudget:Codable {
    var boot:String
    var starts:[Int64]
    func policy(currentBoot:String)throws->WatchdogPolicy {
        guard UUID(uuidString:boot)?.uuidString.lowercased()==boot,
              UUID(uuidString:currentBoot)?.uuidString.lowercased()==currentBoot else {throw JournalError.invalid}
        // Validate old-boot histories too, before deciding whether a new boot
        // legitimately starts a fresh budget. Malformed is not a new boot.
        let restored=try WatchdogPolicy(restoringStarts:starts)
        return boot==currentBoot ? restored:WatchdogPolicy()
    }
    static func read(directory:URL)throws->SupervisorRestartBudget? {
        guard getuid() != 0,getuid()==geteuid() else {throw ControlError.unauthorized}
        let path=directory.appendingPathComponent("restart-budget.json").path
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        if fd<0 {if errno==ENOENT{return nil};throw JournalError.invalid}
        defer {Darwin.close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode & S_IFMT == S_IFREG,
              before.st_uid==geteuid(),before.st_nlink==1,before.st_mode & 0o7777==0o600,
              before.st_size>0,before.st_size<=4096 else {throw JournalError.invalid}
        var bytes=[UInt8](repeating:0,count:Int(before.st_size)+1),offset=0
        let began=ProcessInfo.processInfo.systemUptime
        while offset<bytes.count {
            guard ProcessInfo.processInfo.systemUptime-began<2 else {throw JournalError.invalid}
            let remaining=bytes.count-offset
            let count=bytes.withUnsafeMutableBytes {Darwin.read(fd,$0.baseAddress!.advanced(by:offset),remaining)}
            if count<0 && errno==EINTR {continue}
            guard count>=0 else {throw JournalError.invalid}
            if count==0 {break}
            offset+=count
        }
        guard offset==Int(before.st_size),fstat(fd,&after)==0,lstat(path,&named)==0,
              after.st_dev==before.st_dev,after.st_ino==before.st_ino,after.st_size==before.st_size,
              after.st_mode==before.st_mode,after.st_uid==before.st_uid,after.st_nlink==1,
              after.st_mtimespec.tv_sec==before.st_mtimespec.tv_sec,after.st_mtimespec.tv_nsec==before.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec==before.st_ctimespec.tv_sec,after.st_ctimespec.tv_nsec==before.st_ctimespec.tv_nsec,
              named.st_dev==after.st_dev,named.st_ino==after.st_ino,named.st_size==after.st_size,
              named.st_mode==after.st_mode,named.st_uid==after.st_uid,named.st_nlink==1 else {throw JournalError.invalid}
        let data=Data(bytes.prefix(offset));try StrictJSON.validate(data,maximum:4096)
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(object.keys)==Set(["boot","starts"]),let boot=object["boot"] as? String,
              UUID(uuidString:boot)?.uuidString.lowercased()==boot,
              let raw=object["starts"] as? [Any],raw.count<=3 else {throw JournalError.invalid}
        let starts=raw.compactMap{WireScalar.integer($0)}
        guard starts.count==raw.count else {throw JournalError.invalid}
        _ = try WatchdogPolicy(restoringStarts:starts)
        return .init(boot:boot,starts:starts)
    }
}
