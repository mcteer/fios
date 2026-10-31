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
        XCTAssertFalse(metrics.contains{$0.name=="fios.platform.vm.sample.time" && !$0.data.points.isEmpty})
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
                                           vmSampledAt:now-1000))
        let vm=try XCTUnwrap(telemetry.collectMetrics().first{$0.name=="fios.platform.vm.memory.available"})
        XCTAssertEqual((vm.data.points as! [DoublePointData]).first!.value,256)
        let clock=try XCTUnwrap(telemetry.collectMetrics().first{$0.name=="fios.platform.vm.sample.time"})
        XCTAssertEqual(clock.unit,"s")
        XCTAssertEqual((clock.data.points as! [DoublePointData]).first!.value,Double(now-1000)/1000)
        telemetry.resources(ResourceSample(sampledAt:now,physical:1024,available:512,
                                           vmAvailable:256,diskFree:4096,cpu:25,pressure:.normal,thermal:.nominal,
                                           vmSampledAt:now-6000))
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.vm.memory.available" && !$0.data.points.isEmpty})
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.vm.sample.time" && !$0.data.points.isEmpty})
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

    func testSandboxReservationMetricsFollowJournalResources() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let journal=try Journal(directory:directory),now=HostResources.nowMilliseconds()
        var ids:[String]=[]
        for (memory,cpus,workspace):(UInt64,Int,UInt64) in [(512<<20,1,128<<20),(2<<30,2,256<<20)] {
            let id=UUID().uuidString.lowercased();ids.append(id)
            let job=try DurableJob(id:id,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:now)
            _=try journal.reserveSandbox(job:job,configuration:SandboxConfiguration(job:id,nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:memory,cpus:cpus,workspace:workspace))
        }
        // Independent ownership metadata; no worker or model call is made.
        let modelJob=UUID().uuidString.lowercased()
        _=try journal.reserveJob(DurableJob(id:modelJob,idempotency:UUID().uuidString.lowercased(),ownerHash:String(repeating:"a",count:64),requestHash:String(repeating:"b",count:64),created:now))
        try journal.claim(job:modelJob,attempt:0,model:"fixture/model")
        try journal.markUncertain(job:modelJob,attempt:0)
        let telemetry=StudioOpenTelemetry()
        func refresh()throws {
            telemetry.workload(try XCTUnwrap(WorkloadTelemetry.sample(journal:journal,artifactBytes:0,artifactJobs:0,now:now)))
        }
        func number(_ name:String,_ unit:String)throws->Double {
            let metric=try XCTUnwrap(telemetry.collectMetrics().first{$0.name==name})
            XCTAssertEqual(metric.unit,unit)
            let point=try XCTUnwrap((metric.data.points as? [DoublePointData])?.first)
            XCTAssertTrue(point.attributes.isEmpty)
            return point.value
        }
        try refresh()
        XCTAssertEqual(try number("fios.platform.sandbox.memory.reserved","By"),Double((2<<30)+(512<<20)))
        XCTAssertEqual(try number("fios.platform.sandbox.cpu.reserved","{cpu}"),3)
        XCTAssertEqual(try number("fios.platform.sandbox.workspace.capacity","By"),Double(384<<20))
        try journal.transitionJob(id:ids[0],to:.revoking,now:now)
        try refresh()
        XCTAssertEqual(try number("fios.platform.sandbox.memory.reserved","By"),Double((2<<30)+(512<<20)))
        // The fixture never issued create; confirmed absence releases only
        // this record's local runtime reservation, with no external action.
        try journal.confirmSandboxAbsent(job:ids[0])
        try journal.transitionJob(id:ids[0],to:.removed,now:now)
        try refresh()
        XCTAssertEqual(try number("fios.platform.sandbox.memory.reserved","By"),Double(2<<30))
        XCTAssertEqual(try number("fios.platform.sandbox.cpu.reserved","{cpu}"),2)
        XCTAssertEqual(try number("fios.platform.sandbox.workspace.capacity","By"),Double(256<<20))
        XCTAssertEqual(try number("fios.platform.inference.uncertain_records","{record}"),1)
        telemetry.workload(nil)
        for name in ["fios.platform.sandbox.memory.reserved","fios.platform.sandbox.cpu.reserved","fios.platform.sandbox.workspace.capacity"] {
            XCTAssertFalse(telemetry.collectMetrics().contains{$0.name==name && !$0.data.points.isEmpty})
        }
    }

    func testCleanupMetricsFollowCurrentWaitAndRecovery() throws {
        let telemetry=StudioOpenTelemetry(),now=HostResources.nowMilliseconds()
        func sample(pending:Int,wait:Int64?)->PlatformWorkloadSample {
            PlatformWorkloadSample(sampledAt:now,jobs:[:],unresolvedRecords:1,uncertainRecords:1,
                workerReservations:0,artifactBytes:0,artifactJobs:0,
                cleanupPending:pending,cleanupWaitMilliseconds:wait)
        }
        func value(_ name:String)->Double? {
            let metric=telemetry.collectMetrics().first{$0.name==name}
            return (metric?.data.points as? [DoublePointData])?.first?.value
        }
        telemetry.workload(sample(pending:1,wait:61000))
        XCTAssertEqual(value("fios.platform.sandbox.cleanup.pending"),1)
        XCTAssertEqual(value("fios.platform.sandbox.cleanup.wait"),61)
        telemetry.workload(sample(pending:0,wait:0))
        XCTAssertEqual(value("fios.platform.sandbox.cleanup.pending"),0)
        XCTAssertEqual(value("fios.platform.sandbox.cleanup.wait"),0)
        XCTAssertEqual(value("fios.platform.inference.uncertain_records"),1)
        telemetry.workload(sample(pending:1,wait:nil))
        XCTAssertEqual(value("fios.platform.sandbox.cleanup.pending"),1)
        XCTAssertNil(value("fios.platform.sandbox.cleanup.wait"))
    }

    func testServiceStateMetricsUseFixedStatesAndExpire() throws {
        let telemetry=StudioOpenTelemetry(),now=HostResources.nowMilliseconds()
        telemetry.services([PlatformServiceSample(service:.mlx,desired:.maintenance,observed:.unknown,sampledAt:now)])
        let metric=try XCTUnwrap(telemetry.collectMetrics().first{$0.name=="fios.platform.service.state"})
        let point=try XCTUnwrap((metric.data.points as? [DoublePointData])?.first)
        XCTAssertEqual(point.value,1)
        XCTAssertEqual(point.attributes["fios.service"],.string("mlx"))
        XCTAssertEqual(point.attributes["fios.service.desired"],.string("maintenance"))
        XCTAssertEqual(point.attributes["fios.service.observed"],.string("unknown"))
        telemetry.services([PlatformServiceSample(service:.orbstack,desired:.running,observed:.ready,sampledAt:now-6000)])
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.service.state" && !$0.data.points.isEmpty})
        telemetry.services([])
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.service.state" && !$0.data.points.isEmpty})
    }

    func testNativeIngressMetricsPreserveReceiptAndSourceTimes() throws {
        let telemetry=StudioOpenTelemetry(),now=HostResources.nowMilliseconds()
        var diagnostics=NativeControlDiagnostics(configured:true)
        var reply=NativeIngressStatus(operation:.observe,status:.ok,instance:String(repeating:"a",count:32),
            pauseSequence:0,owners:1,ingress:0,preparing:0,active:1,responding:0,modelIdentities:1,closed:false,uncertain:false)
        reply.nativeSampleSequence=42;reply.nativeSampledAt=now-50
        diagnostics.completed(reply,receivedAt:now)
        let sample=try XCTUnwrap(diagnostics.ingressSample(now:now))
        telemetry.nativeIngress(sample)
        let metrics=telemetry.collectMetrics()
        let owners=try XCTUnwrap(metrics.first{$0.name=="fios.platform.native.ingress.owners"})
        let point=try XCTUnwrap((owners.data.points as? [DoublePointData])?.first)
        XCTAssertEqual(owners.unit,"{owner}");XCTAssertEqual(point.value,1)
        XCTAssertEqual(point.attributes["fios.sample.clock"],.string("source_and_receipt"))
        let receipt=try XCTUnwrap(metrics.first{$0.name=="fios.platform.native.ingress.receipt.time"})
        XCTAssertEqual((receipt.data.points as! [DoublePointData]).first!.value,Double(now)/1000)
        let source=try XCTUnwrap(metrics.first{$0.name=="fios.platform.native.ingress.source.time"})
        XCTAssertEqual((source.data.points as! [DoublePointData]).first!.value,Double(now-50)/1000)
        reply.nativeSampledAt=now-6000;diagnostics.completed(reply,receivedAt:now)
        telemetry.nativeIngress(diagnostics.ingressSample(now:now))
        XCTAssertFalse(telemetry.collectMetrics().contains{$0.name=="fios.platform.native.ingress.owners" && !$0.data.points.isEmpty})
        reply.nativeSampledAt=nil;reply.nativeSampleSequence=nil;diagnostics.completed(reply,receivedAt:now)
        telemetry.nativeIngress(diagnostics.ingressSample(now:now))
        let legacy=telemetry.collectMetrics()
        let legacyOwners=try XCTUnwrap(legacy.first{$0.name=="fios.platform.native.ingress.owners"})
        XCTAssertEqual((legacyOwners.data.points as! [DoublePointData]).first!.attributes["fios.sample.clock"],.string("receipt_only"))
        XCTAssertFalse(legacy.contains{$0.name=="fios.platform.native.ingress.source.time" && !$0.data.points.isEmpty})
    }

}
