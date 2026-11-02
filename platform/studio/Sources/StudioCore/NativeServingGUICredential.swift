import Foundation
import CoreFoundation
import Darwin

enum NativeServingCredentialError:Error {case unavailable,unsupported}

// Fixed existing MLX GUI setting only. No caller-selected domain/path, writes,
// generated/default key, manager access or public startup wiring. The protected
// supervisor factory selects this source explicitly during reviewed handover.
enum NativeServingGUICredential {
    static let applicationDomain="com.dalcu.mlx-core"
    static let settingsKey="serverOptions"
    static func read(configuration:NativeServingReviewedConfiguration)throws->String {
        guard configuration.role == .supervisor,configuration.document.usesArgumentCredential else {
            throw NativeServingCredentialError.unsupported
        }
        guard geteuid()>0,getuid()==geteuid(),configuration.document.uid==geteuid(),
              configuration.document.host==ProcessInfo.processInfo.hostName else {throw NativeServingCredentialError.unavailable}
        guard let value=CFPreferencesCopyValue(settingsKey as CFString,applicationDomain as CFString,
                                               kCFPreferencesCurrentUser,kCFPreferencesAnyHost),
              let data=value as? Data else {throw NativeServingCredentialError.unavailable}
        return try decode(data)
    }
    // The pinned GUI stores ServerOptions as JSON Data, then trims only the
    // key's surrounding whitespace/newlines before emitting --api-key VALUE.
    // Other settings are read-only opaque data; they cannot select launch argv.
    static func decode(_ data:Data)throws->String {
        do {
            try StrictJSON.validate(data,maximum:32768)
            guard let settings=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let value=settings["apiKey"] as? String else {throw NativeServingCredentialError.unavailable}
            let key=value.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !key.isEmpty,key.utf8.count<=4096,!key.contains("\0") else {throw NativeServingCredentialError.unavailable}
            return key
        } catch {throw NativeServingCredentialError.unavailable}
    }
}
