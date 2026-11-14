import Foundation

// Trusted synthetic source only: no native coverage/enrollment is issued.
func observationFixture(host:String,endpoint:String,profile:String,manager:String,native:String,sequence:Int,sampled:Int,coverage:String)throws->[String:Any] {
    let meta=ActivityObservationMetadata(host:host,endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:native,
        sequence:Int64(sequence),sampledAt:Int64(sampled),nativeSequence:Int64(sequence),nativeSampledAt:Int64(sampled))
    let bytes=try ActivityObservationExport.encode(metadata:meta,coverage:NativeCoverage(rawValue:coverage) ?? .all_clients,sourceCoverage:.all_clients)
    var object=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
    object["coverage"]=coverage
    return object
}

enum DetailedObservationTests {
    static func run()throws {
        let host="fios-edge-a.lab",endpoint=String(repeating:"a",count:64),profile=String(repeating:"b",count:64),manager=UUID().uuidString.lowercased(),native="independently-bound-fixture"
        func meta(_ sequence:Int64=1,_ nativeSequence:Int64=1,_ sampled:Int64=1000,_ nativeTime:Int64=1000)->ActivityObservationMetadata {
            ActivityObservationMetadata(host:host,endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:native,
                sequence:sequence,sampledAt:sampled,nativeSequence:nativeSequence,nativeSampledAt:nativeTime)
        }
        func validator(_ coverage:NativeCoverage = .all_clients)->ObservationValidator {
            ObservationValidator(host:host,endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:native,sourceCoverage:coverage)
        }
        func encode(_ phases:NativePhaseCounts = .zero,local:[String]=[],uncertain:Bool=false)throws->Data {
            try ActivityObservationExport.encode(metadata:meta(),coverage:.all_clients,sourceCoverage:.all_clients,totals:phases,
                models:[NativeModelActivity(model:"fixture/model",resident:true,counts:phases)],localModels:local,localUncertain:uncertain)
        }
        func refuses(_ object:[String:Any])throws {
            let bytes=try JSONSerialization.data(withJSONObject:object)
            do {_=try ActivityObservationExport.decode(bytes);fatalError("Malformed detailed activity accepted")}catch{}
        }
        var idle=validator()
        guard try idle.accept(encode(),now:1000) == .idle else {fatalError("Detailed idle rejected")}
        var ceiling=validator(.unknown)
        guard try ceiling.accept(encode(),now:1000) == .unknown else {fatalError("Detailed frame raised source coverage")}
        for phase in [NativePhaseCounts(ingress:1,preparing:0,queued:0,active:0,responding:0),
                      NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0),
                      NativePhaseCounts(ingress:0,preparing:0,queued:1,active:0,responding:0),
                      NativePhaseCounts(ingress:0,preparing:0,queued:0,active:1,responding:0),
                      NativePhaseCounts(ingress:0,preparing:0,queued:0,active:0,responding:1)] {
            let view=try ActivityObservationExport.decode(encode(phase)).view
            precondition(view.state != .idle && view.state != .unknown && view.owners==1)
        }
        let response=NativePhaseCounts(ingress:0,preparing:0,queued:0,active:0,responding:1)
        let preparing=NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0)
        let cold=try ActivityObservationExport.encode(metadata:meta(),coverage:.all_clients,sourceCoverage:.all_clients,totals:preparing,
            models:[NativeModelActivity(model:"fixture/model",resident:false,counts:preparing)])
        let coldObject=try JSONSerialization.jsonObject(with:cold) as! [String:Any]
        guard coldObject["resident_model"] is NSNull,try ActivityObservationExport.decode(cold).view.state == .preparing else {fatalError("Preparation fabricated residency")}
        guard try ActivityObservationExport.decode(encode(response,local:["fixture/model"])).view.state == .active else {fatalError("Compatible local owner rejected")}
        for bytes in [try encode(local:["fixture/model"]),try encode(response,local:["other/model"]),try encode(response,local:["fixture/model"],uncertain:true)] {
            guard try ActivityObservationExport.decode(bytes).view.state == .unknown else {fatalError("Local ownership became idle/compatible without proof")}
        }
        var replay=validator()
        _=try replay.accept(encode(),now:1000)
        let repeated=try ActivityObservationExport.encode(metadata:meta(2,1,1001,1001),coverage:.all_clients,sourceCoverage:.all_clients)
        do {_=try replay.accept(repeated,now:1001);fatalError("New manager sequence hid repeated native sample")}catch ObservationError.replay{}
        let stale=try ActivityObservationExport.encode(metadata:meta(2,2,7001,1000),coverage:.all_clients,sourceCoverage:.all_clients)
        var oldNative=validator()
        do {_=try oldNative.accept(stale,now:7001);fatalError("Fresh manager hid stale native sample")}catch PolicyError.staleObservation{}
        let future=try ActivityObservationExport.encode(metadata:meta(1,1,1000,1500),coverage:.all_clients,sourceCoverage:.all_clients)
        var futureNative=validator()
        do {_=try futureNative.accept(future,now:499);fatalError("Manager timestamp hid future native sample")}catch PolicyError.staleObservation{}
        for (resourceTime,now) in [(Int64(0),Int64(6000)),(Int64(2001),Int64(1000))] {
            let context=ActivityObservationContext(sampledAt:resourceTime,pressure:.normal,thermal:.nominal)
            let bytes=try ActivityObservationExport.encode(metadata:meta(),coverage:.all_clients,sourceCoverage:.all_clients,context:context)
            var consumer=validator()
            do {_=try consumer.accept(bytes,now:now);fatalError("Fresh activity hid stale/future resource summary")}catch PolicyError.staleObservation{}
        }
        var gap=validator()
        _=try gap.accept(encode(),now:1000)
        let absent=ActivityObservationMetadata(host:host,endpointHash:endpoint,profileHash:profile,managerEpoch:manager,nativeEpoch:native,
            sequence:2,sampledAt:1001,nativeSequence:nil,nativeSampledAt:nil)
        let missing=try ActivityObservationExport.encode(metadata:absent,coverage:.unknown,sourceCoverage:.unknown)
        guard try gap.accept(missing,now:1001) == .unknown else {fatalError("Source outage became idle")}
        let reset=try ActivityObservationExport.encode(metadata:meta(3,1,1002,1002),coverage:.all_clients,sourceCoverage:.all_clients)
        do {_=try gap.accept(reset,now:1002);fatalError("Unknown source gap reset native replay tracking")}catch ObservationError.replay{}
        let entries=(0..<64).map {NativeModelActivity(model:String($0)+String(repeating:"\\",count:1000),resident:false,counts:.zero)}
        let bounded=try ActivityObservationExport.encode(metadata:meta(),coverage:.all_clients,sourceCoverage:.all_clients,models:entries)
        guard bounded.count<=65536,try ActivityObservationExport.decode(bounded).reason == .observation_too_large else {fatalError("Large detailed export truncated into idle")}
        var base=try JSONSerialization.jsonObject(with:encode()) as! [String:Any]
        var changed=base;changed["activity"]="active";try refuses(changed)
        changed=base;changed["outstanding_owners"]=true;try refuses(changed)
        let normal=String(decoding:try encode(),as:UTF8.self)
        let floating=normal.replacingOccurrences(of:"\"native_sequence\":1",with:"\"native_sequence\":1.0")
        precondition(floating != normal)
        do {_=try ActivityObservationExport.decode(Data(floating.utf8));fatalError("Floating native sequence was coerced")}catch{}
        changed=base;changed["source_age_ms"]=1;try refuses(changed)
        changed=base;changed["local_ownership"]=["unresolved_count":1,"uncertain":false,"blocked":false];try refuses(changed)
        changed=base;changed["resources"]=["sampled_at":NSNull(),"pressure":"normal","thermal":"nominal"];try refuses(changed)
        let duplicate=base["models"] as! [[String:Any]]
        changed=base;changed["models"]=duplicate+duplicate;try refuses(changed)
        base["version"]=1
        base=base.filter {ActivityObservationExport.legacyFields.contains($0.key)}
        do {_=try ActivityObservationExport.decode(JSONSerialization.data(withJSONObject:base),allowLegacyUnsupported:true);fatalError("Legacy all-client sample bypassed detailed contract")}catch{}
        print("PASS: detailed bounded source/manager epochs/sequences/ages, phase coherence, local ownership overlays, independent coverage and overflow-to-unknown; synthetic source only")
    }
}
