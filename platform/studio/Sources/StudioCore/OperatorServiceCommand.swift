import Foundation

// Fixed local operator grammar only. This is NOT an authority grant, session
// command, native scope issuer, or a task/model-controlled argument vector.
public struct OperatorServiceCommand {
    public let operation:ControlOperation
    public let payload:[String:Any]
    public init?(arguments:[String]) {
        guard arguments.count>=3,arguments[0]=="service",ManagedService(rawValue:arguments[1]) != nil else {return nil}
        let service=arguments[1]
        if arguments.count==3,ServiceDesired(rawValue:arguments[2]) != nil {
            operation = .serviceDesired;payload=["service":service,"desired":arguments[2]]
        } else if arguments.count==3,arguments[2]=="drain" {
            operation = .serviceDrain;payload=["service":service]
        } else if arguments.count==4,arguments[2]=="force",arguments[3]=="prepare" {
            operation = .serviceForce;payload=["service":service,"phase":"prepare"]
        } else if arguments.count==6,arguments[2]=="force",arguments[3]=="confirm",
                  Self.token(arguments[4]),Self.digest(arguments[5]) {
            operation = .serviceForce;payload=["service":service,"phase":"confirm","token":arguments[4],"scope_digest":arguments[5]]
        } else {return nil}
    }
    private static func token(_ value:String)->Bool {UUID(uuidString:value)?.uuidString.lowercased()==value}
    private static func digest(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    // Shared server-side validation. Never trust a digest as affected scope:
    // confirmation must be compared with independently issued native evidence.
    static func valid(operation:ControlOperation,payload:[String:Any])->Bool {
        guard let service=payload["service"] as? String,ManagedService(rawValue:service) != nil else {return false}
        let fields=Set(payload.keys)
        switch operation {
        case .serviceDesired:
            guard fields==Set(["service","desired"]),let desired=payload["desired"] as? String else {return false}
            return ServiceDesired(rawValue:desired) != nil
        case .serviceDrain:return fields==Set(["service"])
        case .serviceForce:
            if fields==Set(["service","phase"]),payload["phase"] as? String=="prepare" {return true}
            guard fields==Set(["service","phase","token","scope_digest"]),payload["phase"] as? String=="confirm",
                  let token=payload["token"] as? String,let digest=payload["scope_digest"] as? String else {return false}
            return Self.token(token) && Self.digest(digest)
        default:return false
        }
    }
}
