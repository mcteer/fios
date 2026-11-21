import Foundation

// Separate availability/coverage metadata. Neither false nor absence is a
// positive coverage claim; an observed gap is not a cleanup failure.
struct NativeBackgroundCoverage:Sendable,Equatable {
    let sdkResidencyRefreshUntracked:Bool?
}

// Explicit current-ABI negative flags only. Availability means a compiled
// readonly flag exists; false is no all-client, idle or terminal proof.
struct NativeCurrentBackendFlags:Sendable,Equatable {
    let available:UInt8
    let uncertain:UInt8
    static let names=["sdk_uncertain","llama_uncertain","streamed_pool_uncertain","ds4_host_uncertain","ds4_gpu_uncertain","ane_reported_uncertain","ane_native_uncertain"]
    func validate()throws {
        guard available<=127,uncertain<=127,uncertain & ~available == 0 else {throw NativeControlError.invalid}
    }
    var dictionary:[String:Any] {
        var output=[String:Any]()
        for (index,name) in Self.names.enumerated() {
            let bit=UInt8(1)<<index
            output[name]=available & bit == 0 ? NSNull():((uncertain & bit != 0) as Any)
        }
        return output
    }
}
extension NativeBackendFenceWire {
    static func currentRequest(instance:String)throws->Data {
        var data=try request(instance:instance);data[4]=2;return data
    }
    static func currentReply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativeBackendFences {
        try decodeCurrent(data,instance:instance,after:sequence,background:false)
    }
    static func backgroundRequest(instance:String)throws->Data {
        var data=try currentRequest(instance:instance);data[4]=3;return data
    }
    static func backgroundReply(_ data:Data,instance:String,after sequence:UInt64=0)throws->NativeBackendFences {
        try decodeCurrent(data,instance:instance,after:sequence,background:true)
    }
    private static func decodeCurrent(_ data:Data,instance:String,after sequence:UInt64,background:Bool)throws->NativeBackendFences {
        let bytes=Array(data);_=try NativeControlWire.instanceBytes(instance)
        guard sequence<=UInt64(ActivityPolicy.maximumTimestamp),bytes.count==64,
              bytes[0..<4].elementsEqual("FIF9".utf8),bytes[4]==(background ? 3:2),bytes[5]==0,
              bytes[8..<24].map({String(format:"%02x",$0)}).joined()==instance,
              (background ? bytes[40]<=2 && bytes[41..<64].allSatisfy({$0==0}):bytes[40..<64].allSatisfy({$0==0})) else {throw NativeControlError.invalid}
        func integer(_ start:Int)->UInt64 {bytes[start..<(start+8)].reduce(0) {($0<<8)|UInt64($1)}}
        let current=integer(24),stamp=integer(32)
        guard current>sequence,current<=UInt64(ActivityPolicy.maximumTimestamp),
              stamp==UInt64.max || (stamp>0 && stamp<=UInt64(ActivityPolicy.maximumTimestamp)) else {throw NativeControlError.invalid}
        let flags=NativeCurrentBackendFlags(available:bytes[6],uncertain:bytes[7]);try flags.validate()
        let value=NativeBackendFences(instance:instance,sampleSequence:current,sampledAt:stamp==UInt64.max ? nil:Int64(stamp),
            mimoWarmUncertain:nil,ds4MetalUncertainty:nil,ds4HostUncertainty:nil,current:flags,
            backgroundCoverage:background ? NativeBackgroundCoverage(sdkResidencyRefreshUntracked:bytes[40]==0 ? nil:bytes[40]==2):nil)
        try value.validate();return value
    }
}
