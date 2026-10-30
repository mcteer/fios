import Foundation

// Readonly telemetry. Neither a sensor value nor this export supplies native
// idle, model-completion, lifecycle, or runtime-management authority.
enum ResourceObservationExport {
    struct Frame { let resources:[String:Any]; let observation:[String:Any] }
    static func encode(sample:ResourceSample,gpu:GPUSample?,gpuSampledAt:Int64?,now:Int64,epoch:String,sequence:Int64,vmEpoch:String?)throws->Frame {
        guard WireScalar.uuid(epoch),now>=0,now<=ActivityPolicy.maximumTimestamp,sequence>=0,sequence<=ActivityPolicy.maximumTimestamp else {throw ControlError.internal_error}
        let empty=NSNull(),maximum=UInt64(ActivityPolicy.maximumTimestamp)
        var values:[String:Any]=[:],signals:[String:[String:Any]]=[:]
        func validTime(_ time:Int64?)->Int64? {time.flatMap { (0...ActivityPolicy.maximumTimestamp).contains($0) ? $0:nil }}
        func publish(_ name:String,key:String,value:Any?,at:Int64?,unknown:Any?=nil) {
            let time=validTime(at),age=time.map {now-$0}
            let fresh=age.map {(-1000...5000).contains($0)} ?? false
            let availability=value == nil || time == nil ? "unknown":fresh ? "observed":"stale"
            values[key]=availability == "observed" ? value!:unknown ?? empty
            signals[name]=["availability":availability,"sampled_at":time.map {$0 as Any} ?? empty,"age_ms":age.map {$0 as Any} ?? empty]
        }
        func bytes(_ value:UInt64?)->UInt64? {value.flatMap {$0<=maximum ? $0:nil}}
        let physical=sample.physical>0 ? bytes(sample.physical):nil
        publish("physical_memory",key:"physical",value:physical,at:sample.sampledAt)
        publish("available_memory",key:"available",value:sample.available.flatMap {physical != nil && $0<=sample.physical ? bytes($0):nil},at:sample.sampledAt)
        publish("cpu",key:"cpu",value:sample.cpu.flatMap {$0.isFinite && (0...100).contains($0) ? $0:nil},at:sample.sampledAt)
        publish("disk_free",key:"diskFree",value:bytes(sample.diskFree),at:sample.sampledAt)
        publish("pressure",key:"pressure",value:sample.pressure == .unknown ? nil:sample.pressure.rawValue,at:sample.sampledAt,unknown:"unknown")
        publish("thermal",key:"thermal",value:sample.thermal == .unknown ? nil:sample.thermal.rawValue,at:sample.sampledAt,unknown:"unknown")
        publish("low_power_mode",key:"lowPowerMode",value:sample.lowPowerMode,at:sample.sampledAt)
        let boundVM=vmEpoch.map(WireScalar.sha256) == true
        publish("vm_available",key:"vmAvailable",value:boundVM && physical != nil ? sample.vmAvailable.flatMap {$0<=sample.physical ? bytes($0):nil}:nil,at:sample.vmSampledAt)
        publish("gpu",key:"gpu",value:gpu.flatMap {$0.utilization.isFinite && (0...100).contains($0.utilization) ? $0.utilization:nil},at:gpuSampledAt)
        publish("gpu_in_use_memory",key:"gpu_in_use_bytes",value:bytes(gpu?.inUseBytes),at:gpuSampledAt)
        publish("gpu_allocated_memory",key:"gpu_allocated_bytes",value:bytes(gpu?.allocatedBytes),at:gpuSampledAt)
        values["sampledAt"]=validTime(sample.sampledAt).map {$0 as Any} ?? empty
        values["vmSampledAt"]=validTime(sample.vmSampledAt).map {$0 as Any} ?? empty
        values["diskCommitted"]=bytes(sample.diskCommitted).map {$0 as Any} ?? empty
        let vmObserved=signals["vm_available"]?["availability"] as? String == "observed"
        let gpuObserved=signals["gpu"]?["availability"] as? String == "observed"
        return Frame(resources:values,observation:["version":2,"epoch":epoch,"sequence":sequence,"sampled_at":values["sampledAt"]!,"observed_at":now,
            "gpu_coverage":gpuObserved ? "observed_registry":"unavailable","vm_coverage":vmObserved ? "verified_envelope":"unknown",
            "vm_sampled_at":values["vmSampledAt"]!,"vm_epoch":vmObserved ? vmEpoch! as Any:empty,"signals":signals])
    }
}
