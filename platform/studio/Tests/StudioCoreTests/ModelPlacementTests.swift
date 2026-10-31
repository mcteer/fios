import Foundation

func runModelPlacementTests() throws {
    let model="mlx-community/gemma-4-e4b-it-4bit"
    for host in ["fios-core","fios-core.lab"] {
        guard ModelPlacementPolicy.respectsCoreSmallAssignment(host:host,canonical:model,native:model) else {throw PolicyError.invalidObservation}
    }
    for host in ["fios-edge-a.lab","fios-edge-b.lab"] {
        guard !ModelPlacementPolicy.respectsCoreSmallAssignment(host:host,canonical:model,native:model),
              !ModelPlacementPolicy.respectsCoreSmallAssignment(host:host,canonical:"fixture/alias",native:model),
              ModelPlacementPolicy.respectsCoreSmallAssignment(host:host,canonical:"fixture/reviewed-model",native:"fixture/reviewed-model") else {throw PolicyError.invalidObservation}
    }
    // Plain policy metadata only; core placement does not supply native proof.
    let unknown=NativeSnapshot(host:"fios-core.lab",endpointHash:String(repeating:"a",count:64),
        nativeEpoch:"fixture-native",sequence:1,sampledAt:1000,allClientLifecycleCoverage:false,
        residentModel:nil,outstandingOwners:0,loading:false)
    let eligible=try ActivityPolicy.permits(target:model,snapshot:unknown,now:1000)
    guard !eligible else {throw PolicyError.invalidObservation}
    print("PASS: core-only small-model placement applies to canonical and native mappings; other admission checks remain separate")
}
