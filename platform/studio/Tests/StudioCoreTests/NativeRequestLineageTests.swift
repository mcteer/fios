import Foundation

func runNativeRequestLineageTests()throws {
    let instance=String(repeating:"1",count:32)
    let id="29fc52e328d588a1afee500c96d67ccc1045a873a328efccec3dc9ddfaef2cf5"
    let request=try NativeRequestLineageWire.request(instance:instance,correlationID:id)
    guard request.count==64,request.prefix(4)==Data("FIQ9".utf8),request[4]==1,
          request[5..<8].allSatisfy({$0==0}),request[56..<64].allSatisfy({$0==0}) else {fatalError("Invalid readonly lineage request")}
    func frame(found:Bool,uncertain:Bool,root:UInt64,references:UInt64,counts:[UInt64],sequence:UInt64=1)->Data {
        var data=Data(repeating:0,count:112)
        data.replaceSubrange(0..<4,with:Data("FIP9".utf8));data[4]=1;data[6]=found ? 1:0;data[7]=uncertain ? 1:0
        data.replaceSubrange(8..<56,with:request[8..<56])
        func put(_ value:UInt64,_ offset:Int,_ count:Int){
            for index in 0..<count {data[offset+index]=UInt8(truncatingIfNeeded:value >> ((count-index-1)*8))}
        }
        put(sequence,56,8);put(root,64,8);put(references,72,8)
        for (index,value) in counts.enumerated(){put(value,80+index*4,4)}
        return data
    }
    func decode(_ data:Data)throws->NativeRequestLineage {try NativeRequestLineageWire.reply(data,instance:instance,correlationID:id)}
    func refuses(_ data:Data){do{_=try decode(data)}catch{return};fatalError("Malformed lineage became trusted metadata")}
    let absent=frame(found:false,uncertain:true,root:0,references:0,counts:[0,0,0,0,0])
    let missing=try decode(absent)
    guard !missing.found,missing.uncertain,missing.owners==0 else {fatalError("Missing lineage became terminal/known absence")}
    let live=frame(found:true,uncertain:false,root:UInt64.max,references:3,counts:[2,0,1,0,1])
    var sliced=Data([0x55]);sliced.append(live);sliced.removeFirst()
    let present=try decode(sliced)
    guard present.found,!present.uncertain,present.rootSequence==UInt64.max,present.references==3,
          present.owners==2,present.preparing==1,present.responding==1 else {fatalError("Live retained lineage lost native width/counts")}
    for index in [0,4,5,6,7,8,24,100]{var bad=live;bad[index]=2;refuses(bad)}
    refuses(Data(live.dropLast()));var extra=live;extra.append(0);refuses(extra)
    refuses(frame(found:false,uncertain:false,root:0,references:0,counts:[0,0,0,0,0]))
    refuses(frame(found:true,uncertain:false,root:0,references:2,counts:[2,0,1,0,1]))
    refuses(frame(found:true,uncertain:false,root:1,references:1,counts:[2,0,1,0,1]))
    refuses(frame(found:true,uncertain:false,root:1,references:UInt64.max,counts:[2,0,1,0,1]))
    refuses(frame(found:true,uncertain:false,root:1,references:2,counts:[2,0,0,0,1]))
    refuses(frame(found:true,uncertain:false,root:1,references:257,counts:[257,257,0,0,0]))
    refuses(frame(found:false,uncertain:true,root:1,references:0,counts:[0,0,0,0,0]))
    refuses(frame(found:false,uncertain:true,root:0,references:0,counts:[0,0,0,0,0],sequence:0))
    refuses(frame(found:false,uncertain:true,root:0,references:0,counts:[0,0,0,0,0],sequence:UInt64.max))
    print("PASS: bounded source/ID-bound readonly lineage wire, full-width native root/ref/phase coherence, offset-safe frames and missing-is-unknown; no terminal authority")
}
