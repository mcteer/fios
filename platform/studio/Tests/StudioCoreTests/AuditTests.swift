import Foundation

func runAuditTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let audit=try AuditLog(directory:directory,maximumBytes:512)
    for index in 0..<100 { try audit.record(.started,now:Int64(index),count:index) }
    let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
    let size=try files.reduce(0) { try $0 + Data(contentsOf:$1).count }
    guard size<=512 else { fatalError("Audit exceeded quota") }
    do { try audit.record(.started,now:100,job:"prompt must not become a log identifier");fatalError("Arbitrary audit text accepted") } catch AuditError.invalid {}
    try audit.record(.stopped,now:8*86400000)
    guard try FileManager.default.contentsOfDirectory(atPath:directory.path).count==1 else { fatalError("Expired audit not removed") }
    do { try audit.record(.started,now:0);fatalError("Clock rollback accepted") } catch AuditError.invalid {}
    print("PASS: typed content-free audit, finite bytes/age and clock rollback rejection")
}
