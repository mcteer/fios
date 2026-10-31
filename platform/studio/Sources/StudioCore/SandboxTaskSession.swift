import Foundation
import CryptoKit

// A finite, already-validated input and framed runtime session. The surrounding
// controller owns admission, owner lease, exact runtime identity, model scope,
// artifact service and cleanup. This class cannot create jobs/containers.
final class SandboxTaskSession {
    private var source:Data
    private let hash:String
    private let length:Int
    private let deadline:Int64
    private var uploadBegan:Int64?
    private var stage=0,offset=0,index=0
    private var previous:Int64
    private var stream:SandboxStream
    private var responses:[Data]=[]
    private var responseBytes=0
    private(set) var terminal=false
    private(set) var revoked=false
    var uploaded:Bool {stage==3}
    init(source:Data,deadline:Int64,now:Int64) throws {
        guard source.count<=4<<20,String(data:source,encoding:.utf8) != nil,
              now>=0,now<=ActivityPolicy.maximumTimestamp-1800000,deadline>now,deadline<=now+1800000 else {throw ControlError.invalid_request}
        self.source=source;length=source.count;self.deadline=deadline;previous=now
        hash=SHA256.hash(data:source).map {String(format:"%02x",$0)}.joined()
        stream=try SandboxStream(now:now)
    }
    private func framed(_ fields:[String:Any]) throws -> Data {
        let body=try JSONSerialization.data(withJSONObject:fields.merging(["version":1]) {_,new in new})
        guard (1...65536).contains(body.count) else {throw ControlError.invalid_request}
        let n=UInt32(body.count)
        return Data([UInt8(n>>24),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)])+body
    }
    func response(_ body:Data) throws {
        guard !revoked,!terminal else {throw ControlError.invalid_request}
        try StrictJSON.validate(body,maximum:65536)
        guard let fields=try JSONSerialization.jsonObject(with:body) as? [String:Any],
              let kind=fields["type"] as? String,["model.delta","model.done","artifact.saved","lease.renew"].contains(kind) else {throw ControlError.invalid_request}
        let bytes=try framed(fields)
        guard responses.count<64,responseBytes+bytes.count<=256<<10 else {throw RuntimeError.outputLimit}
        responses.append(bytes);responseBytes+=bytes.count
    }
    func saved(id:String,artifactID:String) throws {
        // A task may exit while an already validated export is being durably
        // published. Keep that export, but never revive its finished pipe.
        let receipt=try stream.saved(id:id,artifactID:artifactID)
        if !terminal && !revoked {try response(receipt)}
    }
    func renew() throws {try response(Data("{\"version\":1,\"type\":\"lease.renew\"}".utf8))}
    func poll(attach:DockerAttach,started:Bool,now:Int64,uptime:TimeInterval) throws -> [SandboxStreamEvent] {
        guard !revoked,now>=previous,now<deadline else {revoke(attach:attach);throw ControlError.invalid_request}
        previous=now
        do {
            if !terminal {try stream.validate(now:now)}
            if started && uploadBegan==nil {uploadBegan=now}
            if !terminal && !uploaded,let began=uploadBegan,now-began>=10000 {throw RuntimeError.deadline}
            var events:[SandboxStreamEvent]=[]
            // Fixed per-heartbeat I/O/work budget. No blocking wait or queue
            // draining loop controlled by task output.
            for _ in 0..<3 {
                if attach.eof {break}
                if attach.ready && started && !uploaded && !terminal {
                    let fields:[String:Any]
                    switch stage {
                    case 0:fields=["type":"input.begin","length":length,"sha256":hash,"deadline":deadline]
                    case 1:
                        if offset<length {fields=["type":"input.chunk","index":index,"data":Data(source[offset..<min(offset+32768,length)]).base64EncodedString()]}
                        else {fields=["type":"input.end"]}
                    default:throw ControlError.invalid_request
                    }
                    let bytes=try framed(fields)
                    if bytes.count<=attach.writableBytes {
                        try attach.enqueue(bytes)
                        if stage==0 {stage=1}
                        else if offset<length {offset=min(offset+32768,length);index+=1}
                        else {stage=3;source.removeAll()}
                    }
                }
                if uploaded,let next=responses.first,next.count<=attach.writableBytes {
                    try attach.enqueue(next);responses.removeFirst();responseBytes-=next.count
                }
                if attach.eof {break}
                for frame in try attach.poll(now:uptime) {
                    guard !terminal else {throw ControlError.invalid_request}
                    if let event=try stream.accept(frame,now:now) {
                        if case .done=event {terminal=true}
                        if case .revoked=event {terminal=true}
                        if terminal {source.removeAll();responses.removeAll();responseBytes=0}
                        events.append(event)
                    }
                }
            }
            if attach.eof && !terminal {throw ControlError.invalid_request}
            return events
        } catch {revoke(attach:attach);throw error}
    }
    func revoke(attach:DockerAttach) {
        revoked=true;source.removeAll();responses.removeAll();responseBytes=0
        stream.revoke();attach.close()
    }
}
