import Foundation

// Serialized manager-side coordinator. It emits finite work for an off-loop
// authenticated NativeControlClient; never blocks the controller or signals a
// service. An ingress acknowledgement cannot establish idle/device completion.
enum NativeMaintenancePhase:String,Equatable {case unknown,observing,changingAdmissions,admissionsClosed,admissionsOpen}
struct NativeMaintenanceCommand:Sendable {
    let id:String
    let operation:NativeControlOperation
    let instance:String?
    let sequence:UInt64
}
struct NativeMaintenanceCoordinator {
    let journal:Journal
    private(set) var phase:NativeMaintenancePhase = .unknown
    private(set) var pending:NativeMaintenanceCommand?
    var lifecycleApplied:Bool {false}

    mutating func setDesired(_ desired:ServiceDesired,role:ControlRole) throws {
        guard role == .operator else {throw NativeControlError.unauthorized}
        // This commits before any native command can be emitted. A failed or
        // lost acknowledgement never rolls desired maintenance back.
        try journal.setDesired(service:ManagedService.mlx.rawValue,desired:desired.rawValue)
        phase = .unknown
    }
    mutating func beginReconciliation() throws -> NativeMaintenanceCommand? {
        guard pending==nil,try journal.recordedDesired(service:.mlx) != nil else {return nil}
        return issue(.observe,instance:nil,sequence:0)
    }
    private mutating func issue(_ operation:NativeControlOperation,instance:String?,sequence:UInt64)->NativeMaintenanceCommand {
        let command=NativeMaintenanceCommand(id:UUID().uuidString.lowercased(),operation:operation,instance:instance,sequence:sequence)
        pending=command;phase = operation == .observe ? .observing:.changingAdmissions
        return command
    }
    mutating func failed(id:String) {
        guard pending?.id==id else {return}
        pending=nil;phase = .unknown
        // No retry/replay. A later reconciliation starts with authenticated
        // observation, never by resending the uncertain action.
    }
    mutating func receive(id:String,value:NativeIngressStatus) throws -> NativeMaintenanceCommand? {
        guard let command=pending,command.id==id else {throw NativeControlError.invalid}
        pending=nil;phase = .unknown
        guard command.operation==value.operation,
              command.instance==nil || command.instance==value.instance,
              value.status == .ok || (command.operation == .pause && value.status == .maintenance && value.closed),
              let desired=try journal.recordedDesired(service:.mlx) else {throw NativeControlError.invalid}
        _ = try NativeControlWire.instanceBytes(value.instance)
        guard value.closed ? value.pauseSequence>0:value.pauseSequence==0,
              command.operation != .pause || value.closed,
              command.operation != .resume || !value.closed else {throw NativeControlError.invalid}
        let shouldClose=desired != .running
        if value.closed==shouldClose {
            phase = shouldClose ? .admissionsClosed:.admissionsOpen
            return nil
        }
        // Latest durable operator intent wins if it changed while a request
        // was in flight. Every new action binds the authenticated current
        // source/pause identity. No force or native stop is inferred here.
        return issue(shouldClose ? .pause:.resume,instance:value.instance,sequence:shouldClose ? 0:value.pauseSequence)
    }
}
