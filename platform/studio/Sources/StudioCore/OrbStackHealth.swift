import Foundation

// Metadata liveness only, not Docker compatibility, VM capacity, absence,
// unmanaged-work coverage or a reservation against stopping/starting the VM.
enum OrbStackHealthWire {
    static func available(_ result:CommandResult)->Bool {
        guard result.status==0,(1...128).contains(result.output.count),
              (try? StrictJSON.validate(result.output,maximum:128)) != nil,
              let value=(try? JSONSerialization.jsonObject(with:result.output,options:[.fragmentsAllowed])) as? String else {return false}
        let parts=value.split(separator:".",omittingEmptySubsequences:false)
        return parts.count==2 && parts.allSatisfy {part in
            !part.isEmpty && part.utf8.count<=3 && part.utf8.allSatisfy({(48...57).contains($0)})
        }
    }
}

struct OrbStackHealthProbe:Sendable {
    private let running:any VMRunningReading
    private let expectedCLIHash:String
    private let version:@Sendable ()throws->CommandResult
    init(enrolled:RuntimeEnrolledPolicy) {
        running=enrolled.running;expectedCLIHash=enrolled.document.orbctlSHA256
        let runtime=enrolled.runtime
        version={try runtime.command(["version","--format","{{json .Server.APIVersion}}"],timeout:2)}
    }
    // Code-only isolated adapters; no IPC fields select a command or socket.
    init(running:any VMRunningReading,expectedCLIHash:String,version:@escaping @Sendable ()throws->CommandResult) {
        self.running=running;self.expectedCLIHash=expectedCLIHash;self.version=version
    }
    func probe()->ServiceHealthState {
        let began=ProcessInfo.processInfo.systemUptime,stamp=HostResources.nowMilliseconds()
        do {
            let proof=try running.capture()
            // Require a new status read, rather than refreshing an older
            // running observation under this collection's newer timestamp.
            guard proof.sampledAt>=stamp else {return .unavailable}
            try proof.validate(expectedSHA256:expectedCLIHash,now:HostResources.nowMilliseconds())
            guard OrbStackHealthWire.available(try version()) else {return .unavailable}
            let completed=HostResources.nowMilliseconds(),elapsed=ProcessInfo.processInfo.systemUptime-began
            try proof.validate(expectedSHA256:expectedCLIHash,now:completed)
            guard completed>=stamp,elapsed>=0,elapsed<=4 else {return .unavailable}
            return .healthy
        } catch {return .unavailable}
    }
}
