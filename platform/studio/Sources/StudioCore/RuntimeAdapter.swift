import Foundation
import Darwin
import CryptoKit

public enum RuntimeError: Error { case invalid, identity, launch, deadline, outputLimit, capacity }
public struct CommandResult:Sendable { public let status: Int32; public let output: Data }

// Native CLIs receive no inherited credentials, dynamic-library configuration,
// Docker context/endpoint, or caller replacement of the fixed PATH/locale.
// These are reviewed code-only inputs; no task/operator JSON reaches this API.
enum CommandEnvironment {
    static func sanitized(_ requested:[String:String]) throws -> [String:String] {
        guard Set(requested.keys).isSubset(of:["HOME","DOCKER_CONFIG","DOCKER_CLI_HINTS"]) else {throw RuntimeError.invalid}
        if let home=requested["HOME"] {
            guard home.hasPrefix("/"),home.utf8.count<Int(MAXPATHLEN),!home.contains("\0"),
                  !home.contains("//"),!home.hasSuffix("/"),
                  !home.split(separator:"/").contains(where:{$0=="." || $0==".."}) else {throw RuntimeError.invalid}
        }
        if let config=requested["DOCKER_CONFIG"],config != "/var/empty" {throw RuntimeError.invalid}
        if let hints=requested["DOCKER_CLI_HINTS"],hints != "false" {throw RuntimeError.invalid}
        return ["PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C"].merging(requested) {_,new in new}
    }
}

// Only trusted enrolled policy constructs these objects. No untrusted IPC
// accepts executable paths, argv or environment dictionaries.
public struct VerifiedExecutable:Sendable {
    public let path: String
    public let sha256: String
    public init(path: String, sha256: String) throws {
        guard path.hasPrefix("/"),path.utf8.count<Int(MAXPATHLEN),!path.contains("\0"),
              !path.contains("//"),!path.hasSuffix("/"),
              !path.split(separator:"/").contains(where:{$0=="." || $0==".."}),sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw RuntimeError.invalid }
        self.path = path; self.sha256 = sha256
    }
    func verify(deadline:TimeInterval=ProcessInfo.processInfo.systemUptime+2) throws {
        guard deadline.isFinite,ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)
        guard fd>=0 else {throw RuntimeError.identity};defer {Darwin.close(fd)}
        var before=stat(),after=stat(),named=stat()
        guard fstat(fd,&before)==0,before.st_mode & S_IFMT == S_IFREG,
              before.st_mode & 0o6022 == 0,before.st_mode & 0o111 != 0,before.st_nlink==1,
              before.st_uid==0 || before.st_uid==geteuid(),before.st_size>0,before.st_size<=512<<20 else {throw RuntimeError.identity}
        var hash=SHA256(),bytes=[UInt8](repeating:0,count:32768),total:Int64=0
        while true {
            guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count<0 && errno==EINTR {continue}
            guard count>=0 else {throw RuntimeError.identity};if count==0 {break}
            total+=Int64(count);guard total<=before.st_size else {throw RuntimeError.identity}
            hash.update(data:Data(bytes.prefix(count)))
        }
        guard total==before.st_size,fstat(fd,&after)==0,lstat(path,&named)==0,
              before.st_dev==after.st_dev,before.st_ino==after.st_ino,before.st_size==after.st_size,
              before.st_uid==after.st_uid,before.st_mode==after.st_mode,after.st_nlink==1,
              before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              named.st_dev==after.st_dev,named.st_ino==after.st_ino,named.st_mode==after.st_mode,
              named.st_uid==after.st_uid,named.st_nlink==1,named.st_size==after.st_size,
              named.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec,named.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec,
              named.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec,named.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec,
              hash.finalize().map({String(format:"%02x",$0)}).joined()==sha256 else {throw RuntimeError.identity}
        // This authenticates the current file, not future path-based spawn.
        // Reviewed immutable artifact/profile lifetime remains mandatory.
    }
    public func run(arguments: [String], timeout: TimeInterval, maximumOutput: Int = 1 << 20,
                    environment: [String:String] = [:]) throws -> CommandResult {
        try runChecked(arguments:arguments,timeout:timeout,maximumOutput:maximumOutput,environment:environment,checkpoint:{})
    }
    func runChecked(arguments:[String],timeout:TimeInterval,maximumOutput:Int=1<<20,
                    environment:[String:String]=[:],checkpoint:()throws->Void)throws->CommandResult {
        try runBounded(arguments:arguments,timeout:timeout,maximumOutput:maximumOutput,
            environment:CommandEnvironment.sanitized(environment),checkpoint:checkpoint)
    }
    // Fixed metadata operation only. Preserve a verified venv invocation alias
    // while sharing CLI capacity, exact-child signalling and bounded reap.
    func platformWorkerMetadata(invocation:String)throws->CommandResult {
        try runBounded(arguments:["-I","-B","-m","fios_agent.platform_worker","--metadata"],timeout:10,maximumOutput:4096,
            environment:["PATH":"/usr/bin:/bin","LANG":"C","LC_ALL":"C","HOME":"/var/empty","PYDANTIC_AI_NO_BANNER":"1"],
            invocation:invocation,workingDirectory:"/var/empty",discardStandardError:true)
    }
    private func runBounded(arguments:[String],timeout:TimeInterval,maximumOutput:Int,environment:[String:String],
                            invocation:String?=nil,workingDirectory:String?=nil,discardStandardError:Bool=false,
                            checkpoint:()throws->Void={})throws->CommandResult {
        guard timeout > 0, timeout <= 10, maximumOutput >= 0, maximumOutput <= 1 << 20,
              arguments.count <= 128, arguments.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4096 }) else { throw RuntimeError.invalid }
        try CommandSlots.shared.acquire()
        var commandProcess:Process?
        var processStart:UInt64?
        defer {CommandSlots.shared.release(commandProcess,start:processStart)}
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try verify(deadline:deadline)
        if let invocation {
            var named=stat()
            guard invocation.hasPrefix("/"),!invocation.contains("\0"),invocation.utf8.count<=4096,
                  lstat(invocation,&named)==0,named.st_uid==0 || named.st_uid==geteuid(),
                  [S_IFREG,S_IFLNK].contains(named.st_mode&S_IFMT),
                  named.st_mode&S_IFMT==S_IFLNK || named.st_mode&0o022==0,
                  URL(fileURLWithPath:invocation).resolvingSymlinksInPath().path==path else {throw RuntimeError.identity}
        }
        guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
        let process = Process(), pipe = Pipe()
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd,F_GETFL)
        // Establish nonblocking reads before starting the child. Otherwise
        // a silent command could block read() past all cleanup deadlines.
        guard flags >= 0,fcntl(fd,F_SETFL,flags | O_NONBLOCK)==0 else {throw RuntimeError.launch}
        process.executableURL = URL(fileURLWithPath:invocation ?? path); process.arguments = arguments
        process.environment = environment
        if let workingDirectory {process.currentDirectoryURL=URL(fileURLWithPath:workingDirectory)}
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        if discardStandardError {process.standardError=FileHandle.nullDevice}else {process.standardError=pipe}
        try checkpoint()
        guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
        commandProcess=process
        try process.run()
        processStart=try? WorkerResources.startIdentifier(pid:process.processIdentifier)
        func signalOwned(_ signal:Int32) {
            guard process.isRunning,let processStart,
                  (try? WorkerResources.startIdentifier(pid:process.processIdentifier))==processStart else {return}
            kill(process.processIdentifier,signal)
        }
        pipe.fileHandleForWriting.closeFile()
        defer { pipe.fileHandleForReading.closeFile() }
        var output = Data(), failure: RuntimeError?
        var termAt: TimeInterval?
        var killed = false
        var eof = false
        var buffer = [UInt8](repeating:0,count:4096)
        while !eof || process.isRunning {
            // EOF ends pipe work, not process supervision or its deadline.
            let count = eof ? 0 : read(fd,&buffer,buffer.count)
            let readError = count < 0 ? errno : 0
            let now = ProcessInfo.processInfo.systemUptime
            // Output first observed at or after the cutoff cannot supersede
            // the deadline, nor can later drain failures replace a cause.
            if failure == nil {failure=Self.outputFailure(now:now,deadline:deadline,count:count,error:readError,remaining:maximumOutput-output.count)}
            if count > 0 {
                if failure == nil {output.append(contentsOf:buffer.prefix(count))}
            } else if count == 0 || (readError != EAGAIN && readError != EINTR) {eof = true}
            if failure != nil && termAt == nil {
                termAt = now
                signalOwned(SIGTERM)
            }
            if let termAt, now - termAt >= 1, process.isRunning, !killed {
                signalOwned(SIGKILL); killed = true
            }
            if let termAt, now - termAt >= 2 {
                // A runtime CLI timeout never proves its daemon action absent.
                // No retry or reservation release is performed by this layer.
                throw failure ?? RuntimeError.deadline
            }
            if !eof || process.isRunning { Thread.sleep(forTimeInterval:0.005) }
        }
        // EOF plus Foundation exit observation makes terminationStatus available;
        // slot release independently requires kernel absence. No blocking join.
        if let failure { throw failure }
        return try Self.terminalResult(deadline:deadline,output:output,status:{process.terminationStatus})
    }
    static func outputFailure(now:TimeInterval,deadline:TimeInterval,count:Int,error:Int32,remaining:Int)->RuntimeError? {
        guard now.isFinite,now>=0,now<deadline else {return .deadline}
        if count>remaining {return .outputLimit}
        if count<0,error != EAGAIN,error != EINTR {return .launch}
        return nil
    }
    static func terminalResult(deadline:TimeInterval,output:Data,status:()->Int32,
                               uptime:()->TimeInterval={ProcessInfo.processInfo.systemUptime})throws->CommandResult {
        let exit=status()
        let observed=uptime()
        guard deadline.isFinite,observed.isFinite,observed>=0,observed<deadline else {throw RuntimeError.deadline}
        return CommandResult(status:exit,output:output)
    }
}
