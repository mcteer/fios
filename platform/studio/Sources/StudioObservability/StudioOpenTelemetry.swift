import Foundation
import StudioCore
import OpenTelemetryApi
import OpenTelemetrySdk

private final class ResourceMetrics:@unchecked Sendable {
    let lock=NSLock()
    var sample:ResourceSample?
    func update(_ value:ResourceSample) {lock.lock();sample=value;lock.unlock()}
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
        _=meter.gaugeBuilder(name:"fios.platform.resource.sample.time").setUnit("s").buildWithCallback { observation in
            if let sample=state.current() {observation.record(value:Double(sample.sampledAt)/1000)}
        }
    }
    public func event(_ event:OperationalEvent) {
        events.add(value:1,attributes:["fios.event":.string(event.rawValue)])
        logger.logRecordBuilder().setEventName("fios.platform."+event.rawValue).setBody(.string(event.rawValue)).emit()
    }
    public func resources(_ sample:ResourceSample) {state.update(sample)}
    public func collectMetrics()->[MetricData] {reader.collect()}
    deinit {_ = reader.shutdown()}
}
