import Foundation
import Darwin

// Denial-only handover signal. Configuration presence is never evidence that
// Fios owns a process or may start/stop one. Do not read credentials or content.
enum FiosGUILaunchPolicy {
    enum Presence { case absent, present, unavailable }
    static let installedImage = "/Applications/MLX-Serve.app/Contents/MacOS/MLXCore"
    static let configurationPath = "/Library/Application Support/Fios/Studio/native-serving-launch.json"

    static func refusal() -> String? {
        refusal(image: currentImage(), policy: configurationPresence)
    }

    // The lookup is lazy: a development/copy image never reads installed data.
    static func refusal(image: String?, policy: () -> Presence) -> String? {
        guard let image, !image.isEmpty else {
            return "Could not verify this app's launch role. Server startup was refused."
        }
        guard image.utf8.elementsEqual(installedImage.utf8) else { return nil }
        switch policy() {
        case .absent: return nil
        case .present:
            return "Fios launch configuration is present. Server startup from this app is disabled."
        case .unavailable:
            return "Could not check Fios launch configuration. Server startup was refused."
        }
    }

    private static func currentImage() -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(bytes: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }

    private static func configurationPresence() -> Presence {
        var item = stat()
        if lstat(configurationPath, &item) == 0 { return .present }
        return errno == ENOENT ? .absent : .unavailable
    }
}
