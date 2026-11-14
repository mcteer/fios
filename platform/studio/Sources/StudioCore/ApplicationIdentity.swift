import Foundation
import Security

enum ApplicationIdentity {
    // Trusted fixed profile inputs only. This checks identity without opening
    // an application, loading models or enabling certificate network access.
    static func verify(bundle:URL,executable:VerifiedExecutable,identifier:String,team:String?=nil,deadline:TimeInterval)throws {
        func live()throws {
            guard deadline.isFinite,deadline>ProcessInfo.processInfo.systemUptime,
                  deadline-ProcessInfo.processInfo.systemUptime<=10 else {throw ControlError.unauthorized}
        }
        try live()
        guard identifier.range(of:"^[A-Za-z0-9][A-Za-z0-9.-]{0,127}$",options:.regularExpression) != nil,
              team.map({$0.range(of:"^[A-Z0-9]{10}$",options:.regularExpression) != nil}) ?? true else {throw ControlError.unauthorized}
        try RootPolicyFile.verifyApplicationTree(path:bundle.path,deadline:deadline)
        let bytes=try RootPolicyFile.read(path:bundle.appendingPathComponent("Contents/Info.plist").path,maximum:65536)
        guard let info=try PropertyListSerialization.propertyList(from:bytes,format:nil) as? [String:Any],
              info["CFBundleIdentifier"] as? String==identifier,
              let name=info["CFBundleExecutable"] as? String,!name.isEmpty,!name.contains("/"),!name.contains("\0"),
              bundle.appendingPathComponent("Contents/MacOS/"+name).path==executable.path else {throw ControlError.unauthorized}
        try RootPolicyFile.verifyExecutable(executable)
        try live()
        var code:SecStaticCode?,requirement:SecRequirement?
        var text="identifier \""+identifier+"\" and anchor apple generic"
        if let team {text+=" and certificate leaf[subject.OU] = \""+team+"\""}
        guard SecStaticCodeCreateWithPath(bundle as CFURL,[],&code)==errSecSuccess,let code,
              SecRequirementCreateWithString(text as CFString,[],&requirement)==errSecSuccess,let requirement,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSCheckAllArchitectures|kSecCSStrictValidate|kSecCSCheckNestedCode|kSecCSSingleThreaded),requirement)==errSecSuccess else {throw ControlError.unauthorized}
        try live()
        try RootPolicyFile.verifyExecutable(executable)
        try live()
        // Valid only while the reviewed root-protected installation remains
        // unchanged. Root updates must stop/serialize against all consumers.
    }
}
