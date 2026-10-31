import Foundation

func runAsyncArtifactTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let service=AsyncArtifacts(store:try ArtifactStore(directory:directory,availableBytes:{100<<30}))
    let owner=String(repeating:"a",count:64),job=UUID().uuidString.lowercased(),request=UUID().uuidString.lowercased(),data=Data(repeating:65,count:65536)
    try service.publish(request:request,job:job,owner:owner,data:data,now:1000)
    do {try service.publish(request:request,job:job,owner:owner,data:data,now:1000);fatalError("Pending publication replayed")} catch ArtifactServiceFailure.capacity {}
    func wait(_ count:Int)throws->[ArtifactServiceResult] {
        var values:[ArtifactServiceResult]=[]
        let deadline=ProcessInfo.processInfo.systemUptime+3
        while values.count<count && ProcessInfo.processInfo.systemUptime<deadline {values+=service.drain();Thread.sleep(forTimeInterval:0.005)}
        guard values.count==count else {throw RuntimeError.deadline};return values
    }
    let stored=try wait(1)
    guard case .success(.published(let id))=stored[0].result else {fatalError("Async publication failed")}
    try service.download(request:UUID().uuidString.lowercased(),id:id,owner:owner,now:1001)
    try service.download(request:UUID().uuidString.lowercased(),id:id,owner:String(repeating:"b",count:64),now:1001)
    do {try service.download(request:UUID().uuidString.lowercased(),id:id,owner:owner,now:1001);fatalError("Artifact service exceeded two total slots")} catch ArtifactServiceFailure.capacity {}
    var bytes=Data(),denied=false
    for result in try wait(2) {
        switch result.result {
        case .failure(.unauthorized):denied=true
        case .success(.download(var stream)):
            var ended=false
            while !ended {
                switch try stream.next(now:1002) {
                case .begin:break
                case .chunk(_,let encoded):bytes.append(Data(base64Encoded:encoded)!)
                case .end:ended=true
                }
            }
        default:fatalError("Unexpected artifact result")
        }
    }
    guard denied,bytes==data else {fatalError("Async artifact owner/integrity boundary failed")}
    print("PASS: off-loop durable export publication/owner-verified finite download, duplicate in-flight refusal and two total I/O/result slots")
}
