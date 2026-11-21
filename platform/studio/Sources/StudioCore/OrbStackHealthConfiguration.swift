import Foundation
import CryptoKit

// Readonly installed-manager composition. Loading verifies existing opaque
// runtime/session policy; it launches nothing and grants no absence, session,
// credential, VM-capacity, task, native-admission or lifecycle permission.
enum OrbStackHealthConfiguration {
    static func load(directory:URL)throws->ServiceHealthCollector? {
        guard let runtime=try RuntimeEnrolledPolicy.load(directory:directory),
              let session=try SessionEnrolledPolicy.load(directory:directory,role:.manager) else {return nil}
        guard runtime.document.uid==session.document.uid,
              runtime.document.host==session.document.host,
              runtime.document.statePath==session.document.statePath,
              runtime.document.managerSHA256==session.document.managerSHA256,
              let application=session.applications[.orbstack] else {throw ServiceError.invalid}
        try RootPolicyFile.verifyExecutable(application)
        let inputs=["fios-orbstack-readonly-health-v1",runtime.policySHA256,session.document.reviewSHA256,
                    session.document.sessionSHA256,application.sha256]
        let digest=SHA256.hash(data:Data(inputs.joined(separator:"\0").utf8)).map {String(format:"%02x",$0)}.joined()
        let census=try ServiceProcessCensus(executable:application,relatedRoots:["/Applications/OrbStack.app"],
            reviewDigest:digest,uid:runtime.document.uid)
        return ServiceHealthCollector(census:census,probe:OrbStackHealthProbe(enrolled:runtime))
    }
}
