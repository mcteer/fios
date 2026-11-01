import Foundation
import Darwin

// One directly spawned child, never an adopted PID. Only this holder calls
// waitpid for that child; its lock serializes reaping and signalling, so the
// kernel cannot reuse the PID between the owned-child check and SIGTERM.
// No deinit signal/reap, global wait, shell, process-group or force fallback.
final class ServingOwnedProcess:@unchecked Sendable {
    private let executable:VerifiedExecutable
    private let arguments:[String]
    private let environment:[String:String]
    private let workingDirectory:String
    private let lock=NSLock()
    private var entered=false
    private var pid:Int32 = -1
    private var exited=false
    private var uncertain=false
    init(executable:VerifiedExecutable,arguments:[String],environment:[String:String],workingDirectory:String) {
        self.executable=executable;self.arguments=arguments;self.environment=environment;self.workingDirectory=workingDirectory
    }
    var processIdentifier:Int32 {lock.lock();defer {lock.unlock()};return pid}
    func run()throws {
        lock.lock();defer {lock.unlock()}
        guard !entered,arguments.count<=128,environment.count<=16,
              workingDirectory.hasPrefix("/"),workingDirectory.utf8.count<Int(MAXPATHLEN),!workingDirectory.contains("\0"),
              !workingDirectory.contains("//"),(workingDirectory=="/" || !workingDirectory.hasSuffix("/")),
              !workingDirectory.split(separator:"/").contains(where:{$0=="." || $0==".."}),
              (arguments+Array(environment.values)+Array(environment.keys)).allSatisfy({!$0.contains("\0") && $0.utf8.count<=4096}),
              workingDirectory.utf8.count+arguments.reduce(executable.path.utf8.count+1,{$0+$1.utf8.count+1})+environment.reduce(0,{$0+$1.key.utf8.count+$1.value.utf8.count+2})<=65536 else {throw RuntimeError.invalid}
        var actions:posix_spawn_file_actions_t?,attributes:posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions)==0 else {throw RuntimeError.invalid}
        defer {posix_spawn_file_actions_destroy(&actions)}
        guard posix_spawnattr_init(&attributes)==0 else {throw RuntimeError.invalid}
        defer {posix_spawnattr_destroy(&attributes)}
        var mask=sigset_t(),defaults=sigset_t()
        sigemptyset(&mask);sigemptyset(&defaults)
        for number in [SIGTERM,SIGINT,SIGHUP,SIGPIPE,SIGCHLD] {sigaddset(&defaults,number)}
        let flags=Int16(POSIX_SPAWN_CLOEXEC_DEFAULT|POSIX_SPAWN_SETSIGMASK|POSIX_SPAWN_SETSIGDEF)
        let directoryAction:Int32
        if #available(macOS 26.0,*) {directoryAction=posix_spawn_file_actions_addchdir(&actions,workingDirectory)}
        else {directoryAction=posix_spawn_file_actions_addchdir_np(&actions,workingDirectory)}
        guard posix_spawnattr_setflags(&attributes,flags)==0,
              directoryAction==0,
              posix_spawnattr_setsigmask(&attributes,&mask)==0,posix_spawnattr_setsigdefault(&attributes,&defaults)==0,
              posix_spawn_file_actions_addopen(&actions,STDIN_FILENO,"/dev/null",O_RDONLY,0)==0,
              posix_spawn_file_actions_addopen(&actions,STDOUT_FILENO,"/dev/null",O_WRONLY,0)==0,
              posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0)==0 else {throw RuntimeError.invalid}
        var argv=([executable.path]+arguments).map {$0.withCString {strdup($0)}}
        var env=environment.keys.sorted().map {key in (key+"="+environment[key]!).withCString {strdup($0)}}
        defer {for pointer in argv+env {if let pointer {free(pointer)}}}
        guard argv.allSatisfy({$0 != nil}),env.allSatisfy({$0 != nil}) else {throw RuntimeError.invalid}
        argv.append(nil);env.append(nil)
        entered=true
        let result=argv.withUnsafeMutableBufferPointer {args in
            env.withUnsafeMutableBufferPointer {variables in
                executable.path.withCString {path in posix_spawn(&pid,path,&actions,&attributes,args.baseAddress!,variables.baseAddress!)}
            }
        }
        guard result==0,pid>1 else {uncertain=true;throw RuntimeError.identity}
    }
    // Positive local reaping only. ECHILD/unknown ownership never becomes an
    // exit receipt or permission to signal an arbitrary process with this PID.
    private func reapLocked()->Bool {
        if exited {return true}
        guard entered,pid>1,!uncertain else {return false}
        var status:Int32=0
        for _ in 0..<3 {
            let result=waitpid(pid,&status,WNOHANG)
            if result==pid {exited=true;return true}
            if result==0 {return false}
            if result<0,errno==EINTR {continue}
            uncertain=true;return false
        }
        uncertain=true;return false
    }
    var isRunning:Bool {lock.lock();defer {lock.unlock()};return !reapLocked()}
    func terminate(expected:ServiceIdentity,deadline:TimeInterval)throws {
        lock.lock();defer {lock.unlock()}
        let now=ProcessInfo.processInfo.systemUptime
        guard expected.valid,expected.pid==pid,expected.sha256==executable.sha256,
              deadline.isFinite,deadline>now,deadline-now<=10 else {throw RuntimeError.identity}
        if reapLocked() {return}
        guard entered,pid>1,!uncertain else {throw RuntimeError.identity}
        _=try ServiceIdentity.verified(peer:NativeControlPeer(pid:pid,start:expected.start,executable:executable),expectedUID:geteuid(),deadline:min(deadline,ProcessInfo.processInfo.systemUptime+1))
        guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
        // A child which exits now remains our unreaped zombie. No other method
        // can release that PID while this lock is held. This is local custody,
        // not the independent native lifecycle reservation required by callers.
        guard kill(pid,SIGTERM)==0 else {uncertain=true;throw RuntimeError.identity}
    }
}
