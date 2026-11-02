import Foundation
import CoreFoundation

enum ModelProtocolError:Error { case invalid }
enum ModelWorkerEvent {
    case dispatched, activity, text(kind:String,content:String), usage(posts:Int,output:Int)
    case complete, interrupted, failed(code:String)
}

// Trusted-binary protocol processing is correlated to one reserved request.
// No terminal/usage/transport event alone clears any other ownership record.
struct ModelWorkerProtocol {
    let job:String
    let attempt:Int
    private var dispatched=false
    private var usage:(Int,Int)?
    private var units=0
    private var terminal=false
    private var failed=false
    init(job:String,attempt:Int) { self.job=job;self.attempt=attempt }
    mutating func accept(_ data:Data) throws -> ModelWorkerEvent {
        guard !failed else { throw ModelProtocolError.invalid }
        do { return try parse(data) }
        catch { failed=true;throw ModelProtocolError.invalid }
    }
    private mutating func parse(_ data:Data) throws -> ModelWorkerEvent {
        guard !terminal else { throw ModelProtocolError.invalid }
        try StrictJSON.validate(data,maximum:256<<10)
        guard let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              fields["job_id"] as? String==job,let type=fields["type"] as? String else { throw ModelProtocolError.invalid }
        func integer(_ key:String)->Int? {
            guard let number=fields[key] as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["d","f"].contains(String(cString:number.objCType)),number.int64Value>=0,
                  number.int64Value<=ActivityPolicy.maximumTimestamp else { return nil }
            return Int(number.int64Value)
        }
        func exact(_ extra:[String])->Bool { Set(fields.keys)==Set(["v","type","job_id"]+extra) }
        guard integer("v")==1 else { throw ModelProtocolError.invalid }
        switch type {
        case "activity":
            guard exact([]),usage==nil else { throw ModelProtocolError.invalid };return .activity
        case "dispatched":
            guard exact(["attempt"]),integer("attempt")==attempt,!dispatched,usage==nil else { throw ModelProtocolError.invalid }
            dispatched=true;return .dispatched
        case "delta","reasoning":
            guard exact(["content"]),dispatched,usage==nil,let content=fields["content"] as? String,
                  !content.isEmpty,content.utf16.count<=8192,content.utf16.count<=64000-units else { throw ModelProtocolError.invalid }
            units+=content.utf16.count;return .text(kind:type,content:content)
        case "usage":
            guard exact(["attempt","posts","output_units"]),usage==nil,integer("attempt")==attempt,
                  let posts=integer("posts"),(0...1).contains(posts),posts==0 || dispatched,
                  let output=integer("output_units"),(units...64000).contains(output),posts==1 || output==0 else { throw ModelProtocolError.invalid }
            usage=(posts,output);return .usage(posts:posts,output:output)
        case "done":
            guard exact(["status"]),let status=fields["status"] as? String,let usage else { throw ModelProtocolError.invalid }
            if status=="complete" {
                guard dispatched,usage.0==1,usage.1==units else { throw ModelProtocolError.invalid }
                terminal=true;return .complete
            }
            guard status=="interrupted" else { throw ModelProtocolError.invalid }
            terminal=true;return .interrupted
        case "error":
            let codes:Set<String>=["busy","invalid_request","model_unavailable","upstream_unavailable","upstream_http","upstream_timeout","incomplete_stream","invalid_stream","unsupported_output","output_limit","internal_error","deadline","search_tool_protocol","search_budget_exceeded"]
            guard let code=fields["code"] as? String,codes.contains(code),exact(["code"]) || exact(["code","upstream_status"]) else { throw ModelProtocolError.invalid }
            if fields["upstream_status"] != nil {
                guard let status=integer("upstream_status"),(400...599).contains(status) else { throw ModelProtocolError.invalid }
            }
            terminal=true;return .failed(code:code)
        default:throw ModelProtocolError.invalid
        }
    }
}
