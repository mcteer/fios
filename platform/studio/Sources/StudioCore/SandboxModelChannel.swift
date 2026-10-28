import Foundation
import CoreFoundation

enum SandboxModelInput { case request(id:String,prompt:String),cancel(id:String) }

// Constructed by the trusted runtime controller after full container identity
// verification. Neither model/endpoint/owner nor management roles come from
// container data. Every container frame remains untrusted.
struct SandboxModelChannel {
    let job:String
    let runtimeID:String
    private var active:String?
    private var used=Set<String>()
    private var closed=false,cancelled=false
    init(job:String,runtimeID:String) throws {
        guard UUID(uuidString:job)?.uuidString.lowercased()==job,runtimeID.count==64,
              runtimeID.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else { throw ControlError.invalid_request }
        self.job=job;self.runtimeID=runtimeID
    }
    mutating func accept(_ data:Data,runtimeID:String) throws -> SandboxModelInput {
        guard !closed else { throw ControlError.invalid_request }
        do {
            guard runtimeID==self.runtimeID else { throw ControlError.unauthorized }
            try StrictJSON.validate(data,maximum:65536)
            guard let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let version=value["version"] as? NSNumber,CFGetTypeID(version) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:version.objCType)),version.intValue==1,
                  let kind=value["type"] as? String,let id=value["id"] as? String,
                  UUID(uuidString:id)?.uuidString.lowercased()==id else { throw ControlError.invalid_request }
            if kind=="model.request" {
                guard Set(value.keys)==Set(["version","type","id","prompt"]),active==nil,used.count<4,!used.contains(id),
                      let prompt=value["prompt"] as? String,!prompt.isEmpty,prompt.utf16.count<=128000 else { throw ControlError.invalid_request }
                used.insert(id);active=id;cancelled=false
                return .request(id:id,prompt:prompt)
            }
            guard kind=="model.cancel",Set(value.keys)==Set(["version","type","id"]),active==id else { throw ControlError.invalid_request }
            cancelled=true;return .cancel(id:id)
        } catch {
            closed=true;throw error
        }
    }
    mutating func forward(_ event:ModelWorkerEvent) throws -> [Data] {
        guard !closed,let id=active else { return [] }
        let value:[String:Any]
        switch event {
        case .text(let kind,let content):
            // Hidden reasoning is not a sandbox instruction/control channel.
            guard kind=="delta",!cancelled else { return [] }
            guard content.utf16.count<=8192 else { closed=true;throw ControlError.invalid_request }
            value=["version":1,"type":"model.delta","id":id,"content":content]
        case .complete:
            value=["version":1,"type":"model.done","id":id,"status":cancelled ? "interrupted" : "complete"];active=nil
        case .interrupted:
            value=["version":1,"type":"model.done","id":id,"status":"interrupted"];active=nil
        case .failed:
            value=["version":1,"type":"model.done","id":id,"status":"failed"];active=nil
        case .activity,.usage,.dispatched:return []
        }
        let data=try JSONSerialization.data(withJSONObject:value)
        guard data.count<=65536 else { closed=true;throw ControlError.invalid_request }
        return [data]
    }
    mutating func revoke() { closed=true;active=nil }
}
