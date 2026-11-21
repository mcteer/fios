import Foundation

// Distinct CPU lease closure receipt. No conversion to inference terminality,
// native capacity, coverage, or an ordinary withdrawal acknowledgement.
struct NativePristinePreparationClosure:Sendable {
    let instance:String
    let correlationID:String
    let model:String
    let rootSequence:UInt64
    let sampleSequence:UInt64
    let sourceSampledAt:Int64?
}
struct NativePristinePreparationSample:Sendable {
    let peer:NativeControlPeer
    let requestedAt:Int64
    let receivedAt:Int64
    let closure:NativePristinePreparationClosure
}
enum NativePristinePreparationWire {
    static let requestSize=1104,responseSize=88
    static func request(instance:String,correlationID:String,model:String,rootSequence:UInt64)throws->Data {
        var data=try NativePreparationWire.request(operation:.withdraw,instance:instance,correlationID:correlationID,
            model:model,rootSequence:rootSequence,lifetimeMilliseconds:0)
        data[4]=2;data[5]=3
        return data
    }
    static func reply(_ input:Data,instance:String,correlationID:String,model:String,rootSequence:UInt64,
                      after sequence:UInt64)throws->NativePristinePreparationClosure {
        let expected=try request(instance:instance,correlationID:correlationID,model:model,rootSequence:rootSequence)
        let bytes=Array(input)
        guard sequence<=UInt64(ActivityPolicy.maximumTimestamp),bytes.count==responseSize,
              bytes.prefix(4).elementsEqual("FIV9".utf8),bytes[4]==2,bytes[5]==0,bytes[6]==3,bytes[7]==0,
              bytes[80..<88].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        guard bytes[8..<24].elementsEqual(expected[8..<24]),bytes[48..<80].elementsEqual(expected[24..<56])
            else {throw NativeControlError.unauthorized}
        func number(_ offset:Int)->UInt64 {bytes[offset..<offset+8].reduce(0){($0<<8)|UInt64($1)}}
        let sample=number(24),stamp=number(32),root=number(40)
        guard sample>sequence,sample<=UInt64(ActivityPolicy.maximumTimestamp),root==rootSequence,
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)) else {throw NativeControlError.invalid}
        return NativePristinePreparationClosure(instance:instance,correlationID:correlationID,model:model,
            rootSequence:root,sampleSequence:sample,sourceSampledAt:stamp==UInt64.max ? nil:Int64(stamp))
    }
}
