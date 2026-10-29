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
        guard timeout > 0, timeout <= 10, maximumOutput >= 0, maximumOutput <= 1 << 20,
              arguments.count <= 128, arguments.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4096 }) else { throw RuntimeError.invalid }
        let childEnvironment=try CommandEnvironment.sanitized(environment)
        try CommandSlots.shared.acquire()
        var commandProcess:Process?
        defer {CommandSlots.shared.release(commandProcess)}
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try verify(deadline:deadline)
        guard ProcessInfo.processInfo.systemUptime<deadline else {throw RuntimeError.deadline}
        let process = Process(), pipe = Pipe()
        commandProcess=process
        process.executableURL = URL(fileURLWithPath:path); process.arguments = arguments
        process.environment = childEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let processStart=try? WorkerResources.startIdentifier(pid:process.processIdentifier)
        func signalOwned(_ signal:Int32) {
            guard process.isRunning,let processStart,
                  (try? WorkerResources.startIdentifier(pid:process.processIdentifier))==processStart else {return}
            kill(process.processIdentifier,signal)
        }
        pipe.fileHandleForWriting.closeFile()
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd,F_SETFL,O_NONBLOCK)
        defer { pipe.fileHandleForReading.closeFile() }
        var output = Data(), failure: RuntimeError?
        var termAt: TimeInterval?
        var killed = false
        var eof = false
        while !eof || process.isRunning {
            var buffer = [UInt8](repeating:0,count:4096)
            let count = read(fd,&buffer,buffer.count)
            if count > 0 {
                if output.count + count > maximumOutput { failure = .outputLimit }
                else if failure == nil { output.append(contentsOf:buffer.prefix(count)) }
            } else if count == 0 { eof = true }
            else if errno != EAGAIN && errno != EINTR { failure = .launch; eof = true }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= deadline && failure == nil { failure = .deadline }
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
        process.waitUntilExit()
        if let failure { throw failure }
        return CommandResult(status:process.terminationStatus,output:output)
    }
}
