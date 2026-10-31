import Foundation

func runOperatorServiceStatusTests() throws {
    for service in ["mlx","orbstack"] {
        guard let command=OperatorServiceCommand(arguments:["service",service,"status"]) else {fatalError("Service status command missing")}
        precondition(command.operation == .status && command.payload.isEmpty && command.socketName == "observe.sock")
        let response:[String:Any]=["ok":true,"services":[service:["desired":"maintenance","observed":"ready"]]]
        let result=try command.renderResponse(response)
        precondition(result["service"] as? String == service && result["desired"] as? String == "maintenance" && result["observed"] as? String == "ready")
        let unavailable=try command.renderResponse(["ok":false,"error":"unavailable"])
        precondition(unavailable["error"] as? String == "unavailable")
        let desired=OperatorServiceCommand(arguments:["service",service,"running"])!
        precondition(desired.socketName == "control.sock")
        let acknowledgement=try desired.renderResponse(["ok":true,"applied":false])
        precondition(acknowledgement["applied"] as? Bool == false)
        for action in [["maintenance"],["stopped"],["drain"],["force","prepare"],
                       ["force","confirm","00000000-0000-4000-8000-000000000001",String(repeating:"a",count:64)]] {
            let lifecycle=OperatorServiceCommand(arguments:["service",service]+action)!
            precondition(lifecycle.socketName == "control.sock" && lifecycle.payload["service"] as? String == service)
            let result=try lifecycle.renderResponse(["ok":true,"applied":false])
            precondition(result["applied"] as? Bool == false)
        }
    }
}

func runOperatorServiceCommandTests() throws {
    func expect(_ value:Bool,_ message:String) throws {guard value else {fatalError(message)}}
    for service in ["mlx","orbstack"] {
        for desired in ["running","maintenance","stopped"] {
            let command=OperatorServiceCommand(arguments:["service",service,desired])
            try expect(command?.operation == .serviceDesired,"Fixed desired grammar missing")
            try expect(OperatorServiceCommand.valid(operation:command!.operation,payload:command!.payload),"CLI/server desired grammar differs")
        }
        for args in [["service",service,"drain"],["service",service,"force","prepare"],["service",service,"force","confirm","00000000-0000-4000-8000-000000000001",String(repeating:"a",count:64)]] {
            let command=OperatorServiceCommand(arguments:args)
            try expect(command != nil && OperatorServiceCommand.valid(operation:command!.operation,payload:command!.payload),"CLI/server lifecycle grammar differs")
        }
    }
    for args in [[],["service"],["service","mlx"],["service","foreign","running"],["service","mlx","shell"],
                 ["service","mlx","running","--force"],["service","mlx","force"],["service","mlx","force","prepare","extra"],
                 ["service","mlx","force","confirm","bad",String(repeating:"a",count:64)],
                 ["service","mlx","force","confirm","00000000-0000-4000-8000-00000000000A",String(repeating:"a",count:64)],
                 ["service","mlx","force","confirm","00000000-0000-4000-8000-000000000001",String(repeating:"A",count:64)]] {
        try expect(OperatorServiceCommand(arguments:args)==nil,"Unsafe CLI argument grammar accepted")
    }
    let bad:[(ControlOperation,[String:Any])]=[
        (.status,["service":"mlx"]),(.serviceDesired,["service":"mlx","desired":"shell"]),
        (.serviceDesired,["service":"mlx","desired":"running","role":"operator"]),
        (.serviceDrain,["service":"mlx","scope_digest":String(repeating:"a",count:64)]),
        (.serviceDrain,["service":true]),(.serviceForce,["service":"mlx","phase":"prepare","token":"fake"]),
        (.serviceForce,["service":"mlx","phase":"confirm","token":"00000000-0000-4000-8000-000000000001","scope_digest":true])]
    for (operation,payload) in bad {try expect(!OperatorServiceCommand.valid(operation:operation,payload:payload),"Malformed lifecycle payload accepted")}
}
