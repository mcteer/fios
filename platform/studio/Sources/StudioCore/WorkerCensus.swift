import Foundation
import Darwin

// Trusted enrollment must enumerate ALL historically approved parent and
// private-interpreter paths, kept immutable while launches may survive. Never
// infer this set from task packets/current Python alone. The reviewed factory
// must not fork descendants before parent-bound dispatch. No argv/env/content.
struct WorkerCensusPolicy {
    let paths:Set<String>
    private struct Image {let path:String;let device:dev_t;let inode:ino_t;let size:off_t;let changed:timespec;let modified:timespec}
    private let images:[Image]
    init(reviewDigest:String,historicalExecutablePaths:Set<String>)throws {
        guard reviewDigest.utf8.count==64,reviewDigest.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
              !historicalExecutablePaths.isEmpty,historicalExecutablePaths.count<=32,
              historicalExecutablePaths.allSatisfy({$0.hasPrefix("/") && !$0.contains("\0") && !$0.split(separator:"/").contains("..") && $0.utf8.count<=4096}) else {throw WorkerResourceError.invalid}
        var images:[Image]=[]
        for path in historicalExecutablePaths {
            guard let resolved=realpath(path,nil) else {throw WorkerResourceError.unavailable}
            let canonical=String(cString:resolved);free(resolved)
            var info=stat()
            guard lstat(canonical,&info)==0,info.st_mode&S_IFMT==S_IFREG,info.st_nlink==1 else {throw WorkerResourceError.unavailable}
            images.append(Image(path:canonical,device:info.st_dev,inode:info.st_ino,size:info.st_size,changed:info.st_ctimespec,modified:info.st_mtimespec))
        }
        self.images=images;paths=Set(images.map(\.path))
    }
    private func validateImages()throws {
        for image in images {
            var info=stat()
            guard lstat(image.path,&info)==0,info.st_dev==image.device,info.st_ino==image.inode,
                  info.st_mode&S_IFMT==S_IFREG,info.st_nlink==1,info.st_size==image.size,
                  info.st_ctimespec.tv_sec==image.changed.tv_sec,info.st_ctimespec.tv_nsec==image.changed.tv_nsec,
                  info.st_mtimespec.tv_sec==image.modified.tv_sec,info.st_mtimespec.tv_nsec==image.modified.tv_nsec else {throw WorkerResourceError.unavailable}
        }
    }
    // Startup-only, before this manager can spawn work. Any candidate (even an
    // unrelated same-image process) retains uncertainty; never signal it.
    func absence()throws->WorkerCensusAbsence {
        try validateImages()
        let boot=try HostBoot.identity(),uid=geteuid(),began=ProcessInfo.processInfo.systemUptime
        guard uid != 0 else {throw WorkerResourceError.invalid}
        var pids=[Int32](repeating:0,count:32768)
        // Kernel UID filtering avoids requiring visibility into unrelated
        // privileged/system processes. Approved private children are unprivileged.
        let bytes=pids.withUnsafeMutableBytes {proc_listpids(UInt32(PROC_UID_ONLY),uid,$0.baseAddress,Int32($0.count))}
        let stride=Int32(MemoryLayout<Int32>.stride)
        guard bytes>0,bytes<Int32(pids.count)*stride,bytes%stride==0 else {throw WorkerResourceError.unavailable}
        for pid in pids.prefix(Int(bytes/stride)) where pid>1 && pid != getpid() {
            guard ProcessInfo.processInfo.systemUptime-began<1 else {throw WorkerResourceError.unavailable}
            var bytes=[CChar](repeating:0,count:4096)
            errno=0
            let length=proc_pidpath(pid,&bytes,UInt32(bytes.count))
            if length==0 {
                // Path lookup failure alone is NOT process-absence proof
                // (exec transitions can be temporarily uninspectable).
                errno=0
                if kill(pid,0)<0 && errno==ESRCH {continue}
                var info=proc_bsdinfo()
                let size=Int32(MemoryLayout<proc_bsdinfo>.size)
                if proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,size)==size,
                   info.pbi_pid==UInt32(pid),info.pbi_status==UInt32(SZOMB) {continue}
            }
            guard length>0,let path=String(bytes:bytes.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8) else {throw WorkerResourceError.unavailable}
            var image=stat()
            guard stat(path,&image)==0 else {throw WorkerResourceError.unavailable}
            guard !paths.contains(path),!images.contains(where:{$0.device==image.st_dev && $0.inode==image.st_ino}) else {throw WorkerResourceError.unavailable}
        }
        try validateImages()
        guard try HostBoot.identity()==boot else {throw WorkerResourceError.unavailable}
        return WorkerCensusAbsence(boot:boot,uid:uid,sampledAt:ProcessInfo.processInfo.systemUptime)
    }
}

struct WorkerCensusAbsence {
    let boot:String
    private let uid:uid_t
    private let sampledAt:TimeInterval
    fileprivate init(boot:String,uid:uid_t,sampledAt:TimeInterval) {self.boot=boot;self.uid=uid;self.sampledAt=sampledAt}
    func validate()throws {
        let age=ProcessInfo.processInfo.systemUptime-sampledAt
        guard uid==geteuid(),try HostBoot.identity()==boot,age>=0,age<=1 else {throw WorkerResourceError.unavailable}
    }
}
