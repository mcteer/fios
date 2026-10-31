import Foundation
import Darwin

// Process presence within an explicitly reviewed executable/bundle scope.
// Absence is NOT GPU/native terminality, endpoint ownership or a launch lease.
enum ServiceProcessPresence:Equatable {case absent,present(ServiceIdentity),unknown}
struct ServiceProcessSample {
    let presence:ServiceProcessPresence
    let sampledAt:Int64?
    let reviewDigest:String
    let uid:uid_t
    let diagnostic:String
}
struct ServiceProcessEntry:Sendable {
    let pid:Int32
    let uid:uid_t
    let realUID:uid_t
    let savedUID:uid_t
    let start:UInt64
    let path:String
}
protocol ServiceProcessCensusReading:Sendable {
    func pids(uid:uid_t)throws->[Int32]
    func entry(pid:Int32)throws->ServiceProcessEntry?
    func verify(_ entry:ServiceProcessEntry,executable:VerifiedExecutable,uid:uid_t,deadline:TimeInterval)throws->ServiceIdentity
}
struct KernelServiceProcessCensus:ServiceProcessCensusReading {
    func pids(uid:uid_t)throws->[Int32] {
        var pids=[Int32](repeating:0,count:32768)
        let count=pids.withUnsafeMutableBytes {proc_listpids(UInt32(PROC_UID_ONLY),uid,$0.baseAddress,Int32($0.count))}
        let stride=Int32(MemoryLayout<Int32>.stride)
        guard count>0,count<Int32(pids.count)*stride,count%stride==0 else {throw ServiceError.invalid}
        return Array(pids.prefix(Int(count/stride)).filter {$0>1})
    }
    func entry(pid:Int32)throws->ServiceProcessEntry? {
        var before=proc_bsdinfo(),after=proc_bsdinfo()
        let size=Int32(MemoryLayout<proc_bsdinfo>.size)
        errno=0
        if proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&before,size) != size {
            if errno==ESRCH {return nil};throw ServiceError.invalid
        }
        guard before.pbi_pid==UInt32(pid) else {throw ServiceError.invalid}
        if before.pbi_status==UInt32(SZOMB) {return nil} // No active process, NOT native terminality.
        let start=try WorkerResources.startIdentifier(pid:pid)
        var bytes=[CChar](repeating:0,count:4*Int(MAXPATHLEN))
        guard proc_pidpath(pid,&bytes,UInt32(bytes.count))>0,
              let path=String(bytes:bytes.prefix(while:{$0 != 0}).map {UInt8(bitPattern:$0)},encoding:.utf8),
              proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&after,size)==size,
              after.pbi_pid==before.pbi_pid,after.pbi_uid==before.pbi_uid,after.pbi_ruid==before.pbi_ruid,after.pbi_svuid==before.pbi_svuid,
              try WorkerResources.startIdentifier(pid:pid)==start else {throw ServiceError.invalid}
        return ServiceProcessEntry(pid:pid,uid:after.pbi_uid,realUID:after.pbi_ruid,savedUID:after.pbi_svuid,start:start,path:path)
    }
    func verify(_ entry:ServiceProcessEntry,executable:VerifiedExecutable,uid:uid_t,deadline:TimeInterval)throws->ServiceIdentity {
        try ServiceIdentity.verified(peer:NativeControlPeer(pid:entry.pid,start:entry.start,executable:executable),expectedUID:uid,deadline:deadline)
    }
}

// Trusted profile construction only, never a PID/path list from IPC. The
// immutable installed artifact/bundle and complete participant scope remain
// enrollment preconditions, not facts established by a current path hash.
final class ServiceProcessCensus:@unchecked Sendable {
    private let executable:VerifiedExecutable
    private let roots:Set<String>
    private let uid:uid_t
    private let reviewDigest:String
    private let image:stat
    private let source:any ServiceProcessCensusReading
    private let now:@Sendable()->Int64
    private let uptime:@Sendable()->TimeInterval
    private let lock=NSLock()
    private var previous:Int64 = -1
    private var fenced=false
    private var diagnostic="unknown"
    init(executable:VerifiedExecutable,relatedRoots:Set<String>,reviewDigest:String,uid:uid_t,
         source:any ServiceProcessCensusReading=KernelServiceProcessCensus(),
         now:@escaping @Sendable()->Int64=HostResources.nowMilliseconds,
         uptime:@escaping @Sendable()->TimeInterval={ProcessInfo.processInfo.systemUptime})throws {
        guard uid>0,uid==geteuid(),getuid()==geteuid(),WireScalar.sha256(reviewDigest),(1...8).contains(relatedRoots.count),
              relatedRoots.allSatisfy({$0.hasPrefix("/") && $0 != "/" && !$0.hasSuffix("/") && !$0.contains("//") && !$0.contains("\0") && !$0.split(separator:"/").contains(where:{$0=="." || $0==".."})}),
              relatedRoots.contains(where:{executable.path.hasPrefix($0+"/")}) else {throw ServiceError.invalid}
        var before=stat(),after=stat()
        guard lstat(executable.path,&before)==0 else {throw ServiceError.invalid}
        try executable.verify()
        guard lstat(executable.path,&after)==0,Self.same(before,after) else {throw ServiceError.invalid}
        self.executable=executable;roots=relatedRoots;self.uid=uid;self.reviewDigest=reviewDigest;image=after;self.source=source;self.now=now;self.uptime=uptime
    }
    private static func same(_ a:stat,_ b:stat)->Bool {
        a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_mode==b.st_mode && a.st_uid==b.st_uid && a.st_nlink==b.st_nlink && b.st_nlink==1 &&
        a.st_size==b.st_size && a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
    }
    private func imageValid()->Bool {var value=stat();return lstat(executable.path,&value)==0 && Self.same(image,value)}
    func capture()->ServiceProcessSample {
        lock.lock();defer {lock.unlock()}
        let stamp=now(),began=uptime()
        diagnostic="initial"
        var presence=captureLocked(stamp:stamp,began:began)
        let completed=now(),elapsed=uptime()-began
        if completed<previous || completed<stamp || completed>ActivityPolicy.maximumTimestamp || !elapsed.isFinite || elapsed<0 || elapsed>=1 {
            fenced=true;presence = .unknown;diagnostic="clock_or_deadline"
        }
        previous=max(previous,completed)
        return ServiceProcessSample(presence:presence,sampledAt:(0...ActivityPolicy.maximumTimestamp).contains(stamp) ? stamp:nil,reviewDigest:reviewDigest,uid:uid,diagnostic:diagnostic)
    }
    private func captureLocked(stamp:Int64,began:TimeInterval)->ServiceProcessPresence {
        guard !fenced,stamp>=0,stamp<=ActivityPolicy.maximumTimestamp,stamp>=previous,began.isFinite,began>=0,
              uid==geteuid(),getuid()==geteuid() else {fenced=true;return .unknown}
        previous=stamp
        do {
            diagnostic="image"
            guard imageValid() else {fenced=true;return .unknown}
            diagnostic="enumeration"
            let boot=try HostBoot.identity(),first=try source.pids(uid:uid)
            guard (1..<32768).contains(first.count),Set(first).count==first.count,first.contains(getpid()),first.allSatisfy({$0>1}) else {return .unknown}
            var matches:[ServiceProcessEntry]=[],related=false
            diagnostic="inspection"
            for pid in first {
                guard uptime()-began<1 else {return .unknown}
                guard let entry=try source.entry(pid:pid) else {if pid==getpid() {return .unknown};continue}
                guard entry.pid==pid,entry.uid==uid,entry.start>0,entry.path.hasPrefix("/"),!entry.path.contains("\0"),entry.path.utf8.count<4*Int(MAXPATHLEN) else {return .unknown}
                var current=stat()
                guard stat(entry.path,&current)==0 else {return .unknown}
                if entry.path==executable.path || (current.st_dev==image.st_dev && current.st_ino==image.st_ino) {
                    guard entry.realUID==uid,entry.savedUID==uid else {diagnostic="candidate_principal";return .unknown}
                    matches.append(entry)
                }
                else if roots.contains(where:{entry.path==$0 || entry.path.hasPrefix($0+"/")}) {related=true}
            }
            diagnostic="second_enumeration"
            let second=try source.pids(uid:uid)
            guard second.count==first.count,Set(second)==Set(first),Set(second).count==second.count,
                  imageValid(),try HostBoot.identity()==boot,uptime()-began<1 else {return .unknown}
            let completed=now()
            guard completed>=previous,completed-stamp<=1000 else {fenced=true;return .unknown}
            previous=completed
            if matches.isEmpty {diagnostic=related ? "unreviewed_related_process":"scoped_absence";return related ? .unknown:.absent}
            guard matches.count==1 else {diagnostic="multiple_candidates";return .unknown}
            diagnostic="candidate_verification"
            let identity=try source.verify(matches[0],executable:executable,uid:uid,deadline:began+1)
            diagnostic="candidate_postcheck"
            guard identity.valid,identity.pid==matches[0].pid,identity.start==matches[0].start,identity.sha256==executable.sha256,
                  imageValid(),try HostBoot.identity()==boot,uptime()-began<1,now()>=previous else {return .unknown}
            previous=now()
            diagnostic="verified_present"
            return .present(identity)
        } catch {return .unknown}
    }
}
