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
    private(set) var observationOnly=false
    private var admissionsInstance:String?
    var lifecycleApplied:Bool {false}
    init(journal:Journal) {self.journal=journal}

    mutating func setDesired(_ desired:ServiceDesired,role:ControlRole) throws {
        guard role == .operator else {throw NativeControlError.unauthorized}
        // This commits before any native command can be emitted. A failed or
        // lost acknowledgement never rolls desired maintenance back.
        try journal.setDesired(service:ManagedService.mlx.rawValue,desired:desired.rawValue)
        phase = .unknown;admissionsInstance=nil
    }
    mutating func beginReconciliation() throws -> NativeMaintenanceCommand? {
        guard try journal.recordedDesired(service:.mlx) != nil else {return nil}
        if pending != nil {
            // An explicit command can use the already pending observation.
            // Never contend for a second connection or lose that intent.
            if observationOnly {observationOnly=false;phase = .observing}
            return nil
        }
        return issue(.observe,instance:nil,sequence:0)
    }
    mutating func beginObservation()->NativeMaintenanceCommand? {
        guard pending==nil else {return nil}
        return issue(.observe,instance:nil,sequence:0,observationOnly:true)
    }
    private mutating func issue(_ operation:NativeControlOperation,instance:String?,sequence:UInt64,observationOnly:Bool=false)->NativeMaintenanceCommand {
        let command=NativeMaintenanceCommand(id:UUID().uuidString.lowercased(),operation:operation,instance:instance,sequence:sequence)
        pending=command;self.observationOnly=observationOnly
        if !observationOnly {phase = operation == .observe ? .observing:.changingAdmissions}
        return command
    }
    mutating func failed(id:String) {
        guard pending?.id==id else {return}
        pending=nil;observationOnly=false;phase = .unknown;admissionsInstance=nil
        // No retry/replay. A later reconciliation starts with authenticated
        // observation, never by resending the uncertain action.
    }
    mutating func receive(id:String,value:NativeIngressStatus) throws -> NativeMaintenanceCommand? {
        guard let command=pending,command.id==id else {throw NativeControlError.invalid}
        let readOnly=observationOnly,previousPhase=phase,previousInstance=admissionsInstance
        pending=nil;observationOnly=false;phase = .unknown;admissionsInstance=nil
        guard command.operation==value.operation,
              command.instance==nil || command.instance==value.instance,
              value.status == .ok || (command.operation == .pause && value.status == .maintenance && value.closed) else {throw NativeControlError.invalid}
        _ = try NativeControlWire.instanceBytes(value.instance)
        guard value.closed ? value.pauseSequence>0:value.pauseSequence==0,
              command.operation != .pause || value.closed,
              command.operation != .resume || !value.closed else {throw NativeControlError.invalid}
        if readOnly {
            // A periodic read never reconciles/replays durable intent. It can
            // retain only a matching acknowledgement for the same source.
            if previousInstance==value.instance &&
                ((previousPhase == .admissionsClosed && value.closed) || (previousPhase == .admissionsOpen && !value.closed)) {
                phase=previousPhase;admissionsInstance=previousInstance
            }
            return nil
        }
        guard let desired=try journal.recordedDesired(service:.mlx) else {throw NativeControlError.invalid}
        let shouldClose=desired != .running
        if value.closed==shouldClose {
            phase = shouldClose ? .admissionsClosed:.admissionsOpen
            admissionsInstance=value.instance
            return nil
        }
        // Latest durable operator intent wins if it changed while a request
        // was in flight. Every new action binds the authenticated current
        // source/pause identity. No force or native stop is inferred here.
        return issue(shouldClose ? .pause:.resume,instance:value.instance,sequence:shouldClose ? 0:value.pauseSequence)
    }
}
