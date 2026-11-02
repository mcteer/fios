import Foundation

// Code-only native custody interface. A remote implementation must retain
// fixed peer/profile binding and report missing custody history as unknown.
// It cannot adopt a PID or turn local exit into native inference terminality.
protocol ServingProcessControlling:AnyObject,Sendable {
    var recoveryProfileHash:String {get}
    func acceptsBaseProfile(_ base:String,expectedSHA256:String)->Bool
    func accepts(_ command:ServiceLaunchCommand)->Bool
    func begin(_ command:ServiceLaunchCommand,deadline:TimeInterval)throws
    func acknowledgeResult(id:String)->SessionLaunchResult
    @discardableResult func cancelValidation(id:String)->Bool
    @discardableResult func retireKnownExited()->Bool
    func acceptsStopReceipt(_ receipt:ServiceRecordedLaunch)->Bool
    func beginStop(id:String,matching receipt:ServiceRecordedLaunch,deadline:TimeInterval)throws
    func rejectedStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult
    func acknowledgeStopResult(id:String,matching receipt:ServiceRecordedLaunch)->ServingStopResult
    @discardableResult func cancelStopValidation(id:String,matching receipt:ServiceRecordedLaunch)->Bool
}
