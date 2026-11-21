import Foundation

func runNativeRequestHandoffTests()throws {
    let instance=String(repeating:"1",count:32),id=String(repeating:"a",count:64),root=UInt64.max
    let request=try NativeHandoffWire.request(operation:.register,instance:instance,correlationID:id)
    guard request.count==64,request.prefix(4)==Data("FIJ9".utf8),request[5]==0,request[56..<64].allSatisfy({$0==0}) else {fatalError("Registration request expanded authority")}
    func frame(_ operation:NativeHandoffOperation,_ state:NativeHandoffState,_ uncertain:Bool=false)->Data {
        var bytes=Data(repeating:0,count:88);bytes.replaceSubrange(0..<4,with:Data("FIK9".utf8));bytes[4]=1;bytes[6]=state.rawValue;bytes[7]=uncertain ? 1:0
        bytes.replaceSubrange(8..<56,with:request[8..<56]);bytes[63]=1;bytes[64..<72]=Data(repeating:255,count:8);bytes[72]=operation.rawValue;return bytes
    }
    let pending=try NativeHandoffWire.reply(frame(.register,.pending),operation:.register,instance:instance,correlationID:id)
    guard pending.rootSequence==root,pending.state == .pending,!pending.uncertain else {fatalError("Registration lost original full-width root")}
    for state in [NativeHandoffState.cancelled,.handedOff,.unknown] {
        let result=try NativeHandoffWire.reply(frame(.cancel,state),operation:.cancel,instance:instance,correlationID:id,rootSequence:root)
        guard result.state==state,result.rootSequence==root else {fatalError("Cancellation conflated consumed/unknown with cancellation")}
    }
    func refuses(_ bytes:Data,_ operation:NativeHandoffOperation = .register) {
        do{_=try NativeHandoffWire.reply(bytes,operation:operation,instance:instance,correlationID:id,rootSequence:operation == .register ? 0:root)}catch{return};fatalError("Malformed handoff metadata accepted")
    }
    for index in [0,4,5,6,7,8,24,72,73] {var bad=frame(.register,.pending);bad[index]=4;refuses(bad)}
    refuses(frame(.register,.cancelled));refuses(frame(.cancel,.pending),.cancel);refuses(frame(.register,.pending,true))
    var sliced=Data([9]);sliced.append(frame(.register,.pending));sliced.removeFirst()
    _=try NativeHandoffWire.reply(sliced,operation:.register,instance:instance,correlationID:id)
    print("PASS: native original-root handoff metadata, full-width identity, distinct cancelled/handed-off/unknown and strict operation binding; no native admission/completion grant")
}
