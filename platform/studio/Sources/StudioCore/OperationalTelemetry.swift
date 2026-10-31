import Foundation

public enum OperationalEvent:String,Codable,Sendable {
    case started,stopped,desiredChanged,rejected,revoked,reconciled
}

// Operational values only. The SDK adapter lives in a separate package target.
public protocol PlatformTelemetry:Sendable {
    var instrumentation:String {get}
    func event(_ event:OperationalEvent)
    func resources(_ sample:ResourceSample)
    func gpu(_ sample:GPUSample?,sampledAt:Int64?)
    func workload(_ sample:PlatformWorkloadSample?)
    func services(_ samples:[PlatformServiceSample])
    func nativeIngress(_ sample:PlatformNativeIngressSample?)
}

public struct NoopPlatformTelemetry:PlatformTelemetry {
    public init() {}
    public var instrumentation:String {"none"}
    public func event(_ event:OperationalEvent) {}
    public func resources(_ sample:ResourceSample) {}
    public func gpu(_ sample:GPUSample?,sampledAt:Int64?) {}
    public func workload(_ sample:PlatformWorkloadSample?) {}
}

public struct PlatformServiceSample:Sendable {
    public let service:ManagedService
    public let desired:ServiceDesired
    public let observed:ServiceObserved
    public let sampledAt:Int64
    public init(service:ManagedService,desired:ServiceDesired,observed:ServiceObserved,sampledAt:Int64) {
        self.service=service;self.desired=desired;self.observed=observed;self.sampledAt=sampledAt
    }
}

public extension PlatformTelemetry {
    func services(_ samples:[PlatformServiceSample]) {}
    func nativeIngress(_ sample:PlatformNativeIngressSample?) {}
}

enum ServiceTelemetry {
    static func sample(journal:Journal,observations:ServiceObservationCache?,recovery:ServiceRecoveryController?,now:Int64)->[PlatformServiceSample] {
        do {
            return try ManagedService.allCases.map {service in
                guard let desired=ServiceDesired(rawValue:try journal.desired(service:service.rawValue)) else {throw ServiceError.invalid}
                let observed=ServiceStatusPolicy.observed(desired:desired,observation:observations?.snapshot(for:service),
                    launchPending:recovery?.isPending(service) ?? false,now:now)
                return PlatformServiceSample(service:service,desired:desired,observed:observed,sampledAt:now)
            }
        }catch {return []}
    }
}

// Partial request-tracker diagnostics, never a NativeSnapshot or idle proof.
public struct PlatformNativeIngressSample:Sendable {
    public let receivedAt:Int64
    public let sourceSampledAt:Int64?
    public let owners:Int
    public let ingress:Int
    public let preparing:Int
    public let active:Int
    public let responding:Int
    public let modelIdentities:Int
    public let closed:Bool
    public let trackerUncertain:Bool
}
