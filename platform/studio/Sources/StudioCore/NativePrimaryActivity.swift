import Foundation

// Partial conservative ownership roots, including native load preparations.
// Not Codable/NativeSnapshot: no resident, queued/device or all-client claim.
struct NativePrimaryModelActivity:Sendable {
    let model:String
    let preparing:Int
    let active:Int
    let responding:Int
}
struct NativePrimaryActivity:Sendable {
    let instance:String
    let sampleSequence:UInt64
    let sampledAt:Int64?
    let uncertain:Bool
    let owners:Int
    let ingress:Int
    let preparing:Int
    let active:Int
    let responding:Int
    let models:[NativePrimaryModelActivity]
    func validate()throws {
        _=try NativeControlWire.instanceBytes(instance)
        let counts=[owners,ingress,preparing,active,responding]
        guard sampleSequence>0,sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              sampledAt.map({(1...ActivityPolicy.maximumTimestamp).contains($0)}) ?? true,
              counts.allSatisfy({(0...256).contains($0)}),owners==counts[1...4].reduce(0,+),models.count<=64 else {throw NativeControlError.invalid}
        var identities=Set<Data>(),totals=[0,0,0]
        for row in models {
            let phases=[row.preparing,row.active,row.responding]
            guard WireScalar.model(row.model),!row.model.contains("\0"),identities.insert(Data(row.model.utf8)).inserted,
                  phases.allSatisfy({(0...256).contains($0)}),phases.reduce(0,+)>0 else {throw NativeControlError.invalid}
            for index in 0..<3 {totals[index]+=phases[index]}
        }
        guard totals==[preparing,active,responding] else {throw NativeControlError.invalid}
    }
}
struct NativePrimaryActivitySample:Sendable {
    let peer:NativeControlPeer
    let receivedAt:Int64
    let activity:NativePrimaryActivity
}
enum NativePrimaryActivityWire {
    static let responseSize=66624,recordSize=1040
    static func request(instance:String)throws->Data {
        var output=Data(repeating:0,count:32)
        output.replaceSubrange(0..<4,with:Data("FIA9".utf8));output[4]=1
        output.replaceSubrange(8..<24,with:try NativeControlWire.instanceBytes(instance))
        return output
    }
    static func reply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativePrimaryActivity {
        guard data.count==responseSize,sequence<=UInt64(ActivityPolicy.maximumTimestamp) else {throw NativeControlError.invalid}
        _=try NativeControlWire.instanceBytes(instance)
        let bytes=Array(data)
        guard bytes[0..<4].elementsEqual("FIT9".utf8),bytes[4]==1,bytes[5]==0,bytes[6]==0,bytes[7]<=1,
              bytes[8..<24].map({String(format:"%02x",$0)}).joined()==instance else {throw NativeControlError.invalid}
        func integer(_ start:Int,_ count:Int)->UInt64 {bytes[start..<(start+count)].reduce(0) {($0<<8)|UInt64($1)}}
        let current=integer(24,8),stamp=integer(32,8),counts=stride(from:40,to:60,by:4).map {Int(integer($0,4))},modelCount=Int(integer(60,4))
        guard current>sequence,current<=UInt64(ActivityPolicy.maximumTimestamp),
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)),
              counts.allSatisfy({(0...256).contains($0)}),counts[0]==counts[1...4].reduce(0,+),modelCount<=64 else {throw NativeControlError.invalid}
        var identities=Set<Data>(),models=[NativePrimaryModelActivity](),totals=[0,0,0]
        for index in 0..<modelCount {
            let offset=64+index*recordSize,length=Int(integer(offset,2))
            guard (1...1024).contains(length),bytes[offset+2]==0,bytes[offset+3]==0,
                  bytes[(offset+16+length)..<(offset+recordSize)].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
            let encoded=Data(bytes[(offset+16)..<(offset+16+length)])
            guard let model=String(data:encoded,encoding:.utf8),WireScalar.model(model),!model.contains("\0"),identities.insert(encoded).inserted else {throw NativeControlError.invalid}
            let phases=(0..<3).map {Int(integer(offset+4+$0*4,4))}
            guard phases.allSatisfy({(0...256).contains($0)}),phases.reduce(0,+)>0 else {throw NativeControlError.invalid}
            for phase in 0..<3 {totals[phase]+=phases[phase]}
            models.append(NativePrimaryModelActivity(model:model,preparing:phases[0],active:phases[1],responding:phases[2]))
        }
        guard totals==Array(counts[2...4]),bytes[(64+modelCount*recordSize)..<responseSize].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        return NativePrimaryActivity(instance:instance,sampleSequence:current,sampledAt:stamp==UInt64.max ? nil:Int64(stamp),uncertain:bytes[7]==1,
            owners:counts[0],ingress:counts[1],preparing:counts[2],active:counts[3],responding:counts[4],models:models)
    }
}
