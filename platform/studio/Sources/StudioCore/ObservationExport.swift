import Foundation
import CoreFoundation

enum ObservationError:Error { case invalid, identity, replay, trackingLimit }

// Lives with one enrolled consumer. Both expected generations come from
// separate trusted fresh enrollment, NEVER from the frame being checked.
// Reconnect/health/new timestamps cannot mint a binding or clear old ownership.
// Generation/transport proof and persistence remain separate integration.
struct ObservationValidator {
    let host:String
    let endpointHash:String
    let profileHash:String
    let managerEpoch:String
    let nativeEpoch:String
    let sourceCoverage:NativeCoverage
    private var fenced=false
    private var sequence:UInt64=0
    private var sampled:Int64 = -1
    private var nativeSequence:Int64=0
    private var nativeSampled:Int64 = -1
    private var previousNow:Int64 = -1
    init(host:String,endpointHash:String,profileHash:String,managerEpoch:String,nativeEpoch:String,
         sourceCoverage:NativeCoverage = .unknown) {
        self.host=host;self.endpointHash=endpointHash;self.profileHash=profileHash
        self.managerEpoch=managerEpoch;self.nativeEpoch=nativeEpoch
        self.sourceCoverage=sourceCoverage
    }
    mutating func accept(_ data:Data,now:Int64) throws -> HostActivity {
        guard !fenced,WireScalar.host(host),WireScalar.sha256(endpointHash),WireScalar.sha256(profileHash),
              WireScalar.uuid(managerEpoch),!nativeEpoch.isEmpty,nativeEpoch.utf8.count<=128 else {throw ObservationError.identity}
        guard (0...WireScalar.maximumTimestamp).contains(now) else {throw ObservationError.invalid}
        guard now>=previousNow else {
            fenced=true
            throw ObservationError.replay
        }
        // Remember trusted local time even when a frame is malformed/stale.
        // A rejected frame must not hide an observed wall-clock rollback.
        previousNow=now
        let decoded=try ActivityObservationExport.decode(data,allowLegacyUnsupported:true)
        let frame=decoded.metadata
        guard frame.host==host,frame.endpointHash==endpointHash,frame.profileHash==profileHash,
              Data(frame.nativeEpoch.utf8)==Data(nativeEpoch.utf8),frame.managerEpoch==managerEpoch else {
            fenced=true;throw ObservationError.identity
        }
        guard frame.sampledAt>=sampled,UInt64(frame.sequence)>sequence else {throw ObservationError.replay}
        func fresh(_ time:Int64)throws {
            guard (-1000...5000).contains(now-time) else {throw PolicyError.staleObservation}
        }
        try fresh(frame.sampledAt)
        if let time=frame.nativeSampledAt,let counter=frame.nativeSequence {
            try fresh(time)
            guard time>=nativeSampled,counter>nativeSequence else {throw ObservationError.replay}
        }
        if let time=decoded.resourceSampledAt {try fresh(time)}
        sequence=UInt64(frame.sequence);sampled=frame.sampledAt
        if let time=frame.nativeSampledAt,let counter=frame.nativeSequence {nativeSampled=time;nativeSequence=counter}
        guard sourceCoverage == .all_clients,decoded.view.coverage == .all_clients else {return .unknown}
        switch decoded.view.state {
        case .idle:return .idle
        case .preparing:return .preparing
        case .queued,.active:
            guard let model=decoded.view.model else {return .unknown};return .busy(model:model)
        case .unknown:return .unknown
        }
    }
}
