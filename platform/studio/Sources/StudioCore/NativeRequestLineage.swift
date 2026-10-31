import Foundation

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

// Serialized per-request readonly consumer. This volatile view is NOT a
// durable receipt or journal reconciliation issuer; restart cannot refund or
// release original inference ownership. There is no absent/complete state.
struct NativeRequestLineageConsumer:Sendable {
    private let peer:NativeControlPeer
    private let instance:String
    let correlationID:String
    private var previousNow:Int64 = -1
    private var sampledAt:Int64 = -1
    private var sequence:UInt64=0
    private(set) var rootSequence:UInt64?
    private(set) var fenced=false
    init(scope:InferenceScope,job:String,attempt:Int,peer:NativeControlPeer)throws {
        try scope.validate();_=try NativeControlWire.instanceBytes(scope.nativeEpoch)
        guard peer.pid>1,peer.start>0 else {throw NativeControlError.invalid}
        self.peer=peer;instance=scope.nativeEpoch
        correlationID=try scope.nativeRequestCorrelationID(job:job,attempt:attempt)
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
