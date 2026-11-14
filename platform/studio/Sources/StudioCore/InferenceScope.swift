import Foundation
import CryptoKit

// Durable dispatch identity, never prompts, credentials, URLs or proof of
// native terminality. Constructed by the trusted broker before issuing a pipe
// permission. Reconciliation must match the original bytes, not fresh health.
struct InferenceScope: Codable, Sendable {
    static let maximumBytes=16<<10
    let host:String
    let endpointHash:String
    let profileHash:String
    let managerEpoch:String
    let nativeEpoch:String
    let canonicalModel:String
    let nativeModel:String
    let sequence:UInt64
    let sampledAt:Int64

    var identity:[Data] {
        [host,endpointHash,profileHash,managerEpoch,nativeEpoch,canonicalModel,nativeModel].map {Data($0.utf8)}
    }
    func validate() throws {
        guard WireScalar.host(host),WireScalar.sha256(endpointHash),WireScalar.sha256(profileHash),
              WireScalar.uuid(managerEpoch),!nativeEpoch.isEmpty,nativeEpoch.utf8.count<=128,!nativeEpoch.contains("\0"),
              WireScalar.model(canonicalModel),WireScalar.model(nativeModel),sequence>0,sequence<=UInt64(Int64.max),
              (0...WireScalar.maximumTimestamp).contains(sampledAt) else {throw JournalError.invalid}
    }
    func encoded() throws -> Data {
        try validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(self)
        guard data.count<=Self.maximumBytes else {throw JournalError.invalid}
        return data
    }
    // Opaque request correlation only, not a capability or terminal proof.
    // Uses fields already durably recorded before dispatch; native epoch and
    // full profile/scope must still be independently matched on reconciliation.
    func nativeRequestCorrelationID(job:String,attempt:Int)throws->String {
        try validate()
        guard WireScalar.uuid(job),(0...3).contains(attempt) else {throw JournalError.invalid}
        var input=Data("fios-native-request-v1\0".utf8)
        for field in [job,String(attempt),managerEpoch,nativeModel,endpointHash] {
            let bytes=Data(field.utf8),length=UInt32(bytes.count)
            for shift in [24,16,8,0] {input.append(UInt8(truncatingIfNeeded:length >> shift))}
            input.append(bytes)
        }
        return SHA256.hash(data:input).map {String(format:"%02x",$0)}.joined()
    }
    static func decode(_ data:Data) throws -> Self {
        do {
            try StrictJSON.validate(data,maximum:Self.maximumBytes)
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  Set(object.keys)==Set(["host","endpointHash","profileHash","managerEpoch","nativeEpoch","canonicalModel","nativeModel","sequence","sampledAt"]),
                  let sequence=WireScalar.integer(object["sequence"],maximum:Int64.max),sequence>0,
                  WireScalar.integer(object["sampledAt"]) != nil else {throw JournalError.invalid}
            let value=try JSONDecoder().decode(Self.self,from:data)
            try value.validate();return value
        }catch{throw JournalError.invalid}
    }
}

struct InferenceScopeRecord: Sendable {
    let scope:InferenceScope
    let state:InferenceState
}

extension WorkerDispatchBinding {
    func inferenceScope() throws -> InferenceScope {
        guard host==nativeSnapshot.host else {throw JournalError.invalid}
        let scope=InferenceScope(host:host,endpointHash:nativeSnapshot.endpointHash,profileHash:profileHash,
            managerEpoch:managerEpoch,nativeEpoch:nativeSnapshot.nativeEpoch,canonicalModel:canonicalModel,
            nativeModel:nativeModel,sequence:nativeSnapshot.sequence,sampledAt:nativeSnapshot.sampledAt)
        try scope.validate();return scope
    }
}
