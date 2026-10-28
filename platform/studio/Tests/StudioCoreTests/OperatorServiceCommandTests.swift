import Foundation

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
