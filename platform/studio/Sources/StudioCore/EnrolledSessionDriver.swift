import Foundation

public struct SessionNativeApplication:Sendable {
    public let service:ManagedService
    public let bundle:URL
    public let identifier:String
    let team:String?
    init(service:ManagedService) {
        self.service=service
        switch SessionPlan.fixed(service:service,operation:.launch) {
        case .launchApplication(let path):bundle=URL(fileURLWithPath:path)
        case .quitApplication:preconditionFailure("Launch mapping selected quit")
        }
        identifier=service == .mlx ? "com.dalcu.mlx-core":"dev.kdrag0n.MacVirt"
        team=service == .mlx ? "S77TW432YG":nil
    }
}
// Code-only native adapter, not decoded policy. The public factory always
// performs fixed root enrollment and immutable application verification;
// callers cannot replace the validator. Only the session target imports AppKit.
public struct SessionNativeOperations:Sendable {
    let consoleReady:@MainActor @Sendable()->Bool
    let alreadyRunning:@MainActor @Sendable(SessionNativeApplication)->Bool
    let open:@MainActor @Sendable(SessionNativeApplication,@escaping @MainActor @Sendable(Int32?,Bool)->Void)->Void
    public init(consoleReady:@escaping @MainActor @Sendable()->Bool,
                alreadyRunning:@escaping @MainActor @Sendable(SessionNativeApplication)->Bool,
                open:@escaping @MainActor @Sendable(SessionNativeApplication,@escaping @MainActor @Sendable(Int32?,Bool)->Void)->Void) {
        self.consoleReady=consoleReady;self.alreadyRunning=alreadyRunning;self.open=open
    }
}

struct SessionApplicationCheck:Sendable {
    let id:String
    let service:ManagedService
    let bundle:URL
    let executable:VerifiedExecutable
    let identifier:String
    let team:String?
    let deadline:TimeInterval
}
// Trusted programmatic adapters for isolated fixtures; not an IPC/CLI policy
// selector. StudioSession cannot access this internal initializer or type.
struct SessionDriverPorts:Sendable {
    let validate:@Sendable(SessionApplicationCheck)throws->Void
    let consoleReady:@MainActor @Sendable()->Bool
    let alreadyRunning:@MainActor @Sendable(ManagedService)->Bool
    let open:@MainActor @Sendable(ManagedService,@escaping @MainActor @Sendable(Int32?,Bool)->Void)->Void
}

@MainActor public final class EnrolledSessionDriver {
    private struct Check {let id:String;let service:ManagedService;let deadline:TimeInterval;var cancelled=false}
    private let server:SessionControlServer
    private let applications:[ManagedService:VerifiedExecutable]
    private let ports:SessionDriverPorts
    private var checking:Check?
    private var opening:Set<String>=[]
    private var stopped=false

    public static func enrolled(directory:URL,operations:SessionNativeOperations)throws->EnrolledSessionDriver? {
        guard let policy=try SessionEnrolledPolicy.load(directory:directory,role:.session) else {return nil}
        return try EnrolledSessionDriver(directory:directory,manager:policy.manager,applications:policy.applications,ports:nativePorts(operations))
    }
    init(directory:URL,manager:VerifiedExecutable,applications:[ManagedService:VerifiedExecutable],ports:SessionDriverPorts)throws {
        self.applications=applications;self.ports=ports
        server=try SessionControlServer(directory:directory,manager:manager,approvedApplications:applications)
    }
    public func poll(consoleReady:Bool,now:Int64)throws {
        guard !stopped else {return}
        if var check=checking,!check.cancelled,ProcessInfo.processInfo.systemUptime>=check.deadline {
            // Revoke the local future-effect edge BEFORE acknowledging. The
            // read-only validator may still be running: retain its one slot,
            // and its completion can no longer call the application adapter.
            check.cancelled=true;checking=check
            server.acknowledgeNotSent(id:check.id,service:check.service)
        }
        try server.poll(consoleReady:consoleReady,now:now) {service,id in self.begin(service:service,id:id)}
    }
    public func shutdown() {stopped=true;checking=nil} // Never quits native apps.

    private func begin(service:ManagedService,id:String)->SessionLaunchResult {
        guard !stopped,checking==nil,let executable=applications[service] else {return .notSent}
        let deadline=ProcessInfo.processInfo.systemUptime+10
        checking=Check(id:id,service:service,deadline:deadline)
        let application=SessionNativeApplication(service:service)
        let command=SessionApplicationCheck(id:id,service:service,bundle:application.bundle,executable:executable,
            identifier:application.identifier,team:application.team,deadline:deadline)
        let validate=ports.validate
        // One read-only validation task at a time. No application effect occurs
        // on this worker; completion returns to the serialized main actor.
        Task.detached { [weak self] in
            let valid:Bool
            do {try validate(command);valid=true}
            catch {valid=false}
            await self?.validated(service:service,id:id,valid:valid)
        }
        return .uncertain
    }
    private func validated(service:ManagedService,id:String,valid:Bool) {
        guard !stopped,let check=checking,check.id==id,check.service==service else {return}
        checking=nil // This validation completion cannot dispatch again.
        guard !check.cancelled else {return}
        guard valid,ProcessInfo.processInfo.systemUptime<check.deadline,ports.consoleReady(),!ports.alreadyRunning(service) else {
            server.acknowledgeNotSent(id:id,service:service);return
        }
        guard server.claimDispatch(id:id,service:service) else {return}
        opening.insert(id)
        ports.open(service) { [weak self] pid,success in self?.opened(service:service,id:id,pid:pid,success:success) }
    }
    private func opened(service:ManagedService,id:String,pid:Int32?,success:Bool) {
        guard !stopped,opening.remove(id) != nil else {return}
        // Once dispatched, error/timeout/absence cannot become a non-dispatch
        // receipt or native terminality proof.
        guard success,let pid,let start=try? WorkerResources.startIdentifier(pid:pid),let executable=applications[service] else {return}
        _=try? server.acknowledgeStarted(id:id,service:service,identity:ServiceIdentity(pid:pid,start:start,sha256:executable.sha256))
    }
    private static func nativePorts(_ operations:SessionNativeOperations)->SessionDriverPorts {
        SessionDriverPorts(validate:{command in
            try ApplicationIdentity.verify(bundle:command.bundle,executable:command.executable,identifier:command.identifier,team:command.team,deadline:command.deadline)
        },consoleReady:operations.consoleReady,alreadyRunning:{service in
            operations.alreadyRunning(SessionNativeApplication(service:service))
        },open:{service,completion in
            operations.open(SessionNativeApplication(service:service),completion)
        })
    }
}
