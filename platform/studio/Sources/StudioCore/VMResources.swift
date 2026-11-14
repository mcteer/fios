import Foundation

// A configured cap is not a free-memory measurement. Only a trusted adapter
// covering the entire shared VM may supply this observation; container sums
// and host process RSS are deliberately insufficient.
struct VMResourceObservation:Sendable {
    let runtimeHash:String
    let sampledAt:Int64
    let configuredCap:UInt64
    let total:UInt64
    let free:UInt64
    let allVMConsumersCovered:Bool
}
enum VMResources {
    static func kernelMemory(_ data:Data)->(total:UInt64,free:UInt64)? {
        guard !data.isEmpty,data.count<=16384,let text=String(data:data,encoding:.utf8) else {return nil}
        var fields:[String:UInt64]=[:]
        for line in text.split(separator:"\n") {
            let tokens=line.split(whereSeparator:{$0.isWhitespace})
            guard let first=tokens.first else {continue}
            let key=String(first)
            guard ["MemTotal:","MemFree:"].contains(key) else {continue}
            guard tokens.count==3,tokens[2]=="kB",!tokens[1].isEmpty,tokens[1].utf8.allSatisfy({(48...57).contains($0)}),
                  let value=UInt64(tokens[1]),value<=UInt64.max/1024,fields[key]==nil else {return nil}
            fields[key]=value*1024
        }
        guard let total=fields["MemTotal:"],let free=fields["MemFree:"],total>0,free<=total else {return nil}
        return (total,free)
    }
    static func remaining(_ value:VMResourceObservation,expectedRuntimeHash:String,now:Int64)->UInt64? {
        guard value.allVMConsumersCovered,value.runtimeHash==expectedRuntimeHash,
              value.runtimeHash.utf8.count==64,value.runtimeHash.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
              now>=0,now<=ActivityPolicy.maximumTimestamp,value.sampledAt>=0,value.sampledAt<=ActivityPolicy.maximumTimestamp,
              value.sampledAt<=now+1000,now-value.sampledAt<=5000,
              value.configuredCap>0,value.total>0,value.free<=value.total else {return nil}
        // Count all non-free VM pages as occupied, including cache/system
        // services/machines. No speculative reclaim or double free allowance.
        let occupied=value.total-value.free
        guard occupied<=value.configuredCap else {return 0}
        return min(value.free,value.configuredCap-occupied)
    }
}
