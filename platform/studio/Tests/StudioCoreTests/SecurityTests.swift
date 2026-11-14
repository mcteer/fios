import Foundation

func runSecurityTests() throws {
    let management:[ControlOperation]=[.serviceDesired,.serviceDrain,.serviceForce,.reconcile]
    let ownership:[ControlOperation]=[.jobCreate,.jobStatus,.jobRenew,.jobCancel,.artifactRead]
    for operation in management {
        guard !ControlRole.task.allows(operation),!ControlRole.sandbox.allows(operation),!ControlRole.observer.allows(operation),ControlRole.operator.allows(operation) else {fatalError("Management role boundary widened")}
    }
    for operation in ownership {
        guard ControlRole.task.allows(operation),!ControlRole.sandbox.allows(operation),!ControlRole.observer.allows(operation),!ControlRole.operator.allows(operation) else {fatalError("Owner role boundary widened")}
    }
    let id=UUID().uuidString.lowercased()
    let base:[String:Any]=["version":1,"id":id,"operation":"status","payload":[:]]
    for key in ["role","endpoint","argv","command","shell","host","model","token"] {
        var injected=base;injected[key]="untrusted"
        do {_=try ControlRequest.decode(JSONSerialization.data(withJSONObject:injected));fatalError("Authority envelope field accepted")} catch ControlError.invalid_request {}
    }
    for byte in 0...255 {
        let data=Data(repeating:UInt8(byte),count:512)
        var accepted=false
        do {_=try ControlRequest.decode(data);accepted=true} catch {}
        guard !accepted else {fatalError("Non-envelope binary frame accepted")}
    }
    print("PASS: exhaustive management/owner role matrix, authority-field injection and bounded hostile binary control frames; no native side effects")
}
