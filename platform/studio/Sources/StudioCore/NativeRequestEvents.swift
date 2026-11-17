import Foundation

protocol NativeRequestEventsReading:NativeLineageReading {
    var observesRequestEvents:Bool {get}
    func requestEvents(instance:String,correlationID:String,rootSequence:UInt64)throws->NativeRequestEventsSample
}
extension NativeControlClient:NativeRequestEventsReading {}

// Observed SDK callbacks for one original root. These values are neither a
// whole-request completion proof nor authority to release inference ownership.
struct NativeRequestEventCounts:Sendable {
    let sequence:UInt64
    let originated:UInt64
    let retired:UInt64
    let pending:UInt64
    let historyRetained:Bool
    let uncertain:Bool
    func validate()throws {
        let maximum=UInt64(ActivityPolicy.maximumTimestamp)
        guard sequence>0,sequence<=maximum,originated>0,originated<=maximum,
              retired<=originated,pending<=originated,retired+pending==originated else {throw NativeControlError.invalid}
    }
}

struct NativeRequestEvents:Sendable {
    let instance:String
    let correlationID:String
    let rootSequence:UInt64
    let sampleSequence:UInt64
    let sampledAt:Int64
    let identityKnown:Bool
    let sdkInitialized:Bool
    let sourceUncertain:Bool
    let host:NativeRequestEventCounts?
    let metal:NativeRequestEventCounts?
    func validate()throws {
        _=try NativeControlWire.instanceBytes(instance)
        guard WireScalar.sha256(correlationID),rootSequence>0,sampleSequence>0,
              sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),(1...ActivityPolicy.maximumTimestamp).contains(sampledAt),
              (identityKnown && sdkInitialized) || (host==nil && metal==nil) else {throw NativeControlError.invalid}
        try host?.validate();try metal?.validate()
    }
}

struct NativeRequestEventsSample:Sendable {
    let peer:NativeControlPeer
    let requestedAt:Int64
    let receivedAt:Int64
    let events:NativeRequestEvents
}

enum NativeRequestEventsWire {
    static let responseSize=160
    static func request(instance:String,correlationID:String,rootSequence:UInt64)throws->Data {
        var data=try NativeRequestRetirementWire.request(instance:instance,correlationID:correlationID,rootSequence:rootSequence)
        data.replaceSubrange(0..<4,with:Data("FIO9".utf8))
        return data
    }
    static func reply(_ data:Data,instance:String,correlationID:String,rootSequence:UInt64)throws->NativeRequestEvents {
        let expected=try request(instance:instance,correlationID:correlationID,rootSequence:rootSequence),bytes=Array(data)
        guard bytes.count==responseSize,bytes[0..<4].elementsEqual("FIV9".utf8),bytes[4]==1,bytes[5]==0,
              bytes[6]<=7,bytes[7]==0 else {throw NativeControlError.invalid}
        guard bytes[8..<64].elementsEqual(expected[8..<64]) else {throw NativeControlError.unauthorized}
        func number(_ offset:Int)->UInt64 {bytes[offset..<offset+8].reduce(0){($0<<8)|UInt64($1)}}
        func counts(_ offset:Int)throws->NativeRequestEventCounts? {
            let flags=bytes[offset]
            guard flags<=7,bytes[offset+1..<offset+8].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
            if flags&1==0 {
                guard flags==0,bytes[offset+8..<offset+40].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
                return nil
            }
            let value=NativeRequestEventCounts(sequence:number(offset+8),originated:number(offset+16),retired:number(offset+24),pending:number(offset+32),historyRetained:flags&2 != 0,uncertain:flags&4 != 0)
            try value.validate();return value
        }
        guard number(72)<=UInt64(ActivityPolicy.maximumTimestamp) else {throw NativeControlError.invalid}
        let value=NativeRequestEvents(instance:instance,correlationID:correlationID,rootSequence:rootSequence,sampleSequence:number(64),sampledAt:Int64(number(72)),
            identityKnown:bytes[6]&4 != 0,sdkInitialized:bytes[6]&1 != 0,sourceUncertain:bytes[6]&2 != 0,host:try counts(80),metal:try counts(120))
        try value.validate();return value
    }
}
