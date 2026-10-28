import Foundation
import CryptoKit

struct VMMachineKernel:Sendable {
    let identityHash:String
    let bootHash:String
    let sampledAt:Int64
}
// Constructed only by a trusted enrolled collector, never decoded from task
// JSON. Inventory must bracket the kernel read; every running machine needs
// a fresh same-kernel binding. Empty inventory is not an invented zero load.
struct VMEnvelopeContext:Sendable {
    let nativeProfileHash:String
    let expectedBootHash:String
    let configuredCap:UInt64
    let physical:UInt64
    let configurationSampledAt:Int64
    let topologyBeforeAt:Int64
    let topologyAfterAt:Int64
    let machineIDsBefore:Set<String>
    let machineIDsAfter:Set<String>
    let machineKernels:[VMMachineKernel]
}

enum VMEnvelope {
    static func observation(_ sample:VMKernelSample,context:VMEnvelopeContext,now:Int64)->VMResourceObservation? {
        func hash(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})}
        func fresh(_ value:Int64)->Bool {
            now>=0 && now<=ActivityPolicy.maximumTimestamp && value>=0 && value<=ActivityPolicy.maximumTimestamp && (-1000...5000).contains(now-value)
        }
        guard hash(context.nativeProfileHash),hash(context.expectedBootHash),sample.bootHash==context.expectedBootHash,
              context.physical>0,context.physical<=UInt64(ActivityPolicy.maximumTimestamp),context.configuredCap>0,context.configuredCap<=context.physical,
              sample.total>0,sample.total<=context.physical,sample.free<=sample.total,
              context.machineIDsBefore.count<=32,context.machineIDsBefore==context.machineIDsAfter,
              context.machineIDsBefore.allSatisfy(hash),context.machineKernels.count==context.machineIDsBefore.count,
              Set(context.machineKernels.map(\.identityHash))==context.machineIDsBefore,
              context.machineKernels.allSatisfy({hash($0.identityHash) && $0.bootHash==sample.bootHash && fresh($0.sampledAt)}),
              fresh(sample.sampledAt),fresh(context.configurationSampledAt),fresh(context.topologyBeforeAt),fresh(context.topologyAfterAt),
              context.topologyBeforeAt<=sample.sampledAt+1000,context.topologyAfterAt>=sample.sampledAt-1000 else {return nil}
        let identity=["fios-vm-envelope-v1",context.nativeProfileHash,context.expectedBootHash,String(context.configuredCap),String(context.physical)]+context.machineIDsBefore.sorted()
        let runtimeHash=SHA256.hash(data:Data(identity.joined(separator:"\0").utf8)).map {String(format:"%02x",$0)}.joined()
        let earliest=([sample.sampledAt,context.configurationSampledAt,context.topologyBeforeAt,context.topologyAfterAt]+context.machineKernels.map(\.sampledAt)).min()!
        let value=VMResourceObservation(runtimeHash:runtimeHash,sampledAt:earliest,configuredCap:context.configuredCap,total:sample.total,free:sample.free,allVMConsumersCovered:true)
        guard VMResources.remaining(value,expectedRuntimeHash:runtimeHash,now:now) != nil else {return nil}
        return value
    }
}
