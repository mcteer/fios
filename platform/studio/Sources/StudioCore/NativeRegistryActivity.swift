import Foundation

// Registry declarations coupled to one native request capture. Not GPU
// residency/idle proof, all-client coverage, a reservation or native terminality.
struct NativeRegistryModelFact:Sendable {
    let model:String
    let readyDeclared:Bool
    let transitioning:Bool
    let uncertain:Bool
    var claimable:Bool? = nil
    let counts:NativePhaseCounts
}
struct NativeRegistryActivity:Sendable {
    let primary:NativePrimaryActivity
    let registryGeneration:UInt64
    let transitioning:Bool
    let models:[NativeRegistryModelFact]
    func validate()throws {
        try primary.validate()
        guard [3,4].contains(primary.phaseVersion),registryGeneration<=UInt64(ActivityPolicy.maximumTimestamp),models.count<=64 else {throw NativeControlError.invalid}
        var identities=Set<Data>(),totals=[0,0,0,0],positive=[NativePrimaryModelActivity]()
        for row in models {
            guard WireScalar.model(row.model),!row.model.contains("\0"),identities.insert(Data(row.model.utf8)).inserted,
                  row.counts.ingress==0,row.counts.values.allSatisfy({(0...256).contains($0)}),
                  !row.uncertain || primary.uncertain else {throw NativeControlError.invalid}
            if primary.phaseVersion==4 {
                guard let claimable=row.claimable,!claimable || (!row.transitioning && !row.uncertain),
                      !row.readyDeclared || row.uncertain || claimable else {throw NativeControlError.invalid}
            } else if row.claimable != nil {throw NativeControlError.invalid}
            let phases=[row.counts.preparing,row.counts.queued,row.counts.active,row.counts.responding]
            let count=phases.reduce(0,+)
            guard count>0 || row.readyDeclared || row.transitioning || row.uncertain else {throw NativeControlError.invalid}
            for index in 0..<4 {totals[index]+=phases[index]}
            if count>0 {positive.append(NativePrimaryModelActivity(model:row.model,preparing:phases[0],queued:phases[1],active:phases[2],responding:phases[3]))}
        }
        guard totals==[primary.preparing,primary.queued,primary.active,primary.responding],
              models.contains(where:{$0.transitioning})==transitioning,positive.count==primary.models.count else {throw NativeControlError.invalid}
        for (a,b) in zip(positive,primary.models) {
            guard a.model.utf8.elementsEqual(b.model.utf8),a.preparing==b.preparing,a.queued==b.queued,a.active==b.active,a.responding==b.responding else {throw NativeControlError.invalid}
        }
    }
    // The independent native audit/installed ceiling is not supplied by this
    // frame. Neither declared-ready rows nor zero owners can upgrade it.
    func conservativeActivity()->CoherentNativeActivity {
        NativeActivityCoherence.evaluate(coverage:.unknown,sourceCoverage:.unknown,
            totals:NativePhaseCounts(ingress:primary.ingress,preparing:primary.preparing,queued:primary.queued,active:primary.active,responding:primary.responding),
            unattributed:NativePhaseCounts(ingress:primary.ingress,preparing:0,queued:0,active:0,responding:0),
            models:models.map {NativeModelActivity(model:$0.model,resident:$0.readyDeclared,counts:$0.counts)},transitioning:transitioning)
    }
}
enum NativeRegistryActivityWire {
    static let responseSize=67168,recordSize=1048
    static func request(instance:String,version:UInt8=3)throws->Data {
        guard [3,4].contains(version) else {throw NativeControlError.invalid}
        var data=try NativePrimaryActivityWire.queuedRequest(instance:instance);data[4]=version;return data
    }
    static func reply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativeRegistryActivity {
        guard data.count==responseSize,sequence<=UInt64(ActivityPolicy.maximumTimestamp) else {throw NativeControlError.invalid}
        _=try NativeControlWire.instanceBytes(instance);let bytes=Array(data)
        guard bytes[0..<4].elementsEqual("FIT9".utf8),[3,4].contains(bytes[4]),bytes[5]==0,bytes[6]==0,bytes[7]<=1,
              bytes[8..<24].map({String(format:"%02x",$0)}).joined()==instance,
              bytes[76]<=1,bytes[77..<96].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        func integer(_ offset:Int,_ length:Int)->UInt64 {bytes[offset..<(offset+length)].reduce(0) {($0<<8)|UInt64($1)}}
        let current=integer(24,8),stamp=integer(32,8),generation=integer(40,8),modelCount=Int(integer(72,4))
        let counts=stride(from:48,to:72,by:4).map {Int(integer($0,4))}
        guard current>sequence,current<=UInt64(ActivityPolicy.maximumTimestamp),generation<=UInt64(ActivityPolicy.maximumTimestamp),
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)),modelCount<=64,
              counts.allSatisfy({(0...256).contains($0)}),counts[0]==counts[1...5].reduce(0,+) else {throw NativeControlError.invalid}
        var rows=[NativeRegistryModelFact](),primaryRows=[NativePrimaryModelActivity]()
        for index in 0..<modelCount {
            let offset=96+index*recordSize,length=Int(integer(offset,2))
            guard (1...1024).contains(length),bytes[offset+2]<=1,bytes[offset+3]<=(bytes[4]==4 ? 7:3),
                  bytes[(offset+20)..<(offset+24)].allSatisfy({$0==0}),
                  bytes[(offset+24+length)..<(offset+recordSize)].allSatisfy({$0==0}),
                  let model=String(data:Data(bytes[(offset+24)..<(offset+24+length)]),encoding:.utf8) else {throw NativeControlError.invalid}
            let phases=(0..<4).map {Int(integer(offset+4+$0*4,4))}
            guard phases.allSatisfy({(0...256).contains($0)}) else {throw NativeControlError.invalid}
            rows.append(NativeRegistryModelFact(model:model,readyDeclared:bytes[offset+2]==1,transitioning:bytes[offset+3]&1 != 0,uncertain:bytes[offset+3]&2 != 0,claimable:bytes[4]==4 ? bytes[offset+3]&4 != 0:nil,
                counts:NativePhaseCounts(ingress:0,preparing:phases[0],queued:phases[1],active:phases[2],responding:phases[3])))
            if phases.reduce(0,+)>0 {primaryRows.append(NativePrimaryModelActivity(model:model,preparing:phases[0],queued:phases[1],active:phases[2],responding:phases[3]))}
        }
        guard bytes[(96+modelCount*recordSize)..<responseSize].allSatisfy({$0==0}) else {throw NativeControlError.invalid}
        let primary=NativePrimaryActivity(phaseVersion:Int(bytes[4]),instance:instance,sampleSequence:current,sampledAt:stamp==UInt64.max ? nil:Int64(stamp),uncertain:bytes[7]==1,
            owners:counts[0],ingress:counts[1],preparing:counts[2],queued:counts[3],active:counts[4],responding:counts[5],models:primaryRows)
        let value=NativeRegistryActivity(primary:primary,registryGeneration:generation,transitioning:bytes[76]==1,models:rows)
        try value.validate();return value
    }
}
