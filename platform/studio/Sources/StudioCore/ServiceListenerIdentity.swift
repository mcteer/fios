import Foundation
import Darwin

// Read-only association with a listening socket in one exact process. This is
// not global listener exclusivity, response authentication or native authority.
// Keep opaque kernel socket identifiers internal and out of status/log output.
struct ServiceListenerIdentity:Equatable {
    let process:ServiceIdentity
    let descriptor:Int32
    let generation:UInt64
    let socket:UInt64
    let pcb:UInt64
}

enum ServiceListenerProbe {
    static func capture(process:ServiceIdentity,address:String,port:UInt16)->ServiceListenerIdentity? {
        let began=ProcessInfo.processInfo.systemUptime
        guard process.valid,port>0,
              (try? WorkerResources.startIdentifier(pid:process.pid))==process.start else {return nil}
        // One bounded list, including a sentinel entry to detect truncation.
        let maximum=4096,entrySize=MemoryLayout<proc_fdinfo>.stride
        var entries=[proc_fdinfo](repeating:proc_fdinfo(),count:maximum+1)
        let count=entries.withUnsafeMutableBytes {
            proc_pidinfo(process.pid,PROC_PIDLISTFDS,0,$0.baseAddress,Int32($0.count))
        }
        guard count>0,Int(count)%entrySize==0,Int(count)/entrySize<=maximum else {return nil}
        var found:ServiceListenerIdentity?
        var ipv4=in_addr(),ipv6=in6_addr()
        let isIPv4=address.withCString {inet_pton(AF_INET,$0,&ipv4)}==1
        guard isIPv4 || address.withCString({inet_pton(AF_INET6,$0,&ipv6)})==1 else {return nil}
        for entry in entries.prefix(Int(count)/entrySize) where entry.proc_fdtype==PROX_FDTYPE_SOCKET {
            guard ProcessInfo.processInfo.systemUptime-began<0.5 else {return nil}
            var info=socket_fdinfo()
            guard proc_pidfdinfo(process.pid,entry.proc_fd,PROC_PIDFDSOCKETINFO,&info,Int32(MemoryLayout<socket_fdinfo>.size))==MemoryLayout<socket_fdinfo>.size else {return nil}
            let socket=info.psi,tcp=socket.soi_proto.pri_tcp,ip=tcp.tcpsi_ini
            guard socket.soi_kind==SOCKINFO_TCP,socket.soi_type==SOCK_STREAM,
                  socket.soi_protocol==IPPROTO_TCP,tcp.tcpsi_state==TSI_S_LISTEN,
                  ip.insi_lport==Int32(port.bigEndian) else {continue}
            let matches:Bool
            if isIPv4 {
                matches=socket.soi_family==AF_INET && ip.insi_vflag & UInt8(INI_IPV4) != 0 &&
                    (ip.insi_laddr.ina_46.i46a_addr4.s_addr==ipv4.s_addr || ip.insi_laddr.ina_46.i46a_addr4.s_addr==INADDR_ANY)
            } else {
                let actual=withUnsafeBytes(of:ip.insi_laddr.ina_6) {Array($0)}
                let expected=withUnsafeBytes(of:ipv6) {Array($0)}
                matches=socket.soi_family==AF_INET6 && ip.insi_vflag & UInt8(INI_IPV6) != 0 &&
                    (actual==expected || actual.allSatisfy({$0==0}))
            }
            guard matches else {continue}
            // Sharing or multiple matching descriptors cannot identify a sole
            // local listener. Other-process exclusivity remains separate.
            guard found==nil,Int32(socket.soi_options)&SO_REUSEPORT==0,
                  ip.insi_gencnt>0,socket.soi_so>0,socket.soi_pcb>0 else {return nil}
            found=ServiceListenerIdentity(process:process,descriptor:entry.proc_fd,
                generation:ip.insi_gencnt,socket:socket.soi_so,pcb:socket.soi_pcb)
        }
        guard ProcessInfo.processInfo.systemUptime-began<0.5,
              (try? WorkerResources.startIdentifier(pid:process.pid))==process.start else {return nil}
        return found
    }
}
