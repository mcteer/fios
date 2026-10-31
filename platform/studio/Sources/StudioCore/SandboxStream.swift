import Foundation
import CoreFoundation

enum SandboxStreamEvent {
    case model(Data),output(stream:String,index:Int,data:Data),artifact(id:String,data:Data),done(success:Bool),revoked
}

// Payload interpretation only. No filesystem/runtime/management authority.
// Artifact bytes leave only through the owner's trusted publication service.
struct SandboxStream {
    private var budget=TransferBudget()
    private var outputIndex=0
    private var artifact:(id:String,transfer:ChunkTransfer)?
    private var exports=Set<String>()
    private var awaitingSaved=Set<String>()
    private var closed=false
    private var previous:Int64
    init(now:Int64) throws {
        guard (0...ActivityPolicy.maximumTimestamp).contains(now) else { throw ControlError.invalid_request }
        previous=now
    }
    private func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),!["d","f"].contains(String(cString:n.objCType)),n.doubleValue>=Double(Int32.min),n.doubleValue<=Double(Int32.max) else {return nil}
        return n.intValue
    }
    private func uuid(_ value:Any?)->String? {
        guard let text=value as? String,UUID(uuidString:text)?.uuidString.lowercased()==text else {return nil};return text
    }
    mutating func validate(now:Int64) throws {
        guard !closed,now>=previous,now<=ActivityPolicy.maximumTimestamp else {closed=true;throw ControlError.invalid_request}
        previous=now
        do {
            if var pending=artifact {try pending.transfer.validate(now:now);artifact=pending}
        } catch {closed=true;artifact=nil;throw error}
    }
    mutating func accept(_ data:Data,now:Int64) throws -> SandboxStreamEvent? {
        do {
            try validate(now:now)
            try StrictJSON.validate(data,maximum:65536)
            guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],integer(value["version"])==1,let kind=value["type"] as? String else {throw ControlError.invalid_request}
            func exact(_ fields:Set<String>) throws {
                guard Set(value.keys)==fields.union(["version","type"]) else {throw ControlError.invalid_request}
            }
            switch kind {
            case "model.request","model.cancel":
                guard artifact==nil else {throw ControlError.invalid_request}
                // Exact request/UUID/budget validation belongs to the bound
                // SandboxModelChannel immediately before broker submission.
                return .model(data)
            case "output":
                try exact(["stream","index","data"])
                guard let stream=value["stream"] as? String,["stdout","stderr"].contains(stream),integer(value["index"])==outputIndex,
                      let encoded=value["data"] as? String,encoded.utf8.count<=43692,
                      let bytes=Data(base64Encoded:encoded),!bytes.isEmpty,bytes.count<=32768,bytes.base64EncodedString()==encoded else {throw ControlError.invalid_request}
                try budget.chargeOutput(bytes.count)
                let index=outputIndex;outputIndex+=1
                return .output(stream:stream,index:index,data:bytes)
            case "artifact.begin":
                try exact(["id","length","sha256"])
                guard artifact==nil,exports.count<256,let id=uuid(value["id"]),!exports.contains(id),let length=integer(value["length"]),let hash=value["sha256"] as? String else {throw ControlError.invalid_request}
                try budget.chargeOutput(length)
                artifact=(id,try ChunkTransfer(length:length,sha256:hash,created:now,kind:.artifact));exports.insert(id)
            case "artifact.chunk":
                try exact(["id","index","data"])
                guard var pending=artifact,value["id"] as? String==pending.id,let index=integer(value["index"]),let encoded=value["data"] as? String else {throw ControlError.invalid_request}
                try pending.transfer.append(index:index,base64:encoded,now:now);artifact=pending
            case "artifact.end":
                try exact(["id"])
                guard var pending=artifact,value["id"] as? String==pending.id else {throw ControlError.invalid_request}
                let bytes=try pending.transfer.finish(now:now)
                artifact=nil;awaitingSaved.insert(pending.id)
                return .artifact(id:pending.id,data:bytes)
            case "done":
                try exact(["status","exit_code","output_bytes"])
                guard artifact==nil,let code=integer(value["exit_code"]),(-255...255).contains(code),integer(value["output_bytes"])==budget.output,
                      let status=value["status"] as? String,status==(code==0 ? "complete":"failed") else {throw ControlError.invalid_request}
                closed=true;return .done(success:code==0)
            case "error":
                try exact(["code"])
                let safe:Set<String>=["invalid_frame","input_deadline","input_hash","owner_gone","output_limit","backpressure","lease_expired","unsafe_runtime","artifact_deadline","task_revoked"]
                guard let code=value["code"] as? String,safe.contains(code) else {throw ControlError.invalid_request}
                closed=true;artifact=nil;return .revoked
            default:throw ControlError.invalid_request
            }
            return nil
        } catch {closed=true;artifact=nil;throw error}
    }
    mutating func saved(id:String,artifactID:String) throws -> Data {
        guard awaitingSaved.remove(id) != nil,uuid(artifactID) != nil else {throw ControlError.invalid_request}
        return try JSONSerialization.data(withJSONObject:["version":1,"type":"artifact.saved","id":id,"artifact_id":artifactID])
    }
    mutating func revoke() {closed=true;artifact=nil;awaitingSaved.removeAll()}
}
