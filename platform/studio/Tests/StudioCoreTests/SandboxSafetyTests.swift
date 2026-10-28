import Foundation

func runSandboxSafetyTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("fios-sandbox-safety-"+UUID().uuidString)
    var journal:Journal?=try Journal(directory:directory)
    var lifecycle:SandboxLifecycle?=SandboxLifecycle(journal:journal!)
    defer {lifecycle=nil;journal=nil;try? FileManager.default.removeItem(at:directory)}
    let owner=String(repeating:"a",count:64),digest=String(repeating:"b",count:64)
    func reserve()throws->(DurableJob,SandboxConfiguration) {
        let job=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),ownerHash:owner,requestHash:digest,created:1000)
        let config=try SandboxConfiguration(job:job.id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1)
        _=try journal!.reserveSandbox(job:job,configuration:config)
        return (job,config)
    }
    let (job,config)=try reserve(),id=String(repeating:"e",count:64),sentinel=String(repeating:"f",count:64)
    guard case .create?=try lifecycle!.next(job:job.id,now:1000,resourcesSafe:true) else {fatalError("Create intent missing")}
    try lifecycle!.created(job:job.id,runtimeID:id)
    let stopped=SandboxPresence.present(id:id,name:"/"+config.name,image:config.image,nonce:config.nonce,running:false)
    let running=SandboxPresence.present(id:id,name:"/"+config.name,image:config.image,nonce:config.nonce,running:true)
    for presence in [
        SandboxPresence.present(id:sentinel,name:"/"+config.name,image:config.image,nonce:config.nonce,running:true),
        .present(id:id,name:"/unrelated-sentinel",image:config.image,nonce:config.nonce,running:true),
        .present(id:id,name:"/"+config.name,image:"sha256:"+String(repeating:"0",count:64),nonce:config.nonce,running:true),
        .present(id:id,name:"/"+config.name,image:config.image,nonce:String(repeating:"0",count:64),running:true)
    ] {
        do {_=try lifecycle!.observed(job:job.id,presence:presence,now:1001,resourcesSafe:true);fatalError("Foreign/sentinel identity generated a command")}catch RuntimeError.identity{}
    }
    guard case .start(let start)?=try lifecycle!.observed(job:job.id,presence:stopped,now:1002,resourcesSafe:true),start==id else {fatalError("Owned start missing")}
    _=try lifecycle!.observed(job:job.id,presence:running,now:1003,resourcesSafe:true)
    try lifecycle!.cancelled(job:job.id,now:1004)
    guard case .stop(let stop)?=try lifecycle!.observed(job:job.id,presence:running,now:1005,resourcesSafe:true),stop==id else {fatalError("Owned stop missing")}
    // Lost/failed stop acknowledgement is NOT proof of ten seconds of daemon
    // grace. A still-running observation must not advance to rm --force.
    guard case .stop(let repeated)?=try lifecycle!.observed(job:job.id,presence:running,now:1006,resourcesSafe:true),repeated==id else {fatalError("Lost stop reply bypassed graceful stop with force removal")}
    guard case .remove(_,let remove)?=try lifecycle!.observed(job:job.id,presence:stopped,now:1007,resourcesSafe:true),remove==id else {fatalError("Observed exit did not allow exact owned removal")}
    _=try lifecycle!.observed(job:job.id,presence:.absent,now:1008,resourcesSafe:true)
    guard try journal!.jobs().first(where:{$0.id==job.id})?.state == .removed else {fatalError("Owned cleanup incomplete")}

    let (lost,late)=try reserve()
    guard case .create?=try lifecycle!.next(job:lost.id,now:1009,resourcesSafe:true) else {fatalError("Lost create intent missing")}
    // Release every reference before reopening: never two instances of one DB.
    lifecycle=nil;journal=nil
    journal=try Journal(directory:directory);lifecycle=SandboxLifecycle(journal:journal!)
    guard case .inspect?=try lifecycle!.next(job:lost.id,now:1010,resourcesSafe:true) else {fatalError("Recovery replayed uncertain create")}
    _=try lifecycle!.observed(job:lost.id,presence:.absent,now:1011,resourcesSafe:true)
    guard try journal!.jobs().first(where:{$0.id==lost.id})?.state != .removed else {fatalError("Sampled absence cleared uncertain create")}
    let lateID=String(repeating:"1",count:64)
    let latePresence=SandboxPresence.present(id:lateID,name:"/"+late.name,image:late.image,nonce:late.nonce,running:false)
    guard case .remove(_,let recovered)?=try lifecycle!.observed(job:lost.id,presence:latePresence,now:1012,resourcesSafe:true),recovered==lateID else {fatalError("Recovered late create started or escaped cleanup")}
    _=try lifecycle!.observed(job:lost.id,presence:.absent,now:1013,resourcesSafe:true)
    print("PASS: synthetic sentinel/forged identity refusal, lost-stop graceful retry and durable lost-create restart without replay or sampled-absence release")
}
