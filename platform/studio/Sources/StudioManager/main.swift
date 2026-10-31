import Foundation
import StudioCore
#if canImport(StudioObservability)
import StudioObservability
#endif

if CommandLine.arguments.count != 3 || CommandLine.arguments[1] != "--state" || !CommandLine.arguments[2].hasPrefix("/") {
    FileHandle.standardError.write(Data("Usage: studio-manager --state ABSOLUTE_PRIVATE_DIRECTORY\n".utf8))
    exit(2)
}
do {
    #if canImport(StudioObservability)
    try ManagerRuntime.run(directory:URL(fileURLWithPath:CommandLine.arguments[2]),telemetry:StudioOpenTelemetry())
    #else
    try ManagerRuntime.run(directory:URL(fileURLWithPath:CommandLine.arguments[2]))
    #endif
} catch {
    // No raw exceptions, paths, configuration, workload data or credentials.
    FileHandle.standardError.write(Data("studio-manager: startup or runtime failure\n".utf8))
    exit(1)
}
