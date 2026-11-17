import Foundation

func runNativeRequestEventsTests()throws {
    let file=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/platform/native-request-events.json")
    guard let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:String],
          let instance=fixture["instance"],let correlation=fixture["correlation_id"],let root=fixture["root"].flatMap(UInt64.init),
          let configured=fixture["configured"].flatMap({Data(base64Encoded:$0)}),
          let unavailable=fixture["unavailable"].flatMap({Data(base64Encoded:$0)}) else {throw NativeControlError.invalid}
    let observed=try NativeRequestEventsWire.reply(configured,instance:instance,correlationID:correlation,rootSequence:root)
    guard observed.identityKnown,observed.sdkInitialized,!observed.sourceUncertain,let host=observed.host,
          host.originated>0,host.retired==host.originated,host.pending==0,host.historyRetained,!host.uncertain else {throw NativeControlError.invalid}
    let missing=try NativeRequestEventsWire.reply(unavailable,instance:instance,correlationID:correlation,rootSequence:root)
    guard missing.identityKnown,!missing.sdkInitialized,missing.sourceUncertain,missing.host==nil,missing.metal==nil else {throw NativeControlError.invalid}
    guard let gpuFrame=fixture["gpu_configured"].flatMap({Data(base64Encoded:$0)}) else {throw NativeControlError.invalid}
    let gpu=try NativeRequestEventsWire.reply(gpuFrame,instance:instance,correlationID:correlation,rootSequence:root)
    guard gpu.identityKnown,gpu.sdkInitialized,!gpu.sourceUncertain,let metal=gpu.metal,
          metal.originated>0,metal.retired==metal.originated,metal.pending==0,metal.historyRetained,!metal.uncertain else {throw NativeControlError.invalid}
    let request=try NativeRequestEventsWire.request(instance:instance,correlationID:correlation,rootSequence:root)
    guard request.count==64,request.prefix(4).elementsEqual("FIO9".utf8) else {throw NativeControlError.invalid}
    print("PASS: genuine CPU/GPU native SDK event frames preserve original-root counts and unavailable SDK metadata stays absent")
}
