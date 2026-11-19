import Foundation

// A narrow source-consistency result for the original still-unconsumed CPU
// preparation. Not a NativeSnapshot, capacity/dispatch grant or terminal proof.
// The independent reviewed all-client source ceiling is mandatory; neither
// claimability flags nor an authenticated partial frame can raise it.
struct NativeOwnedPreparation:Sendable {
    let target:String
    let registryReadyModel:String?
    let sourceSequence:UInt64
    let registryGeneration:UInt64
}
enum NativeOwnedPreparationCoherence {
    static func evaluate(registration:VerifiedNativePreparationRegistration,lineage:NativeRequestLineageSample,
                         activity:NativePrimaryActivitySample,sourceCoverage:NativeCoverage = .unknown,now:Int64)->NativeOwnedPreparation? {
        guard sourceCoverage == .all_clients,registration.leaseWindowIsCurrent(now:now),
              let registry=activity.registry,registry.primary.phaseVersion==4,
              samePeer(registration.peer,lineage.peer),samePeer(registration.peer,activity.peer) else {return nil}
        do {try registry.validate();try lineage.lineage.validate()} catch {return nil}
        let ack=registration.acknowledgement,root=lineage.lineage,primary=registry.primary
        guard root.instance==ack.instance,root.correlationID==ack.correlationID,root.rootSequence==ack.rootSequence,
              root.found,!root.uncertain,root.owners==1,root.references==1,root.ingress==0,root.preparing==1,root.active==0,root.responding==0,
              root.operations.map({$0.queued==0 && $0.active==0}) ?? true,
              root.sampleSequence>ack.sampleSequence,primary.instance==ack.instance,primary.sampleSequence>root.sampleSequence,
              !primary.uncertain,!registry.transitioning,primary.owners==1,primary.ingress==0,primary.preparing==1,
              primary.queued==0,primary.active==0,primary.responding==0,
              lineage.sampledAt>=registration.sample.requestedAt,lineage.sampledAt<=activity.receivedAt,
              activity.receivedAt>=registration.verifiedAt,activity.receivedAt<=now,
              now-lineage.sampledAt<=5000,now-activity.receivedAt<=5000,
              let captured=primary.sampledAt,captured>=max(lineage.sampledAt,root.sourceCapturedAt ?? lineage.sampledAt),
              captured<=activity.receivedAt,now-captured<=5000,
              let target=registry.models.first(where:{$0.model.utf8.elementsEqual(ack.model.utf8)}),target.claimable==true,
              target.counts==NativePhaseCounts(ingress:0,preparing:1,queued:0,active:0,responding:0),
              registry.models.allSatisfy({!$0.transitioning && !$0.uncertain && ($0.model.utf8.elementsEqual(ack.model.utf8) || $0.counts == .zero)}) else {return nil}
        let ready=registry.models.filter(\.readyDeclared)
        guard ready.count<=1 else {return nil}
        // An idle registry-declared model may differ from the original target
        // during on-demand replacement. Do not relabel it or export global
        // idle/eligibility; native generation-bound consumption still decides.
        return NativeOwnedPreparation(target:ack.model,registryReadyModel:ready.first?.model,
            sourceSequence:primary.sampleSequence,registryGeneration:registry.registryGeneration)
    }
    private static func samePeer(_ a:NativeControlPeer,_ b:NativeControlPeer)->Bool {
        a.pid==b.pid && a.start==b.start && a.executable.sha256==b.executable.sha256 && a.executable.path.utf8.elementsEqual(b.executable.path.utf8)
    }
}
