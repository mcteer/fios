import Foundation

// Local reference release only. This is deliberately not a NativeProof and has
// no operation that resolves a journal claim or grants native admission.
struct NativeRequestRetirement:Sendable {
    let instance:String
    let correlationID:String
    let sampleSequence:UInt64
    let rootSequence:UInt64
    let retirementSequence:UInt64
    let recorded:Bool
    let uncertain:Bool
    func validate()throws {
        _=try NativeControlWire.instanceBytes(instance)
        guard WireScalar.sha256(correlationID),sampleSequence>0,sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),rootSequence>0,
              recorded ? retirementSequence>0 : (uncertain && retirementSequence==0) else {throw NativeControlError.invalid}
    }
}
struct NativeRequestRetirementSample:Sendable {
    let peer:NativeControlPeer
    let sampledAt:Int64
    let retirement:NativeRequestRetirement
}
enum NativeRequestRetirementWire {
    static func request(instance:String,correlationID:String,rootSequence:UInt64)throws->Data {
        guard rootSequence>0 else {throw NativeControlError.invalid}
        var bytes=try NativeRequestLineageWire.request(instance:instance,correlationID:correlationID)
        bytes.replaceSubrange(0..<4,with:Data("FIE9".utf8))
        for i in 0..<8 {bytes[56+i]=UInt8(truncatingIfNeeded:rootSequence >> ((7-i)*8))}
        return bytes
    }
    static func reply(_ input:Data,instance:String,correlationID:String,rootSequence:UInt64)throws->NativeRequestRetirement {
        let expected=try request(instance:instance,correlationID:correlationID,rootSequence:rootSequence),bytes=Array(input)
        guard bytes.count==88,bytes.prefix(4).elementsEqual("FIZ9".utf8),bytes[4]==1,bytes[5]==0,
              bytes[6]<=1,bytes[7]<=1,bytes[80..<88].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        guard bytes[8..<56].elementsEqual(expected[8..<56]),bytes[64..<72].elementsEqual(expected[56..<64]) else {throw NativeControlError.unauthorized}
        func number(_ at:Int)->UInt64 {bytes[at..<at+8].reduce(0){($0<<8)|UInt64($1)}}
        let record=NativeRequestRetirement(instance:instance,correlationID:correlationID,sampleSequence:number(56),rootSequence:rootSequence,
            retirementSequence:number(72),recorded:bytes[6]==1,uncertain:bytes[7]==1)
        try record.validate();return record
    }
}
