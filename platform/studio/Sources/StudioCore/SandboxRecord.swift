import Foundation

struct SandboxRecord:Codable {
    let configuration:SandboxConfiguration
    var runtimeID:String?
    var createIssued=false
    var startIssued=false
    var removalProven=false
}
