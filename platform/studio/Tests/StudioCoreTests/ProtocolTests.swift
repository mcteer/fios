import Foundation

private func mustReject(_ input: String) {
    do { _ = try ControlRequest.decode(Data(input.utf8)) } catch { return }
    preconditionFailure("Invalid control JSON accepted")
}
func runProtocolTests() throws {
    let id = UUID().uuidString.lowercased()
    let valid = "{\"version\":1,\"id\":\"\(id)\",\"operation\":\"status\",\"payload\":{}}"
    let request = try ControlRequest.decode(Data(valid.utf8))
    precondition(request.operation == .status)
    mustReject("{\"version\":1,\"version\":1,\"id\":\"\(id)\",\"operation\":\"status\",\"payload\":{}}")
    mustReject("{\"version\":1,\"id\":\"\(id)\",\"operation\":\"status\",\"payload\":{\"x\":1,\"\\u0078\":2}}")
    mustReject(valid + "{}")
    mustReject(valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":true"))
    mustReject(valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"))
    mustReject(valid.replacingOccurrences(of: "\"payload\":{}", with: "\"payload\":{},\"role\":\"operator\""))
    mustReject(valid.replacingOccurrences(of: "status", with: "shell"))
    mustReject(String(repeating: " ", count: 65_537))
    mustReject("[" + String(repeating: "[",count: 65) + "0" + String(repeating: "]",count: 65) + "]")
    precondition(ControlRole.observer.allows(.status))
    precondition(!ControlRole.observer.allows(.jobCreate))
    precondition(!ControlRole.task.allows(.serviceForce))
    precondition(!ControlRole.sandbox.allows(.jobCreate))
    print("PASS: strict control JSON, duplicate/escaped keys, frame bounds and role policy")
}
