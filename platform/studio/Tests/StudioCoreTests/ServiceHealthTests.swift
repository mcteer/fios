import Foundation

func runServiceHealthTests() throws {
    func reply(_ status:String,_ body:String,_ extra:String="")->Data {
        Data("HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: application/json\r\n\(extra)\r\n\(body)".utf8)
    }
    guard ServiceHealthWire.decode(reply("200 OK","{\"status\":\"ok\"}")) == .healthy,
          ServiceHealthWire.decode(reply("503 Service Unavailable","{\"status\":\"loading\"}")) == .loading,
          ServiceHealthWire.decode(reply("401 Unauthorized","")) == .waitingCredentials,
          ServiceHealthWire.decode(reply("403 Forbidden","")) == .waitingCredentials else {fatalError("Service health status mapping broken")}
    for data in [reply("302 Found","", "Location: http://example.invalid/\r\n"),
                 reply("200 OK","{\"status\":\"ok\",\"status\":\"loading\"}"),
                 reply("200 OK","{\"status\":\"ok\"}","Transfer-Encoding: chunked\r\n"),
                 reply("200 OK","{\"status\":\"ok\"}","Content-Length: 15\r\n"),
                 reply("200 OK","{\"status\":\"ok\",\"model\":\"unreviewed\"}"),
                 reply("200 OK",String(repeating:"x",count:16385)),
                 reply("200 OK","{\"status\":\"ok\"}")+Data([0])] {
        guard ServiceHealthWire.decode(data) == .unavailable else {fatalError("Redirect/ambiguous/unbounded service health accepted")}
    }
    for port in [0,1,80,443,65536] {
        do {_ = try ServiceHealthProbe(port:port);fatalError("Unapproved health target accepted")}
        catch RuntimeError.invalid {}
    }
    let identity=ServiceIdentity(pid:2,start:1,sha256:String(repeating:"a",count:64))
    let review=String(repeating:"b",count:64)
    let sample=ServiceProcessSample(presence:.present(identity),sampledAt:1000,reviewDigest:review,uid:501,diagnostic:"verified_present")
    let collector=MLXServiceHealthCollector(presence:{sample},health:{.healthy},now:{1000},uptime:{1})
    guard let observed=collector.capture(sessionReady:true,credentialsReady:true),
          observed.identity==identity,observed.responding,observed.sampledAt==1000,
          observed.nativeIdle==nil,observed.runtimeUnmanaged==nil else {fatalError("Composed health lost original identity or invented idle")}
    let loading=MLXServiceHealthCollector(presence:{sample},health:{.loading},now:{1000},uptime:{1})
    guard let pending=loading.capture(sessionReady:true,credentialsReady:true),!pending.responding,
          pending.credentialsReady else {fatalError("Loading became readiness or lost known credentials")}
    let absent=ServiceProcessSample(presence:.absent,sampledAt:1000,reviewDigest:review,uid:501,diagnostic:"scoped_absence")
    let missing=MLXServiceHealthCollector(presence:{absent},health:{fatalError("Scoped absence invoked health")},now:{1000},uptime:{1})
    guard missing.capture(sessionReady:true,credentialsReady:true)==nil else {fatalError("Scoped absence became launch authority")}
    let auth=MLXServiceHealthCollector(presence:{sample},health:{.waitingCredentials},now:{1000},uptime:{1})
    guard let waiting=auth.capture(sessionReady:true,credentialsReady:true),!waiting.responding,!waiting.credentialsReady else {fatalError("Credential wait lost in composition")}
    guard collector.capture(sessionReady:true,credentialsReady:false)?.credentialsReady==false else {fatalError("Public health granted credentials")}
    var samples=[sample,ServiceProcessSample(presence:.present(ServiceIdentity(pid:3,start:2,sha256:identity.sha256)),sampledAt:1000,reviewDigest:review,uid:501,diagnostic:"verified_present")]
    let restarted=MLXServiceHealthCollector(presence:{samples.removeFirst()},health:{.healthy},now:{1000},uptime:{1})
    guard restarted.capture(sessionReady:true,credentialsReady:true)==nil,samples.isEmpty else {fatalError("Health crossed a process restart")}
    let earlier=ServiceProcessSample(presence:.present(identity),sampledAt:900,reviewDigest:review,uid:501,diagnostic:"verified_present")
    let old=MLXServiceHealthCollector(presence:{earlier},health:{.healthy},now:{1000},uptime:{1})
    guard old.capture(sessionReady:true,credentialsReady:true)?.sampledAt==900 else {fatalError("Collection refreshed original process sample")}
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    let background=AsyncServiceHealth(collector:MLXServiceHealthCollector(presence:{sample},health:{
        entered.signal()
        guard release.wait(timeout:.now()+2) == .success else {return .unavailable}
        return .healthy
    },now:{1000},uptime:{1}))
    background.begin(sessionReady:true,credentialsReady:true)
    guard entered.wait(timeout:.now()+1) == .success,background.poll()==nil else {fatalError("Background health did not retain its active slot")}
    background.begin(sessionReady:true,credentialsReady:false) // No second exchange.
    release.signal()
    let end=ProcessInfo.processInfo.systemUptime+2
    var collected:AsyncServiceHealth.Result?
    while collected==nil,ProcessInfo.processInfo.systemUptime<end {
        collected=background.poll();if collected==nil {Thread.sleep(forTimeInterval:0.005)}
    }
    guard collected?.observation?.responding==true,collected?.observation?.credentialsReady==true,
          background.poll()==nil,entered.wait(timeout:.now()+0.02) == .timedOut else {fatalError("Background health lost/replaced/duplicated its one result")}
    print("PASS: fixed no-inference health wire, loading/auth separation, redirects/ambiguous/oversized response and target refusal")
}
