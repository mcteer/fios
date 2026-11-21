import Foundation

enum NativePreparationOperation:UInt8,Sendable {case reserve=1,withdraw=2}
// An acknowledgement of CPU bookkeeping only. Not Codable, a dispatch grant,
// NativeSnapshot, native capacity, all-client coverage or terminality evidence.
struct NativePreparationAcknowledgement:Sendable {
    let operation:NativePreparationOperation
    let instance:String
    let correlationID:String
    let model:String
    let rootSequence:UInt64
    let sampleSequence:UInt64
    let sourceSampledAt:Int64?
    let lifetimeMilliseconds:UInt32
}
struct NativePreparationSample:Sendable {
    let peer:NativeControlPeer
    let requestedAt:Int64
    let receivedAt:Int64
    let acknowledgement:NativePreparationAcknowledgement
}
enum NativePreparationWire {
    static let requestSize=1104,responseSize=88
    static func request(operation:NativePreparationOperation,instance:String,correlationID:String,model:String,
                        rootSequence:UInt64=0,lifetimeMilliseconds:UInt32=5000)throws->Data {
        guard WireScalar.model(model),!model.contains("\0"),model.utf8.count<=1024,
              correlationID.utf8.contains(where:{$0 != 48}),
              operation == .reserve ? rootSequence==0 && (1...5000).contains(lifetimeMilliseconds)
                                   : rootSequence>0 && lifetimeMilliseconds==0 else {throw NativeControlError.invalid}
        let identity=try NativeRequestLineageWire.request(instance:instance,correlationID:correlationID)
        var data=Data(repeating:0,count:requestSize)
        data.replaceSubrange(0..<4,with:Data("FIP9".utf8));data[4]=1;data[5]=operation.rawValue
        data.replaceSubrange(8..<56,with:identity[8..<56])
        for index in 0..<8 {data[56+index]=UInt8(truncatingIfNeeded:rootSequence >> ((7-index)*8))}
        let modelBytes=Array(model.utf8),length=UInt16(modelBytes.count)
        data[64]=UInt8(truncatingIfNeeded:length>>8);data[65]=UInt8(truncatingIfNeeded:length)
        for index in 0..<4 {data[68+index]=UInt8(truncatingIfNeeded:lifetimeMilliseconds >> ((3-index)*8))}
        data.replaceSubrange(80..<80+modelBytes.count,with:modelBytes)
        return data
    }
    static func reply(_ input:Data,operation:NativePreparationOperation,instance:String,correlationID:String,model:String,
                      rootSequence:UInt64=0,lifetimeMilliseconds:UInt32=5000,after sequence:UInt64=0)throws->NativePreparationAcknowledgement {
        let expected=try request(operation:operation,instance:instance,correlationID:correlationID,model:model,
                                 rootSequence:rootSequence,lifetimeMilliseconds:lifetimeMilliseconds),bytes=Array(input)
        guard sequence<=UInt64(ActivityPolicy.maximumTimestamp),bytes.count==responseSize,
              bytes.prefix(4).elementsEqual("FIV9".utf8),bytes[4]==1,bytes[5]==0,bytes[6]==operation.rawValue,bytes[7]==0,
              bytes[84..<88].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        guard bytes[8..<24].elementsEqual(expected[8..<24]),bytes[48..<80].elementsEqual(expected[24..<56]),
              bytes[80..<84].elementsEqual(expected[68..<72]) else {throw NativeControlError.unauthorized}
        func number(_ offset:Int)->UInt64 {bytes[offset..<offset+8].reduce(0){($0<<8)|UInt64($1)}}
        let sample=number(24),stamp=number(32),root=number(40)
        guard sample>sequence,sample<=UInt64(ActivityPolicy.maximumTimestamp),root>0,
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)),
              operation == .reserve || root==rootSequence else {throw NativeControlError.invalid}
        return NativePreparationAcknowledgement(operation:operation,instance:instance,correlationID:correlationID,model:model,
            rootSequence:root,sampleSequence:sample,sourceSampledAt:stamp==UInt64.max ? nil:Int64(stamp),lifetimeMilliseconds:lifetimeMilliseconds)
    }
}
