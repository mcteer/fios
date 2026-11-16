import Foundation
func runRegistryActivityWireTests(nativeFrame:String?=nil)throws {
    let instance=String(repeating:"07",count:16),request=try NativeRegistryActivityWire.request(instance:instance)
    guard request.count==32,request.prefix(5)==Data("FIA9".utf8)+Data([3]) else {fatalError("Coupled activity request version changed")}
    var frame=Data(repeating:0,count:67168);frame.replaceSubrange(0..<4,with:Data("FIT9".utf8));frame[4]=3
    frame.replaceSubrange(8..<24,with:Data(repeating:7,count:16));frame[31]=2;frame[38]=3;frame[39]=232;frame[47]=7
    frame[51]=1;frame[63]=1;frame[75]=1;frame[97]=9;frame[98]=1;frame[107]=1
    frame.replaceSubrange(120..<129,with:Data("fixture/a".utf8))
    let value=try NativeRegistryActivityWire.reply(frame,instance:instance,after:1)
    guard value.registryGeneration==7,value.primary.queued==1,value.primary.owners==1,value.models.count==1,value.models[0].readyDeclared,
          value.conservativeActivity().coverage == .unknown,value.conservativeActivity().state == .unknown,!value.conservativeActivity().permits(target:"fixture/a") else {fatalError("Registry declaration gained idle/admission authority")}
    let request4=try NativeRegistryActivityWire.request(instance:instance,version:4)
    guard request4[4]==4,value.models[0].claimable==nil else {fatalError("Legacy metadata acquired claimability")}
    var frame4=frame;frame4[4]=4;frame4[99]=4
    let available=try NativeRegistryActivityWire.reply(frame4,instance:instance)
    guard available.primary.phaseVersion==4,available.models[0].claimable==true,
          available.conservativeActivity().coverage == .unknown,available.conservativeActivity().state == .unknown else {fatalError("Claimability became native authority")}
    var unloaded=frame4;unloaded[98]=0
    guard try NativeRegistryActivityWire.reply(unloaded,instance:instance).models[0].claimable==true else {fatalError("Advertised unloaded target became unavailable")}
    func invalid(_ data:Data)throws {do {_=try NativeRegistryActivityWire.reply(data,instance:instance);fatalError("Invalid coupled frame accepted")}catch NativeControlError.invalid {}}
    for offset in [4,5,6,7,76,77,95,98,99,116,119,129,67167] {var bad=frame;bad[offset]=255;try invalid(bad)}
    var readyUnavailable=frame4;readyUnavailable[99]=0;try invalid(readyUnavailable)
    var transitionAvailable=frame4;transitionAvailable[99]=5;transitionAvailable[76]=1;try invalid(transitionAvailable)
    var uncertainAvailable=frame4;uncertainAvailable[99]=6;uncertainAvailable[7]=1;try invalid(uncertainAvailable)
    var legacyFlag=frame;legacyFlag[99]=4;try invalid(legacyFlag)
    var generation=frame;generation.replaceSubrange(40..<48,with:Data(repeating:255,count:8));try invalid(generation)
    var excessive=frame;excessive[75]=65;try invalid(excessive)
    var inconsistent=frame;inconsistent[107]=2;try invalid(inconsistent)
    var rowUncertainty=frame;rowUncertainty[99]=2;try invalid(rowUncertainty)
    try invalid(Data(frame.dropLast()))
    do {_=try NativeRegistryActivityWire.reply(frame,instance:instance,after:2);fatalError("Coupled sequence replay accepted")}catch NativeControlError.invalid {}
    var multi=frame;multi[75]=2
    let second=96+1048
    multi.replaceSubrange(second..<(second+1048),with:frame[96..<(96+1048)])
    multi.replaceSubrange((second+4)..<(second+20),with:Data(repeating:0,count:16))
    try invalid(multi)
    multi.replaceSubrange((second+24)..<(second+33),with:Data("fixture/b".utf8))
    let multiple=try NativeRegistryActivityWire.reply(multi,instance:instance)
    guard multiple.models.filter(\.readyDeclared).count==2,multiple.primary.models.count==1,multiple.conservativeActivity().state == .unknown else {fatalError("Multiple declarations were collapsed into one idle model")}
    var empty=frame;empty.replaceSubrange(40..<67168,with:Data(repeating:0,count:67168-40))
    let absent=try NativeRegistryActivityWire.reply(empty,instance:instance)
    guard absent.models.isEmpty,absent.registryGeneration==0,absent.conservativeActivity().state == .unknown else {fatalError("Empty declarations became verified idle")}
    let peer=NativeControlPeer(pid:42,start:100,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"a",count:64)))
    var diagnostic=NativePrimaryActivityDiagnostics(configured:true)
    diagnostic.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1000,registry:value),expectedInstance:instance,now:1000)
    let summary=diagnostic.summary(now:1000)
    guard summary["state"] as? String=="received",summary["registry_generation"] as? UInt64==7,summary["registry_ready_declared"] as? Int==1,
          summary["coherent_activity"] as? String=="unknown",summary["authority"] as? Bool==false else {fatalError("Coupled diagnostic lost generation or gained authority")}
    var backwards=frame;backwards[31]=3;backwards[47]=6
    diagnostic.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1000,registry:try NativeRegistryActivityWire.reply(backwards,instance:instance)),expectedInstance:instance,now:1000)
    guard diagnostic.summary(now:1000)["state"] as? String=="fenced" else {fatalError("Registry generation rollback accepted")}
    var missing=NativePrimaryActivityDiagnostics(configured:true)
    missing.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1000,activity:value.primary),expectedInstance:instance,now:1000)
    guard missing.summary(now:1000)["state"] as? String=="unavailable" else {fatalError("Missing coupled metadata became a successful sample")}
    var sticky=NativePrimaryActivityDiagnostics(configured:true),uncertain=frame
    uncertain[7]=1;uncertain[99]=2
    sticky.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1000,registry:try NativeRegistryActivityWire.reply(uncertain,instance:instance)),expectedInstance:instance,now:1000)
    var clear=frame;clear[31]=3
    sticky.completed(NativePrimaryActivitySample(peer:peer,receivedAt:1000,registry:try NativeRegistryActivityWire.reply(clear,instance:instance)),expectedInstance:instance,now:1000)
    guard sticky.summary(now:1000)["state"] as? String=="fenced",sticky.summary(now:1000)["retained_uncertainty"] as? Bool==true else {fatalError("New registry state cleared old uncertainty")}
    if let nativeFrame {
        let native=try NativeRegistryActivityWire.reply(Data(contentsOf:URL(fileURLWithPath:nativeFrame)),instance:String(repeating:"83",count:16))
        guard native.registryGeneration==7,native.models.count==1,native.models[0].model=="fixture/a",native.primary.queued==1,native.models[0].readyDeclared else {fatalError("Actual native coupled frame disagreed with manager")}
    }
}
