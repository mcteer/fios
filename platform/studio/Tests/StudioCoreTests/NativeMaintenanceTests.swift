import Foundation

func runNativeMaintenanceTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-maintenance-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let instance=String(repeating:"07",count:16)
    func reply(_ operation:NativeControlOperation,closed:Bool,sequence:UInt64=1)->NativeIngressStatus {
        NativeIngressStatus(operation:operation,status:.ok,instance:instance,pauseSequence:closed ? sequence:0,owners:0,ingress:0,preparing:0,active:0,responding:0,modelIdentities:0,closed:closed,uncertain:true)
    }
    do {
        let journal=try Journal(directory:directory)
        var coordinator=NativeMaintenanceCoordinator(journal:journal)
        guard try coordinator.beginReconciliation()==nil else {fatalError("Absent desired row resumed native admissions")}
        do {try coordinator.setDesired(.maintenance,role:.task);fatalError("Model/task changed native maintenance")}catch{}
        guard try journal.recordedDesired(service:.mlx)==nil else {fatalError("Denied maintenance request changed journal")}
        try coordinator.setDesired(.maintenance,role:.operator)
        guard try journal.desired(service:"mlx")=="maintenance",let observe=try coordinator.beginReconciliation(),observe.operation == .observe else {fatalError("Maintenance not persisted before native I/O")}
        guard let pause=try coordinator.receive(id:observe.id,value:reply(.observe,closed:false)),pause.operation == .pause,pause.instance==instance else {fatalError("Native pause not bound to observed source")}
        guard try coordinator.beginReconciliation()==nil else {fatalError("Duplicate in-flight native operation")}
        coordinator.failed(id:pause.id)
        guard coordinator.phase == .unknown,try journal.desired(service:"mlx")=="maintenance" else {fatalError("Lost native reply cleared maintenance")}
        // Reconciliation observes truth; it does not replay a lost pause.
        guard let reconcile=try coordinator.beginReconciliation(),reconcile.operation == .observe,
              try coordinator.receive(id:reconcile.id,value:reply(.observe,closed:true))==nil,
              coordinator.phase == .admissionsClosed else {fatalError("Lost pause was replayed instead of observed")}
    }
    do {
        // Old writer is gone before opening this same disposable database.
        let journal=try Journal(directory:directory)
        var coordinator=NativeMaintenanceCoordinator(journal:journal)
        guard let observe=try coordinator.beginReconciliation(),
              try coordinator.receive(id:observe.id,value:reply(.observe,closed:true,sequence:7))==nil,
              coordinator.phase == .admissionsClosed else {fatalError("Restart lost durable maintenance")}
        try coordinator.setDesired(.running,role:.operator)
        guard let check=try coordinator.beginReconciliation(),
              let resume=try coordinator.receive(id:check.id,value:reply(.observe,closed:true,sequence:7)),
              resume.operation == .resume,resume.sequence==7 else {fatalError("Resume not bound to native pause identity")}
        guard try coordinator.receive(id:resume.id,value:reply(.resume,closed:false))==nil,
              coordinator.phase == .admissionsOpen else {fatalError("Resume confirmation not reconciled")}
        // Open admissions never mean native lifecycle applied, idle or certain.
        guard coordinator.lifecycleApplied == false else {fatalError("Ingress status became native lifecycle authority")}
    }
    do {
        let journal=try Journal(directory:directory)
        var coordinator=NativeMaintenanceCoordinator(journal:journal)
        try coordinator.setDesired(.maintenance,role:.operator)
        guard let observe=try coordinator.beginReconciliation(),
              let pause=try coordinator.receive(id:observe.id,value:reply(.observe,closed:false)) else {fatalError("Missing maintenance plan")}
        do {_ = try coordinator.receive(id:pause.id,value:reply(.pause,closed:false));fatalError("Contradictory acknowledgement retried native action")}catch{}
        guard coordinator.phase == .unknown,coordinator.pending==nil,try journal.desired(service:"mlx")=="maintenance" else {fatalError("Contradictory native outcome cleared durable maintenance")}
    }
    print("PASS: durable operator-only maintenance, restart reconciliation, no lost-action replay and no ingress-to-lifecycle authority escalation")
}
