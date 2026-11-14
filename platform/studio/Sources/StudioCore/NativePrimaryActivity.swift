import Foundation

// Partial conservative ownership roots. No residency, device terminality or
// all-client coverage follows from either authenticated wire version.
struct NativePrimaryModelActivity:Sendable {
    let model:String
    let preparing:Int
    let queued:Int
    let active:Int
    let responding:Int
}
struct NativePrimaryActivity:Sendable {
    let phaseVersion:Int
    let instance:String
    let sampleSequence:UInt64
    let sampledAt:Int64?
    let uncertain:Bool
    let owners:Int
    let ingress:Int
    let preparing:Int
    let queued:Int
    let active:Int
    let responding:Int
    let models:[NativePrimaryModelActivity]
    func validate()throws {
        _=try NativeControlWire.instanceBytes(instance)
        let counts=[owners,ingress,preparing,queued,active,responding]
        guard [1,2].contains(phaseVersion),phaseVersion==2 || (queued==0 && models.allSatisfy({$0.queued==0})),
              sampleSequence>0,sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              sampledAt.map({(1...ActivityPolicy.maximumTimestamp).contains($0)}) ?? true,
              counts.allSatisfy({(0...256).contains($0)}),owners==counts[1...5].reduce(0,+),models.count<=64 else {throw NativeControlError.invalid}
        var identities=Set<Data>(),totals=[0,0,0,0]
        for row in models {
            let phases=[row.preparing,row.queued,row.active,row.responding]
            guard WireScalar.model(row.model),!row.model.contains("\0"),identities.insert(Data(row.model.utf8)).inserted,
                  phases.allSatisfy({(0...256).contains($0)}),phases.reduce(0,+)>0 else {throw NativeControlError.invalid}
            for index in 0..<4 {totals[index]+=phases[index]}
        }
        guard totals==[preparing,queued,active,responding] else {throw NativeControlError.invalid}
    }
}
struct NativePrimaryActivitySample:Sendable {
    let peer:NativeControlPeer
    let receivedAt:Int64
    let activity:NativePrimaryActivity
}
enum NativePrimaryActivityWire {
    static let responseSize=66624,recordSize=1040
    static let queuedResponseSize=66888,queuedRecordSize=1044
    static func request(instance:String)throws->Data {try request(instance:instance,version:1)}
    static func queuedRequest(instance:String)throws->Data {try request(instance:instance,version:2)}
    private static func request(instance:String,version:UInt8)throws->Data {
        var output=Data(repeating:0,count:32)
        output.replaceSubrange(0..<4,with:Data("FIA9".utf8));output[4]=version
        output.replaceSubrange(8..<24,with:try NativeControlWire.instanceBytes(instance))
        return output
    }
    static func reply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativePrimaryActivity {
        try reply(data,instance:instance,after:sequence,version:1)
    }
    static func queuedReply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativePrimaryActivity {
        try reply(data,instance:instance,after:sequence,version:2)
    }
    private static func reply(_ data:Data,instance:String,after sequence:UInt64,version:UInt8)throws->NativePrimaryActivity {
        let size=version==2 ? queuedResponseSize:responseSize,header=version==2 ? 72:64
        let record=version==2 ? queuedRecordSize:recordSize,identityOffset=version==2 ? 20:16
        guard data.count==size,sequence<=UInt64(ActivityPolicy.maximumTimestamp) else {throw NativeControlError.invalid}
        _=try NativeControlWire.instanceBytes(instance)
        let bytes=Array(data)
        guard bytes[0..<4].elementsEqual("FIT9".utf8),bytes[4]==version,bytes[5]==0,bytes[6]==0,bytes[7]<=1,
              bytes[8..<24].map({String(format:"%02x",$0)}).joined()==instance else {throw NativeControlError.invalid}
        func integer(_ start:Int,_ count:Int)->UInt64 {bytes[start..<(start+count)].reduce(0) {($0<<8)|UInt64($1)}}
        let current=integer(24,8),stamp=integer(32,8),modelCount=Int(integer(version==2 ? 64:60,4))
        var counts=stride(from:40,to:version==2 ? 64:60,by:4).map {Int(integer($0,4))}
        if version==1 {counts.insert(0,at:3)}
        guard current>sequence,current<=UInt64(ActivityPolicy.maximumTimestamp),
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)),modelCount<=64,
              version==1 || bytes[68..<72].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        var models=[NativePrimaryModelActivity]()
        for index in 0..<modelCount {
            let offset=header+index*record,length=Int(integer(offset,2))
            guard (1...1024).contains(length),bytes[offset+2]==0,bytes[offset+3]==0,
                  bytes[(offset+identityOffset+length)..<(offset+record)].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
            let encoded=Data(bytes[(offset+identityOffset)..<(offset+identityOffset+length)])
            guard let model=String(data:encoded,encoding:.utf8) else {throw NativeControlError.invalid}
            var phases=(0..<(version==2 ? 4:3)).map {Int(integer(offset+4+$0*4,4))}
            if version==1 {phases.insert(0,at:1)}
            models.append(NativePrimaryModelActivity(model:model,preparing:phases[0],queued:phases[1],active:phases[2],responding:phases[3]))
        }
        guard bytes[(header+modelCount*record)..<size].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        let value=NativePrimaryActivity(phaseVersion:Int(version),instance:instance,sampleSequence:current,sampledAt:stamp==UInt64.max ? nil:Int64(stamp),uncertain:bytes[7]==1,
            owners:counts[0],ingress:counts[1],preparing:counts[2],queued:counts[3],active:counts[4],responding:counts[5],models:models)
        try value.validate()
        return value
    }
}
