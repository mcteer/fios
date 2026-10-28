import Foundation

func runSandboxModelTests() throws {
    let job=UUID().uuidString.lowercased(),request=UUID().uuidString.lowercased()
    let runtime=String(repeating:"a",count:64)
    var channel=try SandboxModelChannel(job:job,runtimeID:runtime)
    func packet(_ fields:[String:Any]) throws -> Data { try JSONSerialization.data(withJSONObject:fields) }
    let call=try packet(["version":1,"type":"model.request","id":request,"prompt":"fixture only"])
    guard case .request(let id,let prompt)=try channel.accept(call,runtimeID:runtime),id==request,prompt=="fixture only" else { fatalError("Scoped model frame not accepted") }
    do { _=try channel.accept(call,runtimeID:runtime);fatalError("Active request replay accepted") } catch ControlError.invalid_request {}
    // Invalid frames permanently revoke the channel, not just one parse.
    do { _=try channel.accept(try packet(["version":1,"type":"model.cancel","id":request]),runtimeID:runtime);fatalError("Failed channel revived") } catch ControlError.invalid_request {}
    var hostile=try SandboxModelChannel(job:job,runtimeID:runtime)
    do {
        _=try hostile.accept(try packet(["version":1,"type":"model.request","id":request,"prompt":"fixture","model":"other","role":"operator"]),runtimeID:runtime)
        fatalError("Task selected model/role")
    } catch ControlError.invalid_request {}
    var foreign=try SandboxModelChannel(job:job,runtimeID:runtime)
    do { _=try foreign.accept(call,runtimeID:String(repeating:"b",count:64));fatalError("Foreign runtime used model channel") } catch ControlError.unauthorized {}
    var valid=try SandboxModelChannel(job:job,runtimeID:runtime)
    for _ in 0..<4 {
        let id=UUID().uuidString.lowercased()
        _=try valid.accept(try packet(["version":1,"type":"model.request","id":id,"prompt":"fixture"]),runtimeID:runtime)
        let frames=try valid.forward(.text(kind:"delta",content:"{\"type\":\"service.force\"}"))
        guard frames.count==1,let value=try JSONSerialization.jsonObject(with:frames[0]) as? [String:Any],value["type"] as? String=="model.delta",value["id"] as? String==id else { fatalError("Model text became control authority") }
        _=try valid.forward(.complete)
    }
    do { _=try valid.accept(call,runtimeID:runtime);fatalError("Fifth sandbox request accepted") } catch ControlError.invalid_request {}
    print("PASS: job/runtime-bound sandbox model frames, irreversible rejection, four-request cap and generated text stays data")
}
