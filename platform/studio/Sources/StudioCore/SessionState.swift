import Foundation
import Darwin
import CoreFoundation

public enum HostBoot {
    // Opaque kernel start ticks, represented canonically as a string rather
    // than a lossy JSON double/safe-integer timestamp. Not lifecycle authority.
    public static func processStartIdentifier(pid:Int32) throws -> String {
        String(try WorkerResources.startIdentifier(pid:pid))
    }
    public static func identity() throws -> String {
        // kern.boottime is wall-clock-derived; a clock adjustment must not
        // reset the supervisor's finite restart budget within the same boot.
        var bytes=[UInt8](repeating:0,count:128),size=128
        let result=bytes.withUnsafeMutableBytes { sysctlbyname("kern.bootsessionuuid",$0.baseAddress,&size,nil,0) }
        guard result==0,size>0,size<=128,
              let boot=UUID(uuidString:String(decoding:bytes.prefix(size).prefix(while:{$0 != 0}),as:UTF8.self)) else { throw JournalError.storage }
        return boot.uuidString.lowercased()
    }
}

struct SessionState {
    let console:Bool
    let mlxPresent:Bool
    let orbstackPresent:Bool
    let lifecycleEnabled:Bool
    static func read(directory:URL,boot:String,now:Int64)->SessionState? {
        let path=directory.appendingPathComponent("session.json").path
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else { return nil };defer { close(fd) }
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode & S_IFMT == S_IFREG,info.st_uid==geteuid(),
              info.st_mode & 0o077==0,info.st_nlink==1,(1...4096).contains(info.st_size),
              now>=0,now<=ActivityPolicy.maximumTimestamp else { return nil }
        var bytes=[UInt8](repeating:0,count:4097),offset=0
        while offset<bytes.count {
            let count=bytes.withUnsafeMutableBytes { Darwin.read(fd,$0.baseAddress!.advanced(by:offset),$0.count-offset) }
            if count<0 && errno==EINTR { continue }
            guard count>=0 else { return nil }
            if count==0 { break };offset+=count
        }
        guard offset<=4096 else { return nil }
        let data=Data(bytes.prefix(offset))
        guard (try? StrictJSON.validate(data,maximum:4096)) != nil,
              let fields=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              Set(fields.keys)==Set(["version","uid","pid","process_start","boot","sampled_uptime_ms","console_session","mlx_present","orbstack_present","lifecycle_enabled"]) else { return nil }
        func integer(_ name:String)->Int64? {
            guard let value=fields[name] as? NSNumber,CFGetTypeID(value) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:value.objCType)) else { return nil }
            return value.int64Value
        }
        func boolean(_ name:String)->Bool? {
            guard let value=fields[name] as? NSNumber,CFGetTypeID(value)==CFBooleanGetTypeID() else { return nil }
            return value.boolValue
        }
        guard integer("version")==2,integer("uid")==Int64(geteuid()),fields["boot"] as? String==boot,
              let pid=integer("pid"),pid>1,pid<=Int32.max,
              let start=fields["process_start"] as? String,let ticks=UInt64(start),ticks>0,String(ticks)==start,
              (try? WorkerResources.startIdentifier(pid:Int32(pid)))==ticks,
              let time=integer("sampled_uptime_ms"),time>=0,time<=ActivityPolicy.maximumTimestamp,
              (-1000...5000).contains(now-time),let console=boolean("console_session"),
              let mlx=boolean("mlx_present"),let orb=boolean("orbstack_present"),let enabled=boolean("lifecycle_enabled"),!enabled else { return nil }
        return SessionState(console:console,mlxPresent:mlx,orbstackPresent:orb,lifecycleEnabled:enabled)
    }
}
