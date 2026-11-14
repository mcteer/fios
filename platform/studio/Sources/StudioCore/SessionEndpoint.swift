import Foundation
import Darwin

// Bootstrap metadata only. No field can replace the connection's live kernel
// UID/PID/start/path/hash verification or establish native/model readiness.
struct SessionEndpointDescriptor:Sendable {
    let pid:Int32
    let start:UInt64
    let instance:String
    let profile:String
    init(_ bytes:Data,expectedBoot:String,expectedProfile:String,expectedUID:uid_t)throws {
        do {
            try StrictJSON.validate(bytes,maximum:2048)
            guard expectedUID>0,WireScalar.uuid(expectedBoot),WireScalar.sha256(expectedProfile),
                  let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  Set(value.keys)==Set(["version","pid","uid","process_start","boot","instance","profile"]),
                  WireScalar.integer(value["version"],maximum:1)==1,
                  WireScalar.integer(value["uid"],maximum:Int64(UInt32.max))==Int64(expectedUID),
                  let pid=WireScalar.integer(value["pid"],maximum:Int64(Int32.max)),pid>1,
                  let text=value["process_start"] as? String,let start=UInt64(text),start>0,String(start)==text,
                  value["boot"] as? String==expectedBoot,value["profile"] as? String==expectedProfile,
                  let instance=value["instance"] as? String,WireScalar.uuid(instance) else {throw ControlError.unauthorized}
            self.pid=Int32(pid);self.start=start;self.instance=instance;profile=expectedProfile
        } catch {throw ControlError.unauthorized}
    }
}

extension SessionControlClient {
    static func discover(directory:URL,helper:VerifiedExecutable,approvedHashes:[ManagedService:String])throws->SessionControlClient? {
        let profile=try ServiceLaunchProfile.digest(approvedHashes)
        var parent=stat()
        guard geteuid()>0,getuid()==geteuid(),lstat(directory.path,&parent)==0,parent.st_mode&S_IFMT==S_IFDIR,
              parent.st_uid==geteuid(),parent.st_mode&0o7777==0o700 else {throw ControlError.unauthorized}
        let file=directory.appendingPathComponent("session-control.json")
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
        if fd<0,errno==ENOENT {return nil}
        guard fd>=0 else {throw ControlError.unauthorized};defer {close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_uid==geteuid(),
              before.st_mode&0o7777==0o600,before.st_nlink==1,(1...2048).contains(before.st_size) else {throw ControlError.unauthorized}
        let deadline=ProcessInfo.processInfo.systemUptime+2
        var data=Data(),buffer=[UInt8](repeating:0,count:2049)
        while true {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw ControlError.unauthorized}
            let count=Darwin.read(fd,&buffer,buffer.count-data.count)
            if count<0,errno==EINTR {continue}
            guard count>=0,data.count+count<=2048 else {throw ControlError.unauthorized}
            if count==0 {break};data.append(contentsOf:buffer.prefix(count))
        }
        guard data.count==before.st_size,fstat(fd,&after)==0,lstat(file.path,&named)==0,
              before.st_dev==after.st_dev,before.st_ino==after.st_ino,before.st_size==after.st_size,
              before.st_uid==after.st_uid,before.st_mode==after.st_mode,after.st_nlink==1,
              before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              named.st_dev==after.st_dev,named.st_ino==after.st_ino,named.st_mode==after.st_mode,named.st_uid==after.st_uid,named.st_nlink==1 else {throw ControlError.unauthorized}
        let descriptor=try SessionEndpointDescriptor(data,expectedBoot:HostBoot.identity(),expectedProfile:profile,expectedUID:geteuid())
        return try SessionControlClient(directory:directory,peer:NativeControlPeer(pid:descriptor.pid,start:descriptor.start,executable:helper),
            instance:descriptor.instance,profile:descriptor.profile,approvedHashes:approvedHashes)
    }
}
