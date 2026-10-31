import Foundation
import StudioCore

if CommandLine.arguments.count != 3 || CommandLine.arguments[1] != "--state" || !CommandLine.arguments[2].hasPrefix("/") {
    FileHandle.standardError.write(Data("Usage: studio-supervisor --state ABSOLUTE_PRIVATE_DIRECTORY\n".utf8)); exit(2)
}
do {
    let executable=URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
    try SupervisorRuntime.run(directory:URL(fileURLWithPath:CommandLine.arguments[2]),
                              manager:executable.deletingLastPathComponent().appendingPathComponent("studio-manager"))
} catch {
    FileHandle.standardError.write(Data("studio-supervisor: startup or runtime failure\n".utf8)); exit(1)
}
