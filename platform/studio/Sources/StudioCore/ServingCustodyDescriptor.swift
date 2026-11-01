import Foundation
import Darwin

// Private descriptor metadata only. A reader must independently verify the
// pinned supervisor kernel/image identity and every authenticated exchange.
struct ServingCustodyDescriptor {
    let pid:Int32
    let start:UInt64
    let instance:String
    init(_ bytes:Data,expectedUID:uid_t,expectedProfile:String,boot:String)throws {
        try StrictJSON.validate(bytes,maximum:2048)
        guard expectedUID>0,WireScalar.sha256(expectedProfile),WireScalar.uuid(boot),
              let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              Set(value.keys)==Set(["version","purpose","pid","uid","process_start","boot","instance","profile"]),
              WireScalar.integer(value["version"],maximum:1)==1,value["purpose"] as? String=="native_serving_custody",
              let pid=WireScalar.integer(value["pid"],maximum:Int64(Int32.max)),pid>1,
              WireScalar.integer(value["uid"],maximum:Int64(UInt32.max))==Int64(expectedUID),
              let text=value["process_start"] as? String,let start=UInt64(text),start>0,String(start)==text,
              value["boot"] as? String==boot,value["profile"] as? String==expectedProfile,
              let instance=value["instance"] as? String,WireScalar.uuid(instance) else {throw ControlError.unauthorized}
        self.pid=Int32(pid);self.start=start;self.instance=instance
    }
    static func read(directory:URL,expectedUID:uid_t,expectedProfile:String,boot:String)throws->ServingCustodyDescriptor? {
        guard expectedUID==geteuid() else {throw ControlError.unauthorized}
        let parentFD=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard parentFD>=0 else {throw ControlError.unauthorized};defer {close(parentFD)}
        var parent=stat()
        guard fstat(parentFD,&parent)==0,parent.st_mode&S_IFMT==S_IFDIR,
              parent.st_uid==expectedUID,parent.st_mode&0o7777==0o700 else {throw ControlError.unauthorized}
        let name="serving-custody.json",fd=openat(parentFD,"serving-custody.json",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        if fd<0 {guard errno==ENOENT else {throw ControlError.unauthorized};return nil}
        defer {close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode&S_IFMT==S_IFREG,before.st_uid==expectedUID,
              before.st_mode&0o7777==0o600,before.st_nlink==1,(1...2048).contains(before.st_size) else {throw ControlError.unauthorized}
        let deadline=ProcessInfo.processInfo.systemUptime+2
        var bytes=Data(),buffer=[UInt8](repeating:0,count:2049)
        while true {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
            let count=Darwin.read(fd,&buffer,buffer.count-bytes.count)
            if count<0,errno==EINTR {continue}
            guard count>=0,bytes.count+count<=2048 else {throw ControlError.unauthorized}
            if count==0 {break};bytes.append(contentsOf:buffer.prefix(count))
        }
        func stable(_ a:stat,_ b:stat)->Bool {
            a.st_dev==b.st_dev && a.st_ino==b.st_ino && a.st_mode==b.st_mode && a.st_uid==b.st_uid &&
            a.st_nlink==b.st_nlink && a.st_size==b.st_size && a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec &&
            a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec
        }
        guard bytes.count==before.st_size,fstat(fd,&after)==0,fstatat(parentFD,name,&named,AT_SYMLINK_NOFOLLOW)==0,
              stable(before,after),stable(after,named),lstat(directory.path,&after)==0,
              after.st_dev==parent.st_dev,after.st_ino==parent.st_ino,after.st_uid==parent.st_uid,after.st_mode==parent.st_mode else {throw ControlError.unauthorized}
        // Unrelated progress/health files may update the directory timestamps;
        // only its identity/ownership/mode and this exact file must stay bound.
        return try Self(bytes,expectedUID:expectedUID,expectedProfile:expectedProfile,boot:boot)
    }
}
