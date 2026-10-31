import Foundation

func runSandboxLifecycleTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let journal=try Journal(directory:directory),controller=SandboxLifecycle(journal:journal)
    let job=try DurableJob(id:UUID().uuidString.lowercased(),idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:1000)
    let config=try SandboxConfiguration(job:job.id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1)
    _=try journal.reserveSandbox(job:job,configuration:config)
    guard case .create?=try controller.next(job:job.id,now:1001,resourcesSafe:true) else { fatalError("Initial create missing") }
    guard case .inspect?=try controller.next(job:job.id,now:1002,resourcesSafe:true) else { fatalError("Create replayed before response") }
    _=try controller.observed(job:job.id,presence:.absent,now:1003,resourcesSafe:true)
    guard try journal.jobs().first?.state == .creating else { fatalError("Unknown create released on sampled absence") }
    let id=String(repeating:"e",count:64)
    try controller.created(job:job.id,runtimeID:id)
    let created=SandboxPresence.present(id:id,name:"/"+config.name,image:config.image,nonce:config.nonce,running:false)
    guard case .start?=try controller.observed(job:job.id,presence:created,now:1004,resourcesSafe:true) else { fatalError("Owned sandbox not started") }
    let running=SandboxPresence.present(id:id,name:"/"+config.name,image:config.image,nonce:config.nonce,running:true)
    _=try controller.observed(job:job.id,presence:running,now:1005,resourcesSafe:true)
    guard try journal.jobs().first?.state == .running else { fatalError("Running state missing") }
    // A backwards clock revokes immediately, even before the last renewal.
    guard case .stop?=try controller.observed(job:job.id,presence:running,now:1004,resourcesSafe:true) else { fatalError("Clock rollback left sandbox active") }
    guard case .remove?=try controller.observed(job:job.id,presence:created,now:1006,resourcesSafe:true) else { fatalError("Cleanup removal missing") }
    _=try controller.observed(job:job.id,presence:.absent,now:1007,resourcesSafe:true)
    guard try journal.jobs().first?.state == .removed else { fatalError("Proven cleanup reservation retained") }
    guard try controller.next(job:job.id,now:1008,resourcesSafe:true)==nil else { fatalError("Removed job revived") }
    print("PASS: sandbox command/result lifecycle, no create/start replay, uncertain absence fencing, clock revocation and proof-gated cleanup")
}
