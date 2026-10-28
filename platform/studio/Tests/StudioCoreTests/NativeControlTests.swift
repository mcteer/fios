import Foundation

func runNativeControlTests() throws {
    let instance=String(repeating:"07",count:16)
    let request=try NativeControlWire.request(operation:.pause,instance:instance,sequence:0)
    guard request.count==32,Array(request.prefix(6))==[70,73,67,57,2,1],Array(request.suffix(16))==Array(repeating:7,count:16) else {fatalError("Native control frame changed")}
    var reply=Data(repeating:0,count:64)
    reply.replaceSubrange(0..<4,with:Data("FIR9".utf8));reply[4]=2;reply[5]=1
    reply.replaceSubrange(8..<24,with:Data(repeating:7,count:16));reply[31]=1;reply[56]=1
    var sliced=Data(repeating:0,count:80)+reply;sliced.removeFirst(80)
    let rebased=try NativeControlWire.reply(sliced)
    guard rebased.pauseSequence==1 else {fatalError("Control decoding depended on backing-buffer offsets")}
    let value=try NativeControlWire.reply(reply)
    guard value.operation == .pause,value.status == .ok,value.instance==instance,value.pauseSequence==1,value.closed,value.owners==0,value.activity == .unknown else {fatalError("Private ingress status became native idle authority")}
    func reject(_ data:Data) {
        do {_ = try NativeControlWire.reply(data);fatalError("Malformed native private control accepted")}catch{}
    }
    for index in [0,4,5,6,7,56,57,58,63] {
        var wrong=reply;wrong[index]=255;reject(wrong)
    }
    var legacy=reply;legacy[4]=1;reject(legacy)
    var owner=reply;owner[5]=3;owner[58]=1;owner[62]=1
    let partial=try NativeControlWire.reply(owner)
    guard partial.ownerStreamOutcome == .ownerStreamsSynchronized,partial.synchronizedStreams==256,partial.activity == .unknown else {fatalError("Partial MLX barrier became global terminal authority")}
    var tooMany=owner;tooMany[63]=1;reject(tooMany)
    var failedProgress=owner;failedProgress[58]=5;reject(failedProgress)
    var openOwner=owner;openOwner[56]=0;openOwner[31]=0;reject(openOwner)
    var uncertainOwner=owner;uncertainOwner[57]=1;reject(uncertainOwner)
    var invalidOwner=owner;invalidOwner[6]=1;reject(invalidOwner)
    var liveOwner=owner;liveOwner[35]=1;liveOwner[39]=1;reject(liveOwner)
    do {_ = try NativeControlWire.request(operation:.ownerBarrier,instance:instance,sequence:0);fatalError("Ungated owner probe accepted")}catch{}
    var zero=reply;zero.replaceSubrange(8..<24,with:Data(repeating:0,count:16));reject(zero)
    var noPause=reply;noPause[31]=0;reject(noPause)
    var inconsistent=reply;inconsistent[35]=1;reject(inconsistent)
    var oversized=reply;oversized[34]=2;oversized[39]=1;reject(oversized)
    reject(reply.dropLast());reject(reply+Data([0]))
    for bad in ["",String(repeating:"0",count:32),String(repeating:"A",count:32),String(repeating:"a",count:31)] {
        do {_ = try NativeControlWire.request(operation:.pause,instance:bad,sequence:0);fatalError("Invalid source identity accepted")}catch{}
    }
    do {_ = try NativeControlWire.request(operation:.observe,instance:nil,sequence:1);fatalError("Observe accepted management sequence")}catch{}
    do {_ = try NativeControlWire.request(operation:.resume,instance:instance,sequence:0);fatalError("Zero resume accepted")}catch{}
    print("PASS: exact native control framing, source/one-use sequence bounds, unknown-only activity and malformed response refusal")
}
