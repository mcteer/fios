import Foundation

enum ServingCustodyOperation:String,CaseIterable,Sendable {
    case launch,lookupLaunch="lookup_launch",cancelLaunch="cancel_launch"
    case stop,lookupStop="lookup_stop",cancelStop="cancel_stop"
    var isStop:Bool {self == .stop || self == .lookupStop || self == .cancelStop}
    var isAction:Bool {self == .launch || self == .stop}
}

// Fixed native service only. No packet selects argv, paths, credentials,
// model/host/role, force policy or native authority. Decoding is data only.
struct ServingCustodyCommand:Sendable {
    let id:String
    let operation:ServingCustodyOperation
    let instance:String
    let profile:String
    let imageSHA256:String
    let deadline:TimeInterval?
    let receipt:ServiceRecordedLaunch?
    var launchCommand:ServiceLaunchCommand {ServiceLaunchCommand(service:.mlx,id:id,expectedSHA256:imageSHA256,profileHash:profile)}
    init(_ bytes:Data,expectedSHA256:String)throws {
        try StrictJSON.validate(bytes,maximum:2048)
        guard WireScalar.sha256(expectedSHA256),let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              WireScalar.integer(value["version"],maximum:1)==1,value["purpose"] as? String=="native_serving_custody",
              let id=value["id"] as? String,WireScalar.uuid(id),
              let text=value["operation"] as? String,let operation=ServingCustodyOperation(rawValue:text),
              let instance=value["instance"] as? String,WireScalar.uuid(instance),
              let profile=value["profile"] as? String,WireScalar.sha256(profile),
              value["image_sha256"] as? String==expectedSHA256 else {throw ControlError.invalid_request}
        var keys=Set(["version","purpose","id","operation","instance","profile","image_sha256"])
        var deadline:TimeInterval?
        if operation.isAction {
            keys.insert("deadline_uptime_ms")
            guard let time=WireScalar.integer(value["deadline_uptime_ms"],maximum:WireScalar.maximumTimestamp),time>0 else {throw ControlError.invalid_request}
            deadline=TimeInterval(time)/1000
        }
        var receipt:ServiceRecordedLaunch?
        if operation.isStop {
            keys.formUnion(["launch_id","pid","process_start","boot"])
            guard let launchID=value["launch_id"] as? String,WireScalar.uuid(launchID),launchID != id,
                  let pid=WireScalar.integer(value["pid"],maximum:Int64(Int32.max)),pid>1,
                  let startText=value["process_start"] as? String,let start=UInt64(startText),start>0,String(start)==startText,
                  let boot=value["boot"] as? String,WireScalar.uuid(boot) else {throw ControlError.invalid_request}
            receipt=ServiceRecordedLaunch(service:.mlx,id:launchID,identity:ServiceIdentity(pid:Int32(pid),start:start,sha256:expectedSHA256),boot:boot,profileHash:profile)
        }
        guard Set(value.keys)==keys else {throw ControlError.invalid_request}
        self.id=id;self.operation=operation;self.instance=instance;self.profile=profile;imageSHA256=expectedSHA256
        self.deadline=deadline;self.receipt=receipt
    }
    static func encode(id:String,operation:ServingCustodyOperation,instance:String,profile:String,imageSHA256:String,
                       deadline:TimeInterval?=nil,receipt:ServiceRecordedLaunch?=nil)throws->Data {
        guard operation.isAction == (deadline != nil),operation.isStop == (receipt != nil) else {throw ControlError.invalid_request}
        var value:[String:Any]=["version":1,"purpose":"native_serving_custody","id":id,"operation":operation.rawValue,
            "instance":instance,"profile":profile,"image_sha256":imageSHA256]
        if let deadline {
            guard deadline.isFinite,deadline>0,deadline<=Double(WireScalar.maximumTimestamp)/1000 else {throw ControlError.invalid_request}
            value["deadline_uptime_ms"]=Int64((deadline*1000).rounded(.down))
        }
        if let receipt {
            guard receipt.service == .mlx,receipt.profileHash==profile,receipt.identity.sha256==imageSHA256 else {throw ControlError.invalid_request}
            value["launch_id"]=receipt.id;value["pid"]=receipt.identity.pid
            value["process_start"]=String(receipt.identity.start);value["boot"]=receipt.boot
        }
        let bytes=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        _=try Self(bytes,expectedSHA256:imageSHA256);return bytes
    }
}

enum ServingCustodyValue:Equatable,Sendable {
    case launch(SessionLaunchResult)
    case stop(ServingStopResult)
}

enum ServingCustodyReply {
    static func encode(command:ServingCustodyCommand,value:ServingCustodyValue)throws->Data {
        var fields:[String:Any]=["version":1,"purpose":"native_serving_custody_reply","id":command.id,
            "operation":command.operation.rawValue,"instance":command.instance,"profile":command.profile]
        switch value {
        case .launch(let value):
            guard !command.operation.isStop else {throw ControlError.invalid_request}
            switch value {
            case .started(let identity):
                fields["status"]="started";fields["pid"]=identity.pid;fields["process_start"]=String(identity.start);fields["sha256"]=identity.sha256
            case .notSent:fields["status"]="not_sent"
            case .uncertain:fields["status"]="uncertain"
            case .wrongInstance:fields["status"]="wrong_instance"
            case .busy:fields["status"]="busy"
            }
        case .stop(let value):
            guard command.operation.isStop else {throw ControlError.invalid_request}
            switch value {
            case .notSent:fields["status"]="not_sent"
            case .localExited:fields["status"]="local_exited"
            case .uncertain:fields["status"]="uncertain"
            }
        }
        let bytes=try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys])
        _=try decode(bytes,command:command);return bytes
    }
    static func decode(_ bytes:Data,command:ServingCustodyCommand)throws->ServingCustodyValue {
        try StrictJSON.validate(bytes,maximum:2048)
        guard let fields=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              WireScalar.integer(fields["version"],maximum:1)==1,fields["purpose"] as? String=="native_serving_custody_reply",
              fields["id"] as? String==command.id,fields["operation"] as? String==command.operation.rawValue,
              fields["instance"] as? String==command.instance,fields["profile"] as? String==command.profile,
              let status=fields["status"] as? String else {throw ControlError.invalid_request}
        let base=Set(["version","purpose","id","operation","instance","profile","status"])
        if status=="started" {
            guard !command.operation.isStop,Set(fields.keys)==base.union(["pid","process_start","sha256"]),
                  let pid=WireScalar.integer(fields["pid"],maximum:Int64(Int32.max)),pid>1,
                  let text=fields["process_start"] as? String,let start=UInt64(text),start>0,String(start)==text,
                  fields["sha256"] as? String==command.imageSHA256 else {throw ControlError.invalid_request}
            return .launch(.started(ServiceIdentity(pid:Int32(pid),start:start,sha256:command.imageSHA256)))
        }
        guard Set(fields.keys)==base else {throw ControlError.invalid_request}
        if command.operation.isStop {
            switch status {
            case "not_sent":return .stop(.notSent)
            case "local_exited":return .stop(.localExited)
            case "uncertain":return .stop(.uncertain)
            default:throw ControlError.invalid_request
            }
        }
        switch status {
        case "not_sent":return .launch(.notSent)
        case "uncertain":return .launch(.uncertain)
        case "wrong_instance":return .launch(.wrongInstance)
        case "busy":return .launch(.busy)
        default:throw ControlError.invalid_request
        }
    }
}
