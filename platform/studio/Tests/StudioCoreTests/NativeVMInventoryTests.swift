import Foundation
import CryptoKit

private struct KernelVMFixture:VMResourceReading {
    var stamp:Int64?=nil
    func read(configuration:SandboxConfiguration,id:String,leaseUntil:Int64)throws->VMKernelSample {
        VMKernelSample(sampledAt:stamp ?? HostResources.nowMilliseconds(),total:16<<30,free:8<<30,bootHash:String(repeating:"b",count:64))
    }
}
private final class InventoryVMFixture:NativeVMInventoryReading,@unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    let change:Bool
    let partial:Bool
    let stamps:[Int64]
    init(change:Bool=false,partial:Bool=false,stamps:[Int64]=[]) {self.change=change;self.partial=partial;self.stamps=stamps}
    var captures:Int {lock.lock();defer {lock.unlock()};return count}
    func capture(checkpoint:()throws->Void)throws->NativeVMInventory {
        lock.lock();defer {lock.unlock()};count+=1
        return NativeVMInventory(configuredCap:count>1 && change ? 10<<30 : 12<<30,sampledAt:stamps.indices.contains(count-1) ? stamps[count-1]:HostResources.nowMilliseconds(),machineIDs:partial ? [String(repeating:"c",count:64)] : [])
    }
}
private final class InventoryClockFixture:@unchecked Sendable {
    private let lock=NSLock()
    private var stamps:[Int64]
    init(_ stamps:[Int64]) {self.stamps=stamps}
    func next()->Int64 {lock.lock();defer {lock.unlock()};return stamps.isEmpty ? Int64.max:stamps.removeFirst()}
}
func runNativeVMInventoryTests() throws {
    guard let path=ProcessInfo.processInfo.environment["FIOS_PLATFORM_VM_INVENTORY_FIXTURE"] else {fatalError("Missing finite VM inventory CLI")}
    let hash=SHA256.hash(data:try Data(contentsOf:URL(fileURLWithPath:path))).map {String(format:"%02x",$0)}.joined()
    let executable=try VerifiedExecutable(path:path,sha256:hash)
    let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:home,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:home)}
    let reader=VerifiedVMInventory(executable:executable,home:home.path)
    try AtomicState.write(Data("Stopped\n".utf8),to:home.appendingPathComponent("status"))
    do {_=try reader.capture();fatalError("Stopped VM produced a native capacity inventory")}catch RuntimeError.launch {}
    guard try String(contentsOf:home.appendingPathComponent("calls"),encoding:.utf8)=="status\n" else {fatalError("Stopped VM still reached config/list")}
    try AtomicState.write(Data("Running\n".utf8),to:home.appendingPathComponent("status"))
    try AtomicState.write(Data(),to:home.appendingPathComponent("calls"))
    let observed=try reader.capture()
    guard observed.configuredCap==12<<30,observed.machineIDs.isEmpty,
          try String(contentsOf:home.appendingPathComponent("calls"),encoding:.utf8)=="status\nconfig\nlist\n" else {fatalError("Running inventory metadata sequence changed")}

    let configuration=try SandboxConfiguration(job:UUID().uuidString.lowercased(),nonce:String(repeating:"c",count:64),image:"sha256:"+String(repeating:"d",count:64),memory:512<<20,cpus:1),id=String(repeating:"e",count:64)
    let calls=home.appendingPathComponent("calls")
    try Data().write(to:calls)
    var publicationChecks=0
    do {
        _=try reader.capture(checkpoint:{
            publicationChecks+=1
            if publicationChecks==2 {throw RuntimeError.deadline}
        })
        fatalError("VM inventory published after its inherited cutoff")
    } catch RuntimeError.deadline {}
    guard publicationChecks==2,try String(contentsOf:calls,encoding:.utf8)=="status\n" else {
        fatalError("Expired VM inventory started a dependent native command")
    }
    let collector=VMEnvelopeReader(kernel:KernelVMFixture(),inventory:InventoryVMFixture(),nativeProfileHash:String(repeating:"a",count:64),physical:32<<30)
    let sample=try collector.read(configuration:configuration,id:id,leaseUntil:HostResources.nowMilliseconds()+30000)
    guard let envelope=sample.envelope,VMResources.remaining(envelope,expectedRuntimeHash:envelope.runtimeHash,now:HostResources.nowMilliseconds())==4<<30 else {fatalError("Complete VM collector lost envelope")}
    for inventory in [InventoryVMFixture(change:true),InventoryVMFixture(partial:true)] {
        let unsafe=VMEnvelopeReader(kernel:KernelVMFixture(),inventory:inventory,nativeProfileHash:String(repeating:"a",count:64),physical:32<<30)
        do {_=try unsafe.read(configuration:configuration,id:id,leaseUntil:HostResources.nowMilliseconds()+30000);fatalError("Changed/partial native VM configuration accepted")}catch RuntimeError.identity {}
    }
    let stamp=HostResources.nowMilliseconds()-100
    for stamps in [[stamp+1,stamp+2],[stamp-2,stamp-1],[stamp+1,stamp-1]] {
        let unsafe=VMEnvelopeReader(kernel:KernelVMFixture(stamp:stamp),inventory:InventoryVMFixture(stamps:stamps),nativeProfileHash:String(repeating:"a",count:64),physical:32<<30)
        do {_=try unsafe.read(configuration:configuration,id:id,leaseUntil:stamp+30000);fatalError("Unbracketed kernel sample crossed the collector boundary")}catch RuntimeError.identity {}
    }
    for (checkpoints,expectedCaptures) in [([2000],0),([1000,2000],1),([1000,1001,2000],1)] {
        let clock=InventoryClockFixture(checkpoints.map(Int64.init)),inventory=InventoryVMFixture(stamps:[1000,1002])
        let reader=VMEnvelopeReader(kernel:KernelVMFixture(stamp:1001),inventory:inventory,nativeProfileHash:String(repeating:"a",count:64),physical:32<<30,wallClock:{clock.next()},uptime:{1})
        do {_=try reader.read(configuration:configuration,id:id,leaseUntil:2000);fatalError("Expired lease accepted at inventory checkpoint")}catch RuntimeError.deadline {}
        guard inventory.captures==expectedCaptures else {fatalError("Inventory executed after observed lease expiry")}
    }
    let rollback=InventoryClockFixture([1000,999]),rolledInventory=InventoryVMFixture(stamps:[1000])
    let rolled=VMEnvelopeReader(kernel:KernelVMFixture(stamp:1000),inventory:rolledInventory,nativeProfileHash:String(repeating:"a",count:64),physical:32<<30,wallClock:{rollback.next()},uptime:{1})
    do {_=try rolled.read(configuration:configuration,id:id,leaseUntil:2000);fatalError("Wall rollback retained VM observation")}catch RuntimeError.identity {}
    guard rolledInventory.captures==1 else {fatalError("Wall rollback reached another inventory capture")}
    let steady=InventoryClockFixture([1000,1000,1001,6001]),slowInventory=InventoryVMFixture(stamps:[1000,1002])
    let slow=VMEnvelopeReader(kernel:KernelVMFixture(stamp:1001),inventory:slowInventory,nativeProfileHash:String(repeating:"a",count:64),physical:32<<30,wallClock:{1001},uptime:{Double(steady.next())/1000})
    do {_=try slow.read(configuration:configuration,id:id,leaseUntil:2000);fatalError("Over-budget kernel read retained VM observation")}catch RuntimeError.deadline {}
    guard slowInventory.captures==1 else {fatalError("Over-budget read reached post-inventory")}
    let ageClock=InventoryClockFixture([1000,1001,6001]),ageInventory=InventoryVMFixture(stamps:[1000,6001])
    let aged=VMEnvelopeReader(kernel:KernelVMFixture(stamp:1001),inventory:ageInventory,nativeProfileHash:String(repeating:"a",count:64),
        physical:32<<30,wallClock:{ageClock.next()},uptime:{1})
    do {_=try aged.read(configuration:configuration,id:id,leaseUntil:12000);fatalError("Expired first inventory produced a VM envelope")}
    catch RuntimeError.identity {}
    guard ageInventory.captures==1 else {fatalError("First inventory age did not stop a second capture")}
    print("PASS: composed VM collector brackets kernel read with native inventory/config, exports conservative envelope and rejects changed cap/unverified machine coverage")
}
