import Foundation

private final class OrbStackHealthFixture:VMRunningReading,@unchecked Sendable {
    private let lock=NSLock()
    private var running=true,daemon=true
    private var reads=0,versions=0
    private var lag:Int64=0
    let hash=String(repeating:"a",count:64)
    func configure(running:Bool,daemon:Bool,lag:Int64=0) {lock.lock();defer {lock.unlock()};self.running=running;self.daemon=daemon;self.lag=lag}
    var counts:(Int,Int) {lock.lock();defer {lock.unlock()};return (reads,versions)}
    func capture()throws->VMRunningProof {
        lock.lock();defer {lock.unlock()};reads+=1
        guard running else {throw RuntimeError.launch}
        return VMRunningProof(sourceSHA256:hash,sampledAt:HostResources.nowMilliseconds()-lag)
    }
    func version()->CommandResult {
        lock.lock();defer {lock.unlock()};versions+=1
        return CommandResult(status:daemon ? 0:1,output:daemon ? Data("\"1.53\"\n".utf8):Data())
    }
    func probe()->OrbStackHealthProbe {OrbStackHealthProbe(running:self,expectedCLIHash:hash,version:{self.version()})}
}

func runOrbStackHealthTests()throws {
    let fixture=OrbStackHealthFixture(),probe=fixture.probe()
    guard probe.probe() == .healthy,fixture.counts == (1,1) else {fatalError("Running daemon health sequence failed")}
    fixture.configure(running:false,daemon:true)
    guard probe.probe() == .unavailable,fixture.counts == (2,1) else {fatalError("Stopped VM still queried the daemon")}
    fixture.configure(running:true,daemon:false)
    guard probe.probe() == .unavailable,fixture.counts == (3,2) else {fatalError("Unavailable daemon became ready")}
    fixture.configure(running:true,daemon:true)
    guard probe.probe() == .healthy,fixture.counts == (4,3) else {fatalError("Fresh daemon observation did not recover status")}
    fixture.configure(running:true,daemon:true,lag:1000)
    guard probe.probe() == .unavailable,fixture.counts == (5,3) else {fatalError("Cached running observation was refreshed or reached daemon")}
    let present=ServiceProcessSample(presence:.present(ServiceIdentity(pid:42,start:1,sha256:fixture.hash)),
        sampledAt:1000,reviewDigest:fixture.hash,uid:501,diagnostic:"fixture_present")
    let collector=ServiceHealthCollector(presence:{present},health:{.healthy},now:{1000},uptime:{1})
    guard let observed=collector.capture(sessionReady:true,credentialsReady:true),observed.responding,
          observed.nativeIdle==nil,observed.runtimeUnmanaged==nil else {fatalError("Service health invented native/runtime work coverage")}
    print("PASS: running prerequisite before daemon metadata, unavailable/recovered daemon status, shared present-process collector and no lifecycle/work authority")
}
