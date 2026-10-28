import Foundation
import CoreFoundation

public enum ControlError: String, Error, Codable { case invalid_request, unauthorized, unsupported_version, internal_error, busy }
public enum ControlOperation: String, Sendable {
    case status, activity, resources, reconcile
    case jobCreate = "job.create", jobStatus = "job.status", jobRenew = "job.renew", jobCancel = "job.cancel"
    case artifactRead = "artifact.read", modelRequest = "model.request"
    case serviceDesired = "service.desired", serviceDrain = "service.drain", serviceForce = "service.force"
}
public enum ControlRole: Sendable {
    case observer, task, `operator`, sandbox
    public func allows(_ operation: ControlOperation) -> Bool {
        switch self {
        case .observer: return [.status,.activity,.resources].contains(operation)
        case .task: return [.status,.jobCreate,.jobStatus,.jobRenew,.jobCancel,.artifactRead,.modelRequest].contains(operation)
        case .operator: return [.status,.activity,.resources,.serviceDesired,.serviceDrain,.serviceForce,.reconcile].contains(operation)
        case .sandbox: return operation == .modelRequest
        }
    }
}

// Fixed data-model vocabularies; Codable rejects unknown/coerced enum values.
public enum ManagedService:String,Codable,CaseIterable,Sendable {case mlx,orbstack}
public enum ServiceDesired:String,Codable,CaseIterable,Sendable {case running,maintenance,stopped}
public enum ServiceObserved:String,Codable,CaseIterable,Sendable {case starting,ready,waiting_session,waiting_credentials,stopped,degraded,unknown}
public enum ReservationState:String,Codable,CaseIterable,Sendable {case reserved,committed,releasing,released}
public enum NativeCoverage:String,Codable,CaseIterable,Sendable {case all_clients,unknown,unsupported}
public enum NativeActivityState:String,Codable,CaseIterable,Sendable {case idle,preparing,queued,active,unknown}
public enum InferenceState:String,Codable,CaseIterable,Sendable {case reserved,dispatched,uncertain,complete,not_sent}
public enum JobKind:String,Codable,CaseIterable,Sendable {case sandbox,model_only}
public enum JobState:String,Codable,CaseIterable,Sendable {case reserved,creating,running,revoking,stopping,removing,removed,reconciling}
public enum MemoryPressure:String,Codable,CaseIterable,Sendable {case normal,warning,critical,unknown}
public enum ThermalState:String,Codable,CaseIterable,Sendable {case nominal,fair,serious,critical,unknown}
public enum WireLimits {
    public static let controlJSON=65_536
    public static let nativeRawObservation=1_048_576
    public static let hostBytes=128
    public static let modelBytes=1024
}

// Shared wire scalars. Never normalize identifiers, coerce booleans/floats to
// integers, or let Swift's canonical-Unicode String equality alias model IDs.
public enum WireScalar {
    public static let maximumTimestamp:Int64 = 9_007_199_254_740_991
    public static func integer(_ value:Any?,maximum:Int64=maximumTimestamp)->Int64? {
        guard maximum>=0,let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["d","f"].contains(String(cString:number.objCType)),number.int64Value>=0,
              number.int64Value<=maximum else {return nil}
        return number.int64Value
    }
    public static func uuid(_ value:String)->Bool {UUID(uuidString:value)?.uuidString.lowercased()==value}
    public static func host(_ value:String)->Bool {
        !value.isEmpty && value.utf8.count<=WireLimits.hostBytes && value.utf8.allSatisfy {$0>32 && $0<127}
    }
    public static func model(_ value:String)->Bool {!value.isEmpty && value.utf8.count<=WireLimits.modelBytes}
    public static func sha256(_ value:String)->Bool {
        value.utf8.count==64 && value.utf8.allSatisfy {(48...57).contains($0)||(97...102).contains($0)}
    }
    public static func exactModel(_ a:String?,_ b:String?)->Bool {
        guard let a,let b,model(a),model(b) else {return false}
        return a.utf8.elementsEqual(b.utf8)
    }
}

public struct ControlRequest {
    public let id: String
    public let operation: ControlOperation
    public let payload: [String: Any]

    public static func decode(_ data: Data) throws -> ControlRequest {
        try StrictJSON.validate(data, maximum: WireLimits.controlJSON)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["version","id","operation","payload"]),
              WireScalar.integer(object["version"]) == 1,
              let id = object["id"] as? String, WireScalar.uuid(id),
              let name = object["operation"] as? String, let operation = ControlOperation(rawValue: name),
              let payload = object["payload"] as? [String: Any]
        else { throw ControlError.invalid_request }
        return ControlRequest(id: id, operation: operation, payload: payload)
    }
}

// Foundation's JSON decoder accepts duplicate object keys. Validate the entire
// bounded grammar first, comparing decoded keys (including Unicode escapes).
public enum StrictJSON {
    public static func validate(_ data: Data, maximum: Int) throws {
        guard !data.isEmpty, data.count <= maximum else { throw ControlError.invalid_request }
        var parser = Parser(bytes: Array(data))
        try parser.value(depth: 0)
        parser.space()
        guard parser.index == parser.bytes.count else { throw ControlError.invalid_request }
    }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        mutating func space() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ expected: UInt8) throws {
            space(); guard index < bytes.count, bytes[index] == expected else { throw ControlError.invalid_request }; index += 1
        }
        mutating func string() throws -> String {
            space(); let start = index; try take(34)
            while index < bytes.count {
                let b = bytes[index]; index += 1
                if b == 34 {
                    let slice = Data(bytes[start..<index])
                    guard let string = try JSONSerialization.jsonObject(with: slice, options: [.fragmentsAllowed]) as? String else { throw ControlError.invalid_request }
                    return string
                }
                if b < 32 { throw ControlError.invalid_request }
                if b == 92 {
                    guard index < bytes.count else { throw ControlError.invalid_request }
                    index += 1 // Full escape/UTF-8 validity checked by JSONSerialization.
                }
            }
            throw ControlError.invalid_request
        }
        mutating func value(depth: Int) throws {
            guard depth <= 32 else { throw ControlError.invalid_request }
            space(); guard index < bytes.count else { throw ControlError.invalid_request }
            switch bytes[index] {
            case 123:
                index += 1; space(); var keys = Set<String>()
                if index < bytes.count && bytes[index] == 125 { index += 1; return }
                while true {
                    let key = try string()
                    guard keys.insert(key).inserted else { throw ControlError.invalid_request }
                    try take(58); try value(depth: depth + 1); space()
                    guard index < bytes.count else { throw ControlError.invalid_request }
                    if bytes[index] == 125 { index += 1; return }
                    try take(44)
                }
            case 91:
                index += 1; space()
                if index < bytes.count && bytes[index] == 93 { index += 1; return }
                while true {
                    try value(depth: depth + 1); space()
                    guard index < bytes.count else { throw ControlError.invalid_request }
                    if bytes[index] == 93 { index += 1; return }
                    try take(44)
                }
            case 34: _ = try string()
            default:
                let start = index
                while index < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw ControlError.invalid_request }
                _ = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed])
            }
        }
    }
}
