import Foundation
import Darwin

// Trusted code-only resolver. Resolve once per observation operation so all
// frames use one authenticated peer; there is no retry or substitution.
protocol NativeReadOnlyClientSource:Sendable {
    func resolve()throws->NativeReadOnlyClient
}

final class NativeServingObservationSource:NativeReadOnlyClientSource,@unchecked Sendable {
    private let configuration:NativeServingReviewedConfiguration
    private let census:ServiceProcessCensus
    private let socket:String
    private let home:String
    private init(configuration:NativeServingReviewedConfiguration,census:ServiceProcessCensus,home:String) {
        self.configuration=configuration;self.census=census;self.home=home
        socket=home+"/.fios-native-control/control.sock"
    }
    static func load(directory:URL)throws->NativeServingObservationSource? {
        guard let configuration=try NativeServingReviewedConfiguration.load(directory:directory) else {return nil}
        guard case .reviewedFiosNative=configuration.processProfile.artifact,
              let home=configuration.document.observationHome else {return nil}
        return NativeServingObservationSource(configuration:configuration,census:try configuration.processProfile.makeCensus(),home:home)
    }
    func resolve()throws->NativeReadOnlyClient {
        let started=ProcessInfo.processInfo.systemUptime
        // A changed installation requires its stopped/reviewed upgrade path;
        // this retained source never silently adopts a replacement policy.
        _=try RootPolicyFile.read(path:NativeServingReviewedConfiguration.policyPath,maximum:32768,expectedSHA256:configuration.policySHA256)
        try RootPolicyFile.verifyExecutable(configuration.processProfile.server)
        var entry=stat()
        guard lstat(home,&entry)==0,entry.st_mode&S_IFMT==S_IFDIR,
              entry.st_uid==configuration.document.uid,entry.st_mode&0o7022==0 else {throw NativeControlError.unavailable}
        let sample=census.capture(),now=HostResources.nowMilliseconds()
        let elapsed=ProcessInfo.processInfo.systemUptime-started
        guard case .present(let identity)=sample.presence,let sampledAt=sample.sampledAt,
              identity.valid,identity.sha256==configuration.processProfile.server.sha256,
              (0...ActivityPolicy.maximumTimestamp).contains(now),(0...ActivityPolicy.maximumTimestamp).contains(sampledAt),
              (0...2000).contains(now-sampledAt),elapsed.isFinite,(0..<2).contains(elapsed) else {throw NativeControlError.unavailable}
        let peer=NativeControlPeer(pid:identity.pid,start:identity.start,executable:configuration.processProfile.server)
        return NativeReadOnlyClient(NativeControlClient(path:socket,peer:peer,version:3,
            observeBackendFences:true,observePrimaryActivity:true,observeSDKBackground:true))
    }
}

enum NativeObservationConfigurationOutcome:Sendable {
    case configured(NativeServingObservationSource),unconfigured,unavailable
}
// One finite metadata load off the heartbeat loop, never a process/model launch.
final class AsyncNativeObservationConfiguration:@unchecked Sendable {
    private let lock=NSLock()
    private var result:NativeObservationConfigurationOutcome?
    init(directory:URL) {
        Thread.detachNewThread { [self] in
            let value:NativeObservationConfigurationOutcome
            do {
                if let source=try NativeServingObservationSource.load(directory:directory) {value = .configured(source)}
                else {value = .unconfigured}
            } catch {value = .unavailable}
            lock.lock();result=value;lock.unlock()
        }
    }
    func poll()->NativeObservationConfigurationOutcome? {
        lock.lock();defer {lock.unlock()};let value=result;result=nil;return value
    }
}
