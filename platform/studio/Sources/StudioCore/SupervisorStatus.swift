import Foundation
import Darwin
import CoreFoundation

public enum SupervisorStatus {
    public static func read(directory:URL,expectedExecutable:String) throws -> [String:Any] {
        let path=directory.appendingPathComponent("supervisor.json").path
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else { throw ControlError.busy };defer { close(fd) }
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode & S_IFMT == S_IFREG,info.st_uid==geteuid(),
              info.st_mode & 0o077==0,info.st_nlink==1,(1...4096).contains(info.st_size) else { throw ControlError.unauthorized }
        var bytes=[UInt8](repeating:0,count:4097),offset=0
        while offset<bytes.count {
            let count=bytes.withUnsafeMutableBytes { Darwin.read(fd,$0.baseAddress!.advanced(by:offset),$0.count-offset) }
            if count<0 && errno==EINTR { continue };guard count>=0 else { throw ControlError.internal_error }
            if count==0 { break };offset+=count
        }
        let data=Data(bytes.prefix(offset));try StrictJSON.validate(data,maximum:4096)
        guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(value.keys)==Set(["version","boot","pid","process_start","state","starts","sampled_uptime_ms"]) else { throw ControlError.invalid_request }
        func integer(_ key:String)->Int64? {
            guard let number=value[key] as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:number.objCType)) else { return nil };return number.int64Value
        }
        let now=Int64(ProcessInfo.processInfo.systemUptime*1000)
        guard integer("version")==1,value["boot"] as? String == (try HostBoot.identity()),
              let pid=integer("pid"),pid>1,pid<=Int32.max,
              let birth=integer("process_start"),birth>0,try WorkerResources.startIdentifier(pid:Int32(pid))==UInt64(birth),let time=integer("sampled_uptime_ms"),time>=0,
              (-1000...5000).contains(now-time),let starts=integer("starts"),(0...3).contains(starts),
              let state=value["state"] as? String,["starting","running","recovering","degraded"].contains(state) else { throw ControlError.busy }
        var executable=[UInt8](repeating:0,count:4096)
        let size=executable.withUnsafeMutableBytes { proc_pidpath(Int32(pid),$0.baseAddress,UInt32($0.count)) }
        guard size>0 else { throw ControlError.busy }
        let actual=String(decoding:executable.prefix(while:{$0 != 0}),as:UTF8.self)
        guard actual==URL(fileURLWithPath:expectedExecutable).resolvingSymlinksInPath().path else { throw ControlError.unauthorized }
        return ["version":1,"ok":true,"supervisor":value]
    }
}
