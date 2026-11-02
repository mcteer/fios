import Foundation
import Darwin

func runNativeHealthConfigurationTests()throws {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    let collector=ServiceHealthCollector(presence:{ServiceProcessSample(presence:.unknown,sampledAt:nil,reviewDigest:String(repeating:"a",count:64),uid:geteuid(),diagnostic:"fixture")},health:{.unavailable},now:{1000},uptime:{1})
    let configuration=AsyncNativeHealthConfiguration {
        guard !Thread.isMainThread else {throw ServiceError.invalid}
        entered.signal()
        guard release.wait(timeout:.now()+2) == .success else {throw ServiceError.invalid}
        return collector
    }
    guard entered.wait(timeout:.now()+1) == .success,configuration.isPending,configuration.poll()==nil else {fatalError("Native metadata load blocked or lost its original worker")}
    release.signal()
    let deadline=ProcessInfo.processInfo.systemUptime+2
    while configuration.isPending && ProcessInfo.processInfo.systemUptime<deadline {Thread.sleep(forTimeInterval:0.005)}
    guard !configuration.isPending,case .configured(let value)=configuration.poll(),value===collector,configuration.poll()==nil else {fatalError("Native metadata completion was duplicated or replaced")}
    for malformed in [false,true] {
        let load=AsyncNativeHealthConfiguration {
            if malformed {_=try NativeServingLaunchDocument(Data("{}".utf8))}
            return nil
        }
        let end=ProcessInfo.processInfo.systemUptime+2
        while load.isPending && ProcessInfo.processInfo.systemUptime<end {Thread.sleep(forTimeInterval:0.005)}
        guard !load.isPending,let result=load.poll() else {fatalError("Native metadata outcome missing")}
        switch result {
        case .unconfigured:guard !malformed else {fatalError("Malformed metadata became unconfigured")}
        case .unavailable:guard malformed else {fatalError("Absent metadata became an error")}
        case .configured:fatalError("Absent metadata created a native collector")
        }
        guard load.poll()==nil else {fatalError("Native metadata load retried or retained a duplicate completion")}
    }
}
