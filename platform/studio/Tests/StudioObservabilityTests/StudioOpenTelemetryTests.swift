import XCTest
@testable import StudioCore
import StudioObservability
import OpenTelemetrySdk

private final class RecordedLogs:LogRecordProcessor {
    var records:[ReadableLogRecord]=[]
    func onEmit(logRecord:ReadableLogRecord) {records.append(logRecord)}
    func forceFlush(explicitTimeout:TimeInterval?)->ExportResult {.success}
    func shutdown(explicitTimeout:TimeInterval?)->ExportResult {.success}
}

final class StudioOpenTelemetryTests:XCTestCase {
    func testAuditEventsUseSDKLogsAndRetainLocalAudit() throws {
        let records=RecordedLogs(),telemetry=StudioOpenTelemetry(logProcessors:[records])
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let audit=try AuditLog(directory:directory,telemetry:telemetry)
        try audit.record(.started,now:HostResources.nowMilliseconds())
        XCTAssertEqual(records.records.count,1)
        XCTAssertEqual(records.records[0].eventName,"fios.platform.started")
        XCTAssertEqual(records.records[0].body?.description,"started")
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
        XCTAssertEqual(files.count,1)
        let local=try JSONSerialization.jsonObject(with:Data(contentsOf:files[0])) as! [String:Any]
        XCTAssertEqual(local["event"] as? String,"started")
    }
    func testOperationalCountersAndResourceGauges() throws {
        let telemetry=StudioOpenTelemetry()
        telemetry.event(.started);telemetry.event(.desiredChanged);telemetry.event(.desiredChanged)
        telemetry.resources(ResourceSample(sampledAt:HostResources.nowMilliseconds(),physical:1024,available:512,
                                           vmAvailable:nil,diskFree:4096,cpu:25,pressure:.normal,thermal:.nominal))
        let metrics=telemetry.collectMetrics()
        let events=try XCTUnwrap(metrics.first{$0.name=="fios.platform.events"},"Collected metric names: \(metrics.map(\.name))")
        XCTAssertEqual(events.type,.LongSum)
        XCTAssertEqual((events.data.points as! [LongPointData]).map(\.value).reduce(0,+),3)
        let cpu=try XCTUnwrap(metrics.first{$0.name=="fios.platform.host.cpu.utilization"})
        XCTAssertEqual(cpu.unit,"1")
        XCTAssertEqual((cpu.data.points as! [DoublePointData]).first!.value,0.25)
        let memory=try XCTUnwrap(metrics.first{$0.name=="fios.platform.host.memory.available"})
        XCTAssertEqual(memory.unit,"By")
        XCTAssertEqual((memory.data.points as! [DoublePointData]).first!.value,512)
        XCTAssertFalse(metrics.contains{$0.name=="fios.platform.vm.memory.available" && !$0.data.points.isEmpty})
        telemetry.resources(ResourceSample(sampledAt:HostResources.nowMilliseconds(),physical:1024,available:nil,
                                           vmAvailable:nil,diskFree:4096,cpu:nil,pressure:.unknown,thermal:.nominal))
        let unavailable=telemetry.collectMetrics()
        XCTAssertFalse(unavailable.contains{$0.name=="fios.platform.host.cpu.utilization" && !$0.data.points.isEmpty})
    }
    func testExpiredResourceSampleStopsPublishingGauges() {
        let telemetry=StudioOpenTelemetry()
        telemetry.resources(ResourceSample(sampledAt:HostResources.nowMilliseconds()-6000,physical:1024,available:512,
                                           vmAvailable:256,diskFree:4096,cpu:25,pressure:.normal,thermal:.nominal))
        let metrics=telemetry.collectMetrics()
        XCTAssertFalse(metrics.contains{$0.name.hasPrefix("fios.platform.host.") && !$0.data.points.isEmpty})
        XCTAssertFalse(metrics.contains{$0.name=="fios.platform.vm.memory.available" && !$0.data.points.isEmpty})
        XCTAssertFalse(metrics.contains{$0.name=="fios.platform.resource.sample.time" && !$0.data.points.isEmpty})
    }

    func testVMGaugeUsesItsOwnCollectionTime() throws {
        let telemetry=StudioOpenTelemetry(),now=HostResources.nowMilliseconds()
        telemetry.resources(ResourceSample(sampledAt:now,physical:1024,available:512,
                                           vmAvailable:256,diskFree:4096,cpu:25,pressure:.normal,thermal:.nominal,
                                           vmSampledAt:now))
        let vm=try XCTUnwrap(telemetry.collectMetrics().first{$0.name=="fios.platform.vm.memory.available"})
        XCTAssertEqual((vm.data.points as! [DoublePointData]).first!.value,256)
        telemetry.resources(ResourceSample(sampledAt:now,physical:1024,available:512,
                                           vmAvailable:256,diskFree:4096,cpu:25,pressure:.normal,thermal:.nominal,
                                           vmSampledAt:now-6000))
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.vm.memory.available" && !$0.data.points.isEmpty})
    }

    func testGPUAndHostConditionMetrics() throws {
        let telemetry=StudioOpenTelemetry(),now=HostResources.nowMilliseconds()
        telemetry.resources(ResourceSample(sampledAt:now,physical:1024,available:512,
                                           vmAvailable:nil,diskFree:4096,cpu:25,pressure:.warning,thermal:.fair,
                                           lowPowerMode:true))
        telemetry.gpu(GPUSample(utilization:40,inUseBytes:256,allocatedBytes:512),sampledAt:now)
        let metrics=telemetry.collectMetrics()
        let gpu=try XCTUnwrap(metrics.first{$0.name=="fios.platform.gpu.utilization"})
        XCTAssertEqual(gpu.unit,"1")
        XCTAssertEqual((gpu.data.points as! [DoublePointData]).first!.value,0.4)
        let memory=try XCTUnwrap(metrics.first{$0.name=="fios.platform.gpu.memory.in_use"})
        XCTAssertEqual(memory.unit,"By")
        XCTAssertEqual((memory.data.points as! [DoublePointData]).first!.value,256)
        let pressure=try XCTUnwrap(metrics.first{$0.name=="fios.platform.host.memory.pressure"})
        XCTAssertEqual((pressure.data.points as! [DoublePointData]).first!.attributes["fios.state"],.string("warning"))
        let thermal=try XCTUnwrap(metrics.first{$0.name=="fios.platform.host.thermal.state"})
        XCTAssertEqual((thermal.data.points as! [DoublePointData]).first!.attributes["fios.state"],.string("fair"))
        let power=try XCTUnwrap(metrics.first{$0.name=="fios.platform.host.power.low"})
        XCTAssertEqual((power.data.points as! [DoublePointData]).first!.value,1)
        telemetry.gpu(GPUSample(utilization:40,inUseBytes:256,allocatedBytes:512),sampledAt:now-6000)
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name.hasPrefix("fios.platform.gpu.") && !$0.data.points.isEmpty})
        telemetry.resources(ResourceSample(sampledAt:now,physical:1024,available:512,
                                           vmAvailable:nil,diskFree:4096,cpu:25,pressure:.unknown,thermal:.unknown))
        let unknown=telemetry.collectMetrics()
        for name in ["fios.platform.host.memory.pressure","fios.platform.host.thermal.state","fios.platform.host.power.low"] {
            XCTAssertFalse(unknown.contains{$0.name==name && !$0.data.points.isEmpty})
        }
    }

    func testWorkloadMetricsUseJournalAggregates() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds()
        let id=UUID().uuidString.lowercased()
        _=try journal.reserveJob(DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),
            ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:now))
        try journal.transitionJob(id:id,to:.running,now:now)
        // Local metadata only; no worker starts and no model request is sent.
        try journal.claim(job:id,attempt:0,model:"fixture/model",requestID:UUID().uuidString.lowercased())
        _=try journal.planWorkerLaunch(job:id,attempt:0)
        try journal.markUncertain(job:id,attempt:0)
        let sample=try XCTUnwrap(WorkloadTelemetry.sample(journal:journal,artifactBytes:2048,artifactJobs:1,now:now))
        XCTAssertEqual(sample.jobs[.running],1);XCTAssertEqual(sample.unresolvedRecords,1)
        XCTAssertEqual(sample.uncertainRecords,1);XCTAssertEqual(sample.workerReservations,1)
        let telemetry=StudioOpenTelemetry();telemetry.workload(sample)
        let metrics=telemetry.collectMetrics()
        let jobs=try XCTUnwrap(metrics.first{$0.name=="fios.platform.jobs"})
        let points=jobs.data.points as! [DoublePointData]
        XCTAssertEqual(points.count,JobState.allCases.count)
        XCTAssertEqual(points.first{$0.attributes["fios.job.state"] == .string("running")}?.value,1)
        let unresolved=try XCTUnwrap(metrics.first{$0.name=="fios.platform.inference.unresolved_records"})
        XCTAssertEqual((unresolved.data.points as! [DoublePointData]).first!.value,1)
        let bytes=try XCTUnwrap(metrics.first{$0.name=="fios.platform.artifacts.size"})
        XCTAssertEqual(bytes.unit,"By");XCTAssertEqual((bytes.data.points as! [DoublePointData]).first!.value,2048)
        telemetry.workload(nil)
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.jobs" && !$0.data.points.isEmpty})
    }

}
