import Foundation
import StudioCore
import OpenTelemetryApi
import OpenTelemetrySdk

private final class ResourceMetrics:@unchecked Sendable {
    let lock=NSLock()
    var sample:ResourceSample?
    var gpu:GPUSample?
    var gpuAt:Int64?
    var workload:PlatformWorkloadSample?
    var services:[PlatformServiceSample]=[]
    var nativeIngress:PlatformNativeIngressSample?
    func update(_ value:ResourceSample) {lock.lock();sample=value;lock.unlock()}
    func updateGPU(_ value:GPUSample?,sampledAt:Int64?) {lock.lock();gpu=value;gpuAt=sampledAt;lock.unlock()}
    func currentGPU()->(sample:GPUSample,sampledAt:Int64)? {
        lock.lock();defer {lock.unlock()}
        guard let gpu,let gpuAt,(-1000...5000).contains(HostResources.nowMilliseconds()-gpuAt) else {return nil}
        return (gpu,gpuAt)
    }
    func updateWorkload(_ value:PlatformWorkloadSample?) {lock.lock();workload=value;lock.unlock()}
    func currentWorkload()->PlatformWorkloadSample? {
        lock.lock();defer {lock.unlock()}
        guard let workload,(-1000...5000).contains(HostResources.nowMilliseconds()-workload.sampledAt) else {return nil}
        return workload
    }
    func updateServices(_ values:[PlatformServiceSample]) {lock.lock();services=values;lock.unlock()}
    func currentServices()->[PlatformServiceSample] {
        lock.lock();defer {lock.unlock()}
        let now=HostResources.nowMilliseconds()
        return services.filter{(-1000...5000).contains(now-$0.sampledAt)}
    }
    func updateNativeIngress(_ value:PlatformNativeIngressSample?) {lock.lock();nativeIngress=value;lock.unlock()}
    func currentNativeIngress()->PlatformNativeIngressSample? {
        lock.lock();defer {lock.unlock()}
        let now=HostResources.nowMilliseconds()
        func fresh(_ time:Int64)->Bool {(0...WireScalar.maximumTimestamp).contains(time) && (-1000...5000).contains(now-time)}
        guard let nativeIngress,fresh(nativeIngress.receivedAt),nativeIngress.sourceSampledAt.map(fresh) ?? true else {return nil}
        return nativeIngress
    }
    func current()->ResourceSample? {
        lock.lock();defer {lock.unlock()}
        guard let sample,(-1000...5000).contains(HostResources.nowMilliseconds()-sample.sampledAt) else {return nil}
        return sample
    }
}

// Pull collection lets a future standard OTel exporter consume SDK MetricData.
// No timer, network transport or backend is started by this reader.
private final class PullMetricReader:MetricReader,@unchecked Sendable {
    private let lock=NSLock()
    private var producer:(any MetricProducer)?
    func register(registration:any CollectionRegistration) {lock.lock();producer=registration as? any MetricProducer;lock.unlock()}
    func collect()->[MetricData] {lock.lock();defer {lock.unlock()};return producer?.collectAllMetrics() ?? []}
    func forceFlush()->ExportResult {.success}
    func shutdown()->ExportResult {lock.lock();producer=nil;lock.unlock();return .success}
    func getAggregationTemporality(for instrument:InstrumentType)->AggregationTemporality {.cumulative}
    func getDefaultAggregation(for instrument:InstrumentType)->any Aggregation {Aggregations.defaultAggregation()}
}

/// OTel SDK instrumentation for fixed operational events and host resources.
/// Transport/exporter configuration belongs to the separately deployed backend.
public final class StudioOpenTelemetry:PlatformTelemetry,@unchecked Sendable {
    public var instrumentation:String {"opentelemetry-swift"}
    private let reader=PullMetricReader()
    private let state=ResourceMetrics()
    private let provider:MeterProviderSdk
    private let logs:LoggerProviderSdk
    private let logger:any OpenTelemetryApi.Logger
    private let events:LongCounterSdk

    public init(metricReader:(any MetricReader)?=nil,logProcessors:[any LogRecordProcessor]=[]) {
        let resource=Resource(attributes:["service.name":.string("fios-studio-manager"),"service.namespace":.string("fios")])
        let builder=MeterProviderSdk.builder().setResource(resource:resource).registerMetricReader(reader:reader)
            .registerView(selector:InstrumentSelector.builder().build(),view:View.builder().build())
        if let metricReader {_=builder.registerMetricReader(reader:metricReader)}
        provider=builder.build()
        logs=LoggerProviderBuilder().with(resource:resource).with(processors:logProcessors).build()
        logger=logs.get(instrumentationScopeName:"fios.studio")
        let meter=provider.meterBuilder(name:"fios.studio").build()
        events=meter.counterBuilder(name:"fios.platform.events").setUnit("{event}").setDescription("Operational platform events").build()
        let state=self.state
        let metrics:[(String,String,(ResourceSample)->Double?)]=[
            ("fios.platform.host.cpu.utilization","1",{$0.cpu.map{$0/100}}),
            ("fios.platform.host.memory.physical","By",{Double($0.physical)}),
            ("fios.platform.host.memory.available","By",{$0.available.map{Double($0)}}),
            ("fios.platform.host.disk.free","By",{$0.diskFree.map{Double($0)}}),
            ("fios.platform.host.power.low","1",{$0.lowPowerMode.map{$0 ? 1.0:0.0}}),
            ("fios.platform.vm.memory.available","By",{sample in
                guard let time=sample.vmSampledAt,(-1000...5000).contains(HostResources.nowMilliseconds()-time) else {return nil}
                return sample.vmAvailable.map{Double($0)}
            })
        ]
        for (name,unit,value) in metrics {
            _=meter.gaugeBuilder(name:name).setUnit(unit).buildWithCallback { observation in
                if let sample=state.current(),let number=value(sample) {observation.record(value:number)}
            }
        }
        let conditions:[(String,(ResourceSample)->String?)]=[
            ("fios.platform.host.memory.pressure",{$0.pressure == .unknown ? nil:$0.pressure.rawValue}),
            ("fios.platform.host.thermal.state",{$0.thermal == .unknown ? nil:$0.thermal.rawValue})
        ]
        for (name,value) in conditions {
            _=meter.gaugeBuilder(name:name).setUnit("1").buildWithCallback { observation in
                if let sample=state.current(),let condition=value(sample) {
                    observation.record(value:1,attributes:["fios.state":.string(condition)])
                }
            }
        }
        let gpuMetrics:[(String,String,(GPUSample)->Double?)]=[
            ("fios.platform.gpu.utilization","1",{$0.utilization/100}),
            ("fios.platform.gpu.memory.in_use","By",{$0.inUseBytes.map{Double($0)}}),
            ("fios.platform.gpu.memory.allocated","By",{$0.allocatedBytes.map{Double($0)}})
        ]
        for (name,unit,value) in gpuMetrics {
            _=meter.gaugeBuilder(name:name).setUnit(unit).buildWithCallback { observation in
                if let sample=state.currentGPU(),let number=value(sample.sample) {observation.record(value:number)}
            }
        }
        _=meter.gaugeBuilder(name:"fios.platform.gpu.sample.time").setUnit("s").buildWithCallback { observation in
            if let sample=state.currentGPU() {observation.record(value:Double(sample.sampledAt)/1000)}
        }
        _=meter.gaugeBuilder(name:"fios.platform.jobs").setUnit("{job}").buildWithCallback { observation in
            if let sample=state.currentWorkload() {
                for status in JobState.allCases {
                    if let count=sample.jobs[status] {observation.record(value:Double(count),attributes:["fios.job.state":.string(status.rawValue)])}
                }
            }
        }
        let workloadMetrics:[(String,String,(PlatformWorkloadSample)->Double)]=[
            ("fios.platform.inference.unresolved_records","{record}",{Double($0.unresolvedRecords)}),
            ("fios.platform.inference.uncertain_records","{record}",{Double($0.uncertainRecords)}),
            ("fios.platform.workers.reservations","{reservation}",{Double($0.workerReservations)}),
            ("fios.platform.artifacts.size","By",{Double($0.artifactBytes)}),
            ("fios.platform.artifacts.jobs","{job}",{Double($0.artifactJobs)}),
            ("fios.platform.workload.sample.time","s",{Double($0.sampledAt)/1000})
        ]
        for (name,unit,value) in workloadMetrics {
            _=meter.gaugeBuilder(name:name).setUnit(unit).buildWithCallback { observation in
                if let sample=state.currentWorkload() {observation.record(value:value(sample))}
            }
        }
        let cleanupMetrics:[(String,String,(PlatformWorkloadSample)->Double?)]=[
            ("fios.platform.sandbox.cleanup.pending","{sandbox}",{$0.cleanupPending.map{Double($0)}}),
            ("fios.platform.sandbox.cleanup.wait","s",{$0.cleanupWaitMilliseconds.map{Double($0)/1000}})
        ]
        for (name,unit,value) in cleanupMetrics {
            _=meter.gaugeBuilder(name:name).setUnit(unit).buildWithCallback { observation in
                if let sample=state.currentWorkload(),let number=value(sample) {observation.record(value:number)}
            }
        }
        _=meter.gaugeBuilder(name:"fios.platform.service.state").setUnit("1").buildWithCallback { observation in
            for sample in state.currentServices() {
                observation.record(value:1,attributes:["fios.service":.string(sample.service.rawValue),
                    "fios.service.desired":.string(sample.desired.rawValue),"fios.service.observed":.string(sample.observed.rawValue)])
            }
        }
        let nativeMetrics:[(String,String,(PlatformNativeIngressSample)->Double?)]=[
            ("owners","{owner}",{Double($0.owners)}),
            ("unparsed","{owner}",{Double($0.ingress)}),
            ("preparing","{owner}",{Double($0.preparing)}),
            ("active","{owner}",{Double($0.active)}),
            ("responding","{owner}",{Double($0.responding)}),
            ("model_identities","{identity}",{Double($0.modelIdentities)}),
            ("closed","1",{$0.closed ? 1:0}),
            ("tracker_uncertain","1",{$0.trackerUncertain ? 1:0}),
            ("receipt.time","s",{Double($0.receivedAt)/1000}),
            ("source.time","s",{$0.sourceSampledAt.map{Double($0)/1000}})
        ]
        for (name,unit,value) in nativeMetrics {
            _=meter.gaugeBuilder(name:"fios.platform.native.ingress."+name).setUnit(unit).buildWithCallback { observation in
                if let sample=state.currentNativeIngress(),let number=value(sample) {
                    observation.record(value:number,attributes:["fios.scope":.string("native_ingress_tracker"),
                        "fios.sample.clock":.string(sample.sourceSampledAt==nil ? "receipt_only":"source_and_receipt")])
                }
            }
        }
        _=meter.gaugeBuilder(name:"fios.platform.resource.sample.time").setUnit("s").buildWithCallback { observation in
            if let sample=state.current() {observation.record(value:Double(sample.sampledAt)/1000)}
        }
    }
    public func event(_ event:OperationalEvent) {
        events.add(value:1,attributes:["fios.event":.string(event.rawValue)])
        logger.logRecordBuilder().setEventName("fios.platform."+event.rawValue).setBody(.string(event.rawValue)).emit()
    }
    public func resources(_ sample:ResourceSample) {state.update(sample)}
    public func gpu(_ sample:GPUSample?,sampledAt:Int64?) {state.updateGPU(sample,sampledAt:sampledAt)}
    public func workload(_ sample:PlatformWorkloadSample?) {state.updateWorkload(sample)}
    public func services(_ samples:[PlatformServiceSample]) {state.updateServices(samples)}
    public func nativeIngress(_ sample:PlatformNativeIngressSample?) {state.updateNativeIngress(sample)}
    public func collectMetrics()->[MetricData] {reader.collect()}
    deinit {_ = reader.shutdown()}
}
