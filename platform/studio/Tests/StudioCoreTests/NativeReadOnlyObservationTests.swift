import Foundation

private final class HeldUnavailableObservationSource:NativeReadOnlyClientSource,@unchecked Sendable {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    func resolve()throws->NativeReadOnlyClient {
        entered.signal()
        guard release.wait(timeout:.now()+2) == .success else {throw NativeControlError.deadline}
        throw NativeControlError.unavailable
    }
}

// Normal read/control sequencing metadata. No native process or model here.
func runNativeReadOnlyObservationTests()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let journal=try Journal(directory:directory)
    var coordinator=NativeMaintenanceCoordinator(journal:journal)
    let instance=String(repeating:"a",count:32)
    func reply(_ operation:NativeControlOperation,closed:Bool,source:String?=nil)->NativeIngressStatus {
        NativeIngressStatus(operation:operation,status:.ok,instance:source ?? instance,pauseSequence:closed ? 1:0,
            owners:0,ingress:0,preparing:0,active:0,responding:0,modelIdentities:0,closed:closed,uncertain:false)
    }
    let observation=coordinator.beginObservation()!
    guard observation.operation == .observe,coordinator.beginObservation()==nil,
          try journal.recordedDesired(service:.mlx)==nil else {throw NativeControlError.invalid}
    guard try coordinator.receive(id:observation.id,value:reply(.observe,closed:false))==nil,
          coordinator.phase == .unknown,try journal.recordedDesired(service:.mlx)==nil else {throw NativeControlError.invalid}
    // An explicit intent arriving during a read takes over that observation;
    // it is not dropped or sent on a second connection.
    let reading=coordinator.beginObservation()!
    try coordinator.setDesired(.maintenance,role:.operator)
    guard try coordinator.beginReconciliation()==nil else {throw NativeControlError.invalid}
    let pause=try coordinator.receive(id:reading.id,value:reply(.observe,closed:false))!
    guard pause.operation == .pause,pause.instance==instance else {throw NativeControlError.invalid}
    guard try coordinator.receive(id:pause.id,value:reply(.pause,closed:true))==nil,
          coordinator.phase == .admissionsClosed else {throw NativeControlError.invalid}
    // Exercise the ordinary asynchronous read-only worker without a socket.
    let source=HeldUnavailableObservationSource(),queue=AsyncNativeControl(observerSource:source)
    defer {source.release.signal()}
    do {try queue.submit(pause);fatalError("Read-only resolver accepted a control operation")}
    catch NativeControlError.unauthorized {}
    try queue.submit(observation)
    guard source.entered.wait(timeout:.now()+1) == .success,queue.poll()==nil else {throw NativeControlError.deadline}
    do {try queue.submit(observation);fatalError("Pending observation allowed duplicate worker")}
    catch RuntimeError.capacity {}
    source.release.signal()
    func awaitResult()throws->NativeControlResult {
        let deadline=ProcessInfo.processInfo.systemUptime+1
        while ProcessInfo.processInfo.systemUptime<deadline {
            if let result=queue.poll() {return result}
            Thread.sleep(forTimeInterval:0.005)
        }
        throw NativeControlError.deadline
    }
    let result=try awaitResult()
    guard result.id==observation.id,case .failure(.unavailable)=result.value,
          result.primaryActivity==nil,result.backendFences==nil,queue.poll()==nil else {
        fatalError("Unavailable read-only source minted a frame or replayed its result")
    }
    let closedRead=coordinator.beginObservation()!
    try queue.submit(closedRead)
    guard source.entered.wait(timeout:.now()+1) == .success else {throw NativeControlError.deadline}
    source.release.signal()
    let nextResult=try awaitResult()
    guard nextResult.id==closedRead.id,case .failure(.unavailable)=nextResult.value,queue.poll()==nil else {
        fatalError("Drained read-only source failed to return capacity or replayed an old reply")
    }
    guard try coordinator.receive(id:closedRead.id,value:reply(.observe,closed:true))==nil,
          coordinator.phase == .admissionsClosed else {throw NativeControlError.invalid}
    try coordinator.setDesired(.running,role:.operator)
    let reconcile=try coordinator.beginReconciliation()!
    let resume=try coordinator.receive(id:reconcile.id,value:reply(.observe,closed:true))!
    guard resume.operation == .resume,resume.sequence==1 else {throw NativeControlError.invalid}
    guard try coordinator.receive(id:resume.id,value:reply(.resume,closed:false))==nil else {throw NativeControlError.invalid}
    // A new source instance is observed without replaying prior control intent.
    let newSource=coordinator.beginObservation()!
    guard try coordinator.receive(id:newSource.id,value:reply(.observe,closed:true,source:String(repeating:"b",count:32)))==nil,
          coordinator.phase == .unknown,!coordinator.lifecycleApplied,
          try journal.recordedDesired(service:.mlx) == .running else {throw NativeControlError.invalid}
    let interrupted=coordinator.beginObservation()!
    coordinator.failed(id:newSource.id)
    guard coordinator.beginObservation()==nil else {fatalError("Stale completion released an unrelated observation")}
    coordinator.failed(id:interrupted.id)
    guard coordinator.phase == .unknown,!coordinator.lifecycleApplied,
          try journal.recordedDesired(service:.mlx) == .running,
          let afterGap=coordinator.beginObservation(),afterGap.id != interrupted.id,
          afterGap.operation == .observe,afterGap.instance==nil,afterGap.sequence==0 else {
        fatalError("Observation failure rewrote intent or replayed a native change")
    }
    var diagnostics=NativeControlDiagnostics(configured:true),sample=reply(.observe,closed:false)
    sample.nativeSampleSequence=1;sample.nativeSampledAt=900
    diagnostics.completed(sample,receivedAt:1000)
    diagnostics.begin(retainingObservation:true)
    let retained=diagnostics.summary(now:1200)
    guard retained["received_at"] as? Int64==1000,retained["source_sampled_at"] as? Int64==900,
          diagnostics.summary(now:6200)["state"] as? String=="stale" else {throw NativeControlError.invalid}
    print("PASS: read-only observations preserve intent, share one pending slot and yield to explicit control without replay")
}
