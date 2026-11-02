import Foundation

// Independent partial source flags. Neither Codable nor NativeSnapshot;
// false/zero/unavailable cannot establish idle, completion or native authority.
struct NativeBackendFences:Sendable {
    let instance:String
    let sampleSequence:UInt64
    let sampledAt:Int64?
    let mimoWarmUncertain:Bool?
    let ds4MetalUncertainty:UInt32?
    let ds4HostUncertainty:UInt32?
    func validate()throws {
        _=try NativeControlWire.instanceBytes(instance)
        guard sampleSequence>0,sampleSequence<=UInt64(ActivityPolicy.maximumTimestamp),
              sampledAt.map({(1...ActivityPolicy.maximumTimestamp).contains($0)}) ?? true,
              ds4MetalUncertainty.map({$0<=31}) ?? true,
              ds4HostUncertainty.map({$0<=7}) ?? true else {throw NativeControlError.invalid}
    }
}
struct NativeBackendFenceSample:Sendable {
    let peer:NativeControlPeer
    let receivedAt:Int64
    let fences:NativeBackendFences
}
enum NativeBackendFenceWire {
    static func request(instance:String)throws->Data {
        var output=Data(repeating:0,count:32)
        output.replaceSubrange(0..<4,with:Data("FIB9".utf8));output[4]=1
        output.replaceSubrange(8..<24,with:try NativeControlWire.instanceBytes(instance))
        return output
    }
    static func reply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativeBackendFences {
        let bytes=Array(data)
        _=try NativeControlWire.instanceBytes(instance)
        guard sequence<=UInt64(ActivityPolicy.maximumTimestamp),bytes.count==64,
              Array(bytes[0..<4])==Array("FIF9".utf8),bytes[4]==1,bytes[5]==0,
              bytes[6]<=7,bytes[7]<=1,bytes[48..<64].allSatisfy({$0==0}),
              bytes[8..<24].map({String(format:"%02x",$0)}).joined()==instance else {throw NativeControlError.invalid}
        func integer(_ start:Int,_ count:Int)->UInt64 {bytes[start..<(start+count)].reduce(0) {($0<<8)|UInt64($1)}}
        let current=integer(24,8),stamp=integer(32,8),metal=UInt32(integer(40,4)),host=UInt32(integer(44,4)),availability=bytes[6]
        guard current>sequence,current<=UInt64(ActivityPolicy.maximumTimestamp),
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)),metal<=31,host<=7,
              availability&1 != 0 || bytes[7]==0,availability&2 != 0 || metal==0,
              availability&4 != 0 || host==0 else {throw NativeControlError.invalid}
        let value=NativeBackendFences(instance:instance,sampleSequence:current,sampledAt:stamp==UInt64.max ? nil:Int64(stamp),
            mimoWarmUncertain:availability&1==0 ? nil:bytes[7]==1,
            ds4MetalUncertainty:availability&2==0 ? nil:metal,ds4HostUncertainty:availability&4==0 ? nil:host)
        try value.validate();return value
    }
}

// Serialized diagnostic cache. Unknown gaps retain the source checkpoint and
// any observed sticky bits. It never supplies a native inference/lifecycle proof.
struct NativeBackendFenceDiagnostics {
    let configured:Bool
    private var value:NativeBackendFenceSample?
    private var checkpoint:NativeBackendFenceSample?
    private var previousNow:Int64=0
    private var unavailable=false,fenced=false,seenMimo=false
    private var seenMetal:UInt32=0,seenHost:UInt32=0
    init(configured:Bool) {self.configured=configured}
    private func fresh(_ time:Int64,now:Int64)->Bool {
        (0...ActivityPolicy.maximumTimestamp).contains(time) && (0...ActivityPolicy.maximumTimestamp).contains(now) && (-1000...5000).contains(now-time)
    }
    mutating func failed() {value=nil;unavailable=true}
    mutating func bind(instance:String) {
        if let checkpoint,checkpoint.fences.instance != instance {fenced=true;failed()}
    }
    mutating func completed(_ sample:NativeBackendFenceSample,expectedInstance:String,now:Int64) {
        guard configured,!fenced else {failed();return}
        let flags=sample.fences
        do {try flags.validate()} catch {failed();return}
        guard flags.instance==expectedInstance,sample.peer.pid>1,sample.peer.start>0,
              let stamp=flags.sampledAt,fresh(stamp,now:now),fresh(sample.receivedAt,now:now) else {failed();return}
        if let old=checkpoint {
            guard sample.peer.pid==old.peer.pid,sample.peer.start==old.peer.start,
                  sample.peer.executable.path.utf8.elementsEqual(old.peer.executable.path.utf8),sample.peer.executable.sha256==old.peer.executable.sha256,
                  flags.instance==old.fences.instance,stamp>=old.fences.sampledAt!,now>=previousNow else {fenced=true;failed();return}
            guard flags.sampleSequence>old.fences.sampleSequence else {failed();return}
        }
        guard !(seenMimo && flags.mimoWarmUncertain==false),
              flags.ds4MetalUncertainty.map({$0&seenMetal==seenMetal}) ?? true,
              flags.ds4HostUncertainty.map({$0&seenHost==seenHost}) ?? true else {fenced=true;failed();return}
        if flags.mimoWarmUncertain==true {seenMimo=true}
        seenMetal |= flags.ds4MetalUncertainty ?? 0;seenHost |= flags.ds4HostUncertainty ?? 0
        checkpoint=sample;value=sample;previousNow=now;unavailable=false
    }
    func summary(now:Int64)->[String:Any] {
        var result:[String:Any]=["version":1,"scope":"independent_partial_backend_fences","coverage":"unknown","authority":false,
            "state":configured ? (fenced ? "fenced":unavailable ? "unavailable":"waiting"):"unconfigured",
            "source_instance":NSNull(),"source_sequence":NSNull(),"source_sampled_at":NSNull(),"source_age_ms":NSNull(),
            "received_at":NSNull(),"receipt_age_ms":NSNull(),"mimo_warm_uncertain":NSNull(),"ds4_metal_uncertainty":NSNull(),"ds4_host_uncertainty":NSNull(),
            "retained_uncertainty":seenMimo || seenMetal != 0 || seenHost != 0]
        guard configured,!fenced,let sample=value,let stamp=sample.fences.sampledAt else {return result}
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else {result["state"]="stale";return result}
        result["source_sequence"]=sample.fences.sampleSequence;result["source_sampled_at"]=stamp;result["source_age_ms"]=now-stamp
        result["received_at"]=sample.receivedAt;result["receipt_age_ms"]=now-sample.receivedAt
        guard now>=previousNow,fresh(stamp,now:now),fresh(sample.receivedAt,now:now) else {result["state"]="stale";return result}
        let flags=sample.fences
        result["state"]=flags.mimoWarmUncertain==nil && flags.ds4MetalUncertainty==nil && flags.ds4HostUncertainty==nil ? "unavailable":"received"
        result["source_instance"]=flags.instance
        result["mimo_warm_uncertain"]=flags.mimoWarmUncertain.map {$0 as Any} ?? NSNull()
        result["ds4_metal_uncertainty"]=flags.ds4MetalUncertainty.map {Int($0) as Any} ?? NSNull()
        result["ds4_host_uncertainty"]=flags.ds4HostUncertainty.map {Int($0) as Any} ?? NSNull()
        return result
    }
}
