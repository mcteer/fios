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
}

public struct NoopPlatformTelemetry:PlatformTelemetry {
    public init() {}
    public var instrumentation:String {"none"}
    public func event(_ event:OperationalEvent) {}
    public func resources(_ sample:ResourceSample) {}
    public func gpu(_ sample:GPUSample?,sampledAt:Int64?) {}
    public func workload(_ sample:PlatformWorkloadSample?) {}
}
