import Foundation

private struct KernelVMFixture:VMResourceReading {
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        VMKernelSample(sampledAt:HostResources.nowMilliseconds(),total:16<<30,free:8<<30,bootHash:String(repeating:"b",count:64))
    }
}
private final class InventoryVMFixture:NativeVMInventoryReading,@unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    let change:Bool
    let partial:Bool
    init(change:Bool=false,partial:Bool=false) {self.change=change;self.partial=partial}
    func capture()throws->NativeVMInventory {
        lock.lock();defer {lock.unlock()};count+=1
        return NativeVMInventory(configuredCap:count>1 && change ? 10<<30 : 12<<30,sampledAt:HostResources.nowMilliseconds(),machineIDs:partial ? [String(repeating:"c",count:64)] : [])
    }
}
func runNativeVMInventoryTests() throws {
    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1),id=String(repeating:"e",count:64)
    let collector=VMEnvelopeReader(kernel:KernelVMFixture(),inventory:InventoryVMFixture(),nativeProfileHash:String(repeating:"a",count:64),physical:32<<30)
    let sample=try collector.read(configuration:configuration,id:id,leaseUntil:HostResources.nowMilliseconds()+30000)
    guard let envelope=sample.envelope,VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:HostResources.nowMilliseconds())==4<<30 else {fatalError("Complete VM collector lost envelope")}
    for inventory in [InventoryVMFixture(change:true),InventoryVMFixture(partial:true)] {
        let unsafe=VMEnvelopeReader(kernel:KernelVMFixture(),inventory:inventory,nativeProfileHash:String(repeating:"a",count:64),physical:32<<30)
        do {_=try unsafe.read(configuration:configuration,id:id,leaseUntil:HostResources.nowMilliseconds()+30000);fatalError("Changed/partial native VM configuration accepted")}catch RuntimeError.identity {}
    }
    print("PASS: composed VM collector brackets kernel read with native inventory/config, exports conservative envelope and rejects changed cap/unverified machine coverage")
}
