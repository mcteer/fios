import Foundation
import CryptoKit
import CoreFoundation

// Live lineage metadata only. Neither Codable nor a terminal/admission proof.
// Native rootSequence is a full-width token, never an interoperable JSON number.
struct NativeRequestLineage:Sendable {
    let instance:String
    let correlationID:String
    let sampleSequence:UInt64
    let rootSequence:UInt64
    let found:Bool
    let uncertain:Bool
    let references:UInt64
    let owners:Int
    let ingress:Int
    let preparing:Int
    let active:Int
    let responding:Int
    func validate()throws {
        _=try NativeControlWire.instanceBytes(instance)
        let counts=[owners,ingress,preparing,active,responding]
        guard WireScalar.sha256(correlationID),sampleSequence>0,sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              counts.allSatisfy({(0...256).contains($0)}),owners==counts[1...4].reduce(0,+),
              found ? (rootSequence>0 && owners>0 && references>=UInt64(owners) && references<=UInt64(owners)*UInt64(UInt32.max))
                    : (uncertain && rootSequence==0 && references==0 && owners==0) else {throw NativeControlError.invalid}
    }
}
struct NativeRequestLineageSample:Sendable {
    let peer:NativeControlPeer
    let sampledAt:Int64
    let lineage:NativeRequestLineage
}
enum NativeRequestLineageWire {
    private static func digestBytes(_ value:String)throws->[UInt8] {
        guard WireScalar.sha256(value) else {throw NativeControlError.invalid}
        let bytes=Array(value.utf8)
        func nibble(_ byte:UInt8)->UInt8 {byte<=57 ? byte-48:byte-87}
        return stride(from:0,to:64,by:2).map {nibble(bytes[$0])*16+nibble(bytes[$0+1])}
    }
    static func request(instance:String,correlationID:String)throws->Data {
        var data=Data(repeating:0,count:64)
        data.replaceSubrange(0..<4,with:Data("FIQ9".utf8));data[4]=1
        data.replaceSubrange(8..<24,with:try NativeControlWire.instanceBytes(instance))
        data.replaceSubrange(24..<56,with:try digestBytes(correlationID))
        return data
    }
    static func reply(_ input:Data,instance:String,correlationID:String)throws->NativeRequestLineage {
        _=try NativeControlWire.instanceBytes(instance);_=try digestBytes(correlationID)
        let bytes=Array(input) // Rebase slices before fixed-offset access.
        guard bytes.count==112,bytes.prefix(4).elementsEqual("FIP9".utf8),bytes[4]==1,bytes[5]==0,
              bytes[6]<=1,bytes[7]<=1,bytes[100..<112].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        let actualInstance=bytes[8..<24].map {String(format:"%02x",$0)}.joined()
        let actualID=bytes[24..<56].map {String(format:"%02x",$0)}.joined()
        guard actualInstance==instance,actualID==correlationID else {throw NativeControlError.unauthorized}
        func number(_ offset:Int,_ count:Int)->UInt64 {bytes[offset..<offset+count].reduce(0){($0<<8)|UInt64($1)}}
        let sequence=number(56,8),root=number(64,8),references=number(72,8)
        let counts=stride(from:80,to:100,by:4).map {Int(number($0,4))}
        let found=bytes[6]==1,uncertain=bytes[7]==1
        let value=NativeRequestLineage(instance:actualInstance,correlationID:actualID,sampleSequence:sequence,rootSequence:root,
            found:found,uncertain:uncertain,references:references,owners:counts[0],ingress:counts[1],preparing:counts[2],active:counts[3],responding:counts[4])
        try value.validate();return value
    }
}

enum NativeRequestLineageObservation {case unknown,live(NativeRequestLineage)}

// Serialized per-request readonly consumer. A journal checkpoint preserves
// original correlation and refusal/replay state, never a live observation or
// terminal receipt. Restart cannot refund/release inference ownership. There
// is no absent/complete state.
struct NativeRequestLineageConsumer:Sendable {
    private let peer:NativeControlPeer
    private let instance:String
    private let nativeModel:String
    let correlationID:String
    private var previousNow:Int64 = -1
    private var sampledAt:Int64 = -1
    private var sequence:UInt64=0
    private(set) var rootSequence:UInt64?
    private(set) var fenced=false
    private var handoffClosure:NativeHandoffClosureCheckpoint?
    init(scope:InferenceScope,job:String,attempt:Int,peer:NativeControlPeer,checkpoint:Data?=nil)throws {
        try scope.validate();_=try NativeControlWire.instanceBytes(scope.nativeEpoch)
        guard peer.pid>1,peer.start>0 else {throw NativeControlError.invalid}
        instance=scope.nativeEpoch;nativeModel=scope.nativeModel
        correlationID=try scope.nativeRequestCorrelationID(job:job,attempt:attempt)
        if let checkpoint {
            let saved=try NativeLineageCheckpoint.decode(checkpoint)
            guard saved.scopeSHA256 == (try Self.scopeDigest(scope)),saved.instance==instance,saved.correlationID==correlationID else {throw JournalError.conflict}
            let original=try saved.peer()
            self.peer=original
            previousNow=saved.previousNow;sampledAt=saved.sampledAt;sequence=saved.sequence;handoffClosure=saved.handoffClosure
            rootSequence=UInt64(saved.root).flatMap {$0==0 ? nil:$0}
            fenced=saved.fenced || original.pid != peer.pid || original.start != peer.start ||
                !original.executable.path.utf8.elementsEqual(peer.executable.path.utf8) || original.executable.sha256 != peer.executable.sha256
        } else {self.peer=peer}
    }
    static func validateCheckpoint(_ data:Data,scope:InferenceScope,job:String,attempt:Int)throws {
        let saved=try NativeLineageCheckpoint.decode(data)
        _=try NativeRequestLineageConsumer(scope:scope,job:job,attempt:attempt,peer:saved.peer(),checkpoint:data)
    }
    static func handoffClosureReceipt(_ data:Data,scope:InferenceScope,job:String,attempt:Int)throws->NativeHandoffClosureCheckpoint? {
        try validateCheckpoint(data,scope:scope,job:job,attempt:attempt)
        return try NativeLineageCheckpoint.decode(data).handoffClosure
    }
    private static func scopeDigest(_ scope:InferenceScope)throws->String {
        SHA256.hash(data:try scope.encoded()).map {String(format:"%02x",$0)}.joined()
    }
    func checkpoint(scope:InferenceScope)throws->Data {
        let saved=NativeLineageCheckpoint(version:handoffClosure == nil ? 1:2,scopeSHA256:try Self.scopeDigest(scope),instance:instance,correlationID:correlationID,
            pid:peer.pid,start:String(peer.start),path:peer.executable.path,sha256:peer.executable.sha256,root:String(rootSequence ?? 0),
            sequence:sequence,sampledAt:sampledAt,previousNow:previousNow,fenced:fenced,handoffClosure:handoffClosure)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(saved)
        _=try NativeLineageCheckpoint.decode(data)
        return data
    }
    // Authenticated original-root registration is durable identity metadata,
    // not a live lineage observation, worker permission or native completion.
    mutating func acceptRegistration(_ sample:NativeHandoffSample,now:Int64)->Bool {
        acceptRegistration(sample,observedAt:now,now:now)
    }
    mutating func acceptRegistration(_ verified:VerifiedNativeHandoffRegistration,now:Int64)->Bool {
        acceptRegistration(verified.sample,observedAt:verified.verifiedAt,now:now)
    }
    mutating func acceptRegistration(_ verified:VerifiedNativePreparationRegistration,now:Int64)->Bool {
        let sample=verified.sample,ack=sample.acknowledgement
        return acceptRootIdentity(suppliedPeer:sample.peer,suppliedInstance:ack.instance,suppliedCorrelation:ack.correlationID,
            suppliedModel:ack.model,root:ack.rootSequence,sampleSequence:ack.sampleSequence,capturedAt:sample.receivedAt,
            observedAt:verified.verifiedAt,now:now,validRegistration:ack.operation == .reserve && (1...5000).contains(ack.lifetimeMilliseconds))
    }
    private mutating func acceptRegistration(_ sample:NativeHandoffSample,observedAt:Int64,now:Int64)->Bool {
        let value=sample.result
        return acceptRootIdentity(suppliedPeer:sample.peer,suppliedInstance:value.instance,suppliedCorrelation:value.correlationID,
            suppliedModel:nil,root:value.rootSequence,sampleSequence:value.sampleSequence,capturedAt:sample.sampledAt,
            observedAt:observedAt,now:now,validRegistration:value.operation == .register && value.state == .pending && !value.uncertain)
    }
    private mutating func acceptRootIdentity(suppliedPeer:NativeControlPeer,suppliedInstance:String,suppliedCorrelation:String,
                                            suppliedModel:String?,root:UInt64,sampleSequence:UInt64,capturedAt:Int64,
                                            observedAt:Int64,now:Int64,validRegistration:Bool)->Bool {
        guard !fenced else {return false}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),now>=previousNow,
              (0...ActivityPolicy.maximumTimestamp).contains(observedAt),now>=observedAt else {fenced=true;return false}
        previousNow=now
        guard suppliedPeer.pid==peer.pid,suppliedPeer.start==peer.start,
              suppliedPeer.executable.path.utf8.elementsEqual(peer.executable.path.utf8),
              suppliedPeer.executable.sha256==peer.executable.sha256,
              suppliedInstance==instance,suppliedCorrelation==correlationID,
              suppliedModel.map({$0.utf8.elementsEqual(nativeModel.utf8)}) ?? true else {fenced=true;return false}
        guard validRegistration,root>0,
              sampleSequence>0,sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              (0...ActivityPolicy.maximumTimestamp).contains(capturedAt),
              (-1000...5000).contains(observedAt-capturedAt) else {return false}
        if let original=rootSequence,original != root {fenced=true;return false}
        // A newer readonly poll may already have persisted this same root.
        // Keep its sequence/clock rather than replaying the registration.
        if sampleSequence<=sequence {
            // A verified original registration remains identity even after a
            // newer unknown lookup; it cannot restore a live observation.
            rootSequence=root
            return true
        }
        guard capturedAt>=sampledAt,sampleSequence>sequence else {return false}
        rootSequence=root;sequence=sampleSequence;sampledAt=capturedAt
        return true
    }
    // A root must first have been observed live and checkpointed. This only
    // returns correlated local metadata; it does not resolve native ownership.
    mutating func acceptRetirement(_ sample:NativeRequestRetirementSample?,now:Int64)->NativeRequestRetirement? {
        guard !fenced else {return nil}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),now>=previousNow else {fenced=true;return nil}
        previousNow=now
        guard let sample else {return nil}
        let value=sample.retirement
        guard sample.peer.pid==peer.pid,sample.peer.start==peer.start,
              sample.peer.executable.path.utf8.elementsEqual(peer.executable.path.utf8),sample.peer.executable.sha256==peer.executable.sha256,
              value.instance==instance,value.correlationID==correlationID else {fenced=true;return nil}
        guard (try? value.validate()) != nil,
              (0...ActivityPolicy.maximumTimestamp).contains(sample.sampledAt),(-1000...5000).contains(now-sample.sampledAt),
              sample.sampledAt>=sampledAt,value.sampleSequence>sequence else {return nil}
        guard let original=rootSequence else {return nil}
        guard original==value.rootSequence else {fenced=true;return nil}
        sequence=value.sampleSequence;sampledAt=sample.sampledAt
        guard value.recorded,!value.uncertain else {return nil}
        return value
    }
    mutating func recordHandoffClosure(_ receipt:NativeHandoffClosureCheckpoint)throws {
        guard !fenced,rootSequence != nil,sequence>0,sampledAt>=0 else {throw JournalError.conflict}
        try receipt.validate();handoffClosure=receipt
    }
    // A cancelled original root can support only non-dispatch, and only when
    // paired with the separately produced fixed-worker no-POST evidence.
    mutating func acceptHandoffCancellation(_ sample:NativeHandoffSample?,now:Int64)->NativeHandoffResult? {
        guard !fenced else {return nil}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),now>=previousNow else {fenced=true;return nil}
        previousNow=now
        guard let sample else {return nil}
        let value=sample.result
        guard sample.peer.pid==peer.pid,sample.peer.start==peer.start,
              sample.peer.executable.path.utf8.elementsEqual(peer.executable.path.utf8),sample.peer.executable.sha256==peer.executable.sha256,
              value.instance==instance,value.correlationID==correlationID else {fenced=true;return nil}
        guard let original=rootSequence else {return nil}
        guard value.rootSequence==original,value.operation == .cancel else {fenced=true;return nil}
        guard value.sampleSequence>sequence,value.sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              (0...ActivityPolicy.maximumTimestamp).contains(sample.sampledAt),(-1000...5000).contains(now-sample.sampledAt),
              sample.sampledAt>=sampledAt else {return nil}
        sequence=value.sampleSequence;sampledAt=sample.sampledAt
        if value.state == .handedOff {fenced=true;return nil}
        guard value.state == .cancelled,!value.uncertain else {return nil}
        return value
    }
    mutating func accept(_ sample:NativeRequestLineageSample?,now:Int64)->NativeRequestLineageObservation {
        guard !fenced else {return .unknown}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now),now>=previousNow else {fenced=true;return .unknown}
        previousNow=now
        guard let sample else {return .unknown}
        let value=sample.lineage
        guard sample.peer.pid==peer.pid,sample.peer.start==peer.start,
              sample.peer.executable.path.utf8.elementsEqual(peer.executable.path.utf8),
              sample.peer.executable.sha256==peer.executable.sha256,
              value.instance==instance,value.correlationID==correlationID else {fenced=true;return .unknown}
        guard (try? value.validate()) != nil,
              (0...ActivityPolicy.maximumTimestamp).contains(sample.sampledAt),
              (-1000...5000).contains(now-sample.sampledAt),sample.sampledAt>=sampledAt,
              value.sampleSequence>sequence else {return .unknown}
        sequence=value.sampleSequence;sampledAt=sample.sampledAt
        if value.found {
            if let original=rootSequence,original != value.rootSequence {fenced=true;return .unknown}
            rootSequence=value.rootSequence
        }
        // Keep sequence/root across unknown gaps. A missing entry is never
        // permission to adopt a later request that reused the opaque ID.
        guard value.found,!value.uncertain else {return .unknown}
        return .live(value)
    }
}

// Durable correlation metadata only. Full-width native tokens use canonical
// decimal strings. Restoring these bytes never restores a live observation,
// clears uncertainty or grants native admission/terminal authority.
private struct NativeLineageCheckpoint:Codable {
    let version:Int
    let scopeSHA256:String
    let instance:String
    let correlationID:String
    let pid:Int32
    let start:String
    let path:String
    let sha256:String
    let root:String
    let sequence:UInt64
    let sampledAt:Int64
    let previousNow:Int64
    let fenced:Bool
    let handoffClosure:NativeHandoffClosureCheckpoint?
    func peer()throws->NativeControlPeer {
        guard pid>1,let token=UInt64(start),token>0,String(token)==start else {throw JournalError.invalid}
        return NativeControlPeer(pid:pid,start:token,executable:try VerifiedExecutable(path:path,sha256:sha256))
    }
    static func decode(_ data:Data)throws->Self {
        try StrictJSON.validate(data,maximum:16384)
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let version=WireScalar.integer(object["version"],maximum:2),[1,2].contains(version),
              Set(object.keys)==Set(["version","scopeSHA256","instance","correlationID","pid","start","path","sha256","root","sequence","sampledAt","previousNow","fenced"]+(version==2 ? ["handoffClosure"]:[])),WireScalar.integer(object["pid"],maximum:Int64(Int32.max)) != nil,
              WireScalar.integer(object["sequence"]) != nil,
              // The initial no-sample sentinel is private persistent metadata.
              ["sampledAt","previousNow"].allSatisfy({key in
                  if let n=object[key] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),["c","s","i","l","q"].contains(String(cString:n.objCType)),n.int64Value == -1 {return true}
                  return WireScalar.integer(object[key]) != nil
              }) else {throw JournalError.invalid}
        let value=try JSONDecoder().decode(Self.self,from:data)
        _=try value.peer();_=try NativeControlWire.instanceBytes(value.instance)
        if version==2 {
            guard let closure=value.handoffClosure,let raw=object["handoffClosure"] as? [String:Any],
                  Set(raw.keys)==Set(["version","localProducer","workerMetadataVersion","handoffVersion","launchNonce"]+(closure.grantSHA256 == nil ? []:["grantSHA256"])),
                  WireScalar.integer(raw["version"],maximum:1)==1,
                  WireScalar.integer(raw["workerMetadataVersion"],maximum:2)==2,
                  WireScalar.integer(raw["handoffVersion"],maximum:1)==1 else {throw JournalError.invalid}
            try closure.validate()
        }else if value.handoffClosure != nil {throw JournalError.invalid}
        guard WireScalar.sha256(value.scopeSHA256),WireScalar.sha256(value.correlationID),
              let root=UInt64(value.root),String(root)==value.root,
              (value.sequence==0 ? value.sampledAt == -1 && root==0:value.sampledAt>=0 && value.previousNow>=0),
              value.handoffClosure == nil || (root>0 && value.sequence>0) else {throw JournalError.invalid}
        return value
    }
}

// Version2 lineage checkpoints retain the accepted non-dispatch decision's
// local producer beside the original native peer/root/cancellation sequence.
// There is deliberately no native complete, device idle or all-client field.
struct NativeHandoffClosureCheckpoint:Codable,Sendable {
    let version:Int
    let localProducer:String
    let workerMetadataVersion:Int
    let handoffVersion:Int
    let launchNonce:String
    let grantSHA256:String?
    func validate()throws {
        guard version==1,workerMetadataVersion==2,handoffVersion==1,WireScalar.uuid(launchNonce),
              localProducer=="never_spawned" ? grantSHA256==nil : localProducer=="reaped_zero_post" && grantSHA256.map(WireScalar.sha256)==true else {throw JournalError.invalid}
    }
}
