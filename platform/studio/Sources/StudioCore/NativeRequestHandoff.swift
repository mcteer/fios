import Foundation

enum NativeHandoffOperation:UInt8,Sendable {case register,cancel}
enum NativeHandoffState:UInt8,Sendable {case pending,handedOff,cancelled,unknown}
// Native handoff metadata only. This is not Codable, a NativeSnapshot, a model
// reservation or permission to resolve an independent native inference claim.
struct NativeHandoffResult:Sendable {
    let operation:NativeHandoffOperation
    let instance:String
    let correlationID:String
    let rootSequence:UInt64
    let sampleSequence:UInt64
    let state:NativeHandoffState
    let uncertain:Bool
}
struct NativeHandoffSample:Sendable {
    let peer:NativeControlPeer
    let sampledAt:Int64
    let result:NativeHandoffResult
}
enum NativeHandoffWire {
    static func request(operation:NativeHandoffOperation,instance:String,correlationID:String,rootSequence:UInt64=0)throws->Data {
        guard operation == .register ? rootSequence==0 : rootSequence>0 else {throw NativeControlError.invalid}
        var bytes=try NativeRequestLineageWire.request(instance:instance,correlationID:correlationID)
        bytes.replaceSubrange(0..<4,with:Data("FIJ9".utf8));bytes[5]=operation.rawValue
        for index in 0..<8 {bytes[56+index]=UInt8(truncatingIfNeeded:rootSequence >> ((7-index)*8))}
        return bytes
    }
    static func reply(_ input:Data,operation:NativeHandoffOperation,instance:String,correlationID:String,rootSequence:UInt64=0)throws->NativeHandoffResult {
        let expected=try request(operation:operation,instance:instance,correlationID:correlationID,rootSequence:rootSequence),bytes=Array(input)
        guard bytes.count==88,bytes.prefix(4).elementsEqual("FIK9".utf8),bytes[4]==1,bytes[5]==0,
              let state=NativeHandoffState(rawValue:bytes[6]),bytes[7]<=1,bytes[72]==operation.rawValue,
              bytes[73..<88].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        guard bytes[8..<56].elementsEqual(expected[8..<56]),operation == .register || bytes[64..<72].elementsEqual(expected[56..<64]) else {throw NativeControlError.unauthorized}
        func number(_ at:Int)->UInt64 {bytes[at..<at+8].reduce(0){($0<<8)|UInt64($1)}}
        let sequence=number(56),root=number(64),uncertain=bytes[7]==1
        guard sequence>0,sequence<=UInt64(ActivityPolicy.maximumTimestamp),root>0,
              !uncertain || state == .unknown,
              operation == .register ? [.pending,.unknown].contains(state) : [.handedOff,.cancelled,.unknown].contains(state) else {throw NativeControlError.invalid}
        return NativeHandoffResult(operation:operation,instance:instance,correlationID:correlationID,rootSequence:root,
            sampleSequence:sequence,state:state,uncertain:uncertain)
    }
}
