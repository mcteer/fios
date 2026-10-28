import Foundation
import CryptoKit

enum ArtifactDownloadEvent {
    case begin(id:String,length:Int,sha256:String)
    case chunk(index:Int,base64:String)
    case end
}

// Owner authentication/integrity verification precedes construction. Finite
// opaque export data only; no filenames, filesystem paths or management tags.
struct ArtifactDownload:Sendable {
    private let id:String
    private var data:Data
    private let sha256:String
    private let deadline:Int64
    private var previous:Int64
    private var began=false,ended=false
    private var offset=0,index=0
    init(id:String,data:Data,created:Int64,expires:Int64) throws {
        guard UUID(uuidString:id)?.uuidString.lowercased()==id,data.count<=16<<20,
              created>=0,created<=ActivityPolicy.maximumTimestamp-30000,expires>created else { throw ArtifactError.invalid }
        self.id=id;self.data=Data(data);previous=created;deadline=min(created+30000,expires)
        sha256=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
    }
    mutating func next(now:Int64) throws -> ArtifactDownloadEvent {
        guard !ended,now>=previous,now<deadline else {
            cancel();throw ArtifactError.unavailable
        }
        previous=now
        if !began { began=true;return .begin(id:id,length:data.count,sha256:sha256) }
        if offset<data.count {
            let end=min(offset+32768,data.count),bytes=Data(data[offset..<end])
            let event=ArtifactDownloadEvent.chunk(index:index,base64:bytes.base64EncodedString())
            offset=end;index+=1;return event
        }
        cancel();return .end
    }
    mutating func cancel() { ended=true;data.removeAll() }
}
