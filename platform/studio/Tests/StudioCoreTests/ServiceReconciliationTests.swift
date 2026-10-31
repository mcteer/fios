import Foundation

func runServiceReconciliationTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory),hash=String(repeating:"a",count:64)
    let pins:[ManagedService:String]=[.mlx:hash,.orbstack:hash]
    let oldJob=UUID().uuidString.lowercased()
    try journal.claim(job:oldJob,attempt:0,model:"fixture/independent")
    try journal.markUncertain(job:oldJob,attempt:0)
    func absent(_ now:Int64)->ServiceObservation {
        ServiceObservation(identity:nil,responding:false,sessionReady:true,credentialsReady:true,nativeIdle:nil,runtimeUnmanaged:nil,sampledAt:now)
    }
    var recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard let first=try recovery.next(service:.mlx,desired:.running,observation:absent(1000),now:1000,tick:1000),first.operation == .launch else {fatalError("New launch did not reserve one typed dispatch")}
    let persisted=try Data(contentsOf:directory.appendingPathComponent("service-recovery.json"))
    guard String(decoding:persisted,as:UTF8.self).contains(first.command.id) else {fatalError("Transport command escaped before durable intent")}
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard let lookup=try recovery.next(service:.mlx,desired:.stopped,observation:nil,now:700000,tick:700000),
          lookup.operation == .lookup,lookup.command.id==first.command.id,
          lookup.command.profileHash==first.command.profileHash else {fatalError("Restart/age/operator stop reissued or lost pending launch")}
    for result:SessionLaunchResult in [.uncertain,.busy,.wrongInstance] {try recovery.receive(lookup,result:result)}
    guard try Data(contentsOf:directory.appendingPathComponent("service-recovery.json"))==persisted else {fatalError("Unknown transport outcome retired durable ownership")}
    let foreignJournal=try Journal(directory:directory.appendingPathComponent("other-controller"))
    let foreignController=try ServiceRecoveryController(journal:foreignJournal,approvedHashes:pins)
    guard let foreign=try foreignController.next(service:.mlx,desired:.running,observation:absent(1000),now:1000,tick:1000) else {fatalError("Missing foreign controller fixture")}
    do {try recovery.receive(foreign,result:.notSent);fatalError("Foreign request retired pending service intent")}catch ServiceError.invalid {}
    try recovery.receive(lookup,result:.notSent)
    guard try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {fatalError("Service reconciliation cleared native inference uncertainty")}
    guard let second=try recovery.next(service:.mlx,desired:.running,observation:absent(700001),now:700001,tick:700001),
          second.operation == .launch,second.command.id != first.command.id else {fatalError("Known non-dispatch did not permit a later independently budgeted start")}
    do {try recovery.receive(lookup,result:.notSent);fatalError("Old lookup retired a new intent")}catch ServiceError.invalid {}
    guard let fenced=try recovery.next(service:.mlx,desired:.running,observation:absent(699999),now:699999,tick:699999),
          fenced.operation == .lookup,fenced.command.id==second.command.id else {fatalError("Clock fence hid pending reconciliation or dispatched another launch")}
    try recovery.receive(fenced,result:.notSent)
    recovery=try ServiceRecoveryController(journal:journal,approvedHashes:pins)
    guard try recovery.next(service:.mlx,desired:.running,observation:absent(800000),now:800000,tick:800000)==nil else {fatalError("Lookup acknowledgement erased the persistent launch clock fence")}
    print("PASS: typed once-only launch versus safe lookup, durable-before-transport, stopped/restarted/aged/fenced reconciliation, correlated receipts and independent native uncertainty retention")
}
