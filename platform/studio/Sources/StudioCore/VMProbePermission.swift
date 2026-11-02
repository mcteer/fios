import Foundation
import Darwin
import CryptoKit

// Trusted profile/bootstrap authority, never Codable or task/model input.
// One finite observation, not recurring permission or a persistent service.
final class VMProbePermission {
    let image:String
    let id:String
    let nonce:String
    let issued:Int64
    let ownerHash:String
    private let boot:String
    private let uid:uid_t
    private var previous:Int64
    private var revoked=false
    private(set) var job:String?
    static let source=Data("import time\ntime.sleep(10)\n".utf8)
    static var sourceHash:String {digest(source)}
    private static func digest(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    init(reviewedImage:String,reviewDigest:String,managerEpoch:String,issued:Int64,id:String=UUID().uuidString.lowercased(),nonce:String? = nil)throws {
        func hash(_ value:String)->Bool {value.utf8.count==64 && value.utf8.allSatisfy {(48...57).contains($0)||(97...102).contains($0)}}
        let nonce=nonce ?? (UUID().uuidString+UUID().uuidString).replacingOccurrences(of:"-",with:"").lowercased()
        guard UUID(uuidString:id)?.uuidString.lowercased()==id,hash(nonce),reviewedImage.hasPrefix("sha256:"),hash(String(reviewedImage.dropFirst(7))),hash(reviewDigest),
              UUID(uuidString:managerEpoch)?.uuidString.lowercased()==managerEpoch,
              issued>=0,issued<=ActivityPolicy.maximumTimestamp-30000,geteuid() != 0 else {throw AdmissionError.invalid}
        image=reviewedImage;self.id=id;self.nonce=nonce;self.issued=issued;previous=issued;boot=try HostBoot.identity();uid=geteuid()
        ownerHash=Self.digest(Data(("fios-vm-bootstrap-owner-v1\0"+reviewDigest+"\0"+managerEpoch+"\0"+UUID().uuidString.lowercased()).utf8))
    }
    func validate(now:Int64)throws {
        do {
            guard !revoked,now>=previous,now>=issued,now<issued+30000,uid==geteuid(),try HostBoot.identity()==boot else {throw AdmissionError.expired}
            previous=now
        } catch {revoked=true;throw error}
    }
    func consume(job:String,now:Int64)throws {
        try validate(now:now)
        guard self.job==nil,job==id else {throw AdmissionError.invalid}
        self.job=job
    }
    func authorize(_ configuration:SandboxConfiguration,job:DurableJob,now:Int64)throws {
        try validate(now:now)
        guard self.job==job.id,configuration.job==job.id,configuration.nonce==nonce,configuration.image==image,configuration.memory==512<<20,configuration.cpus==1,
              job.ownerHash==ownerHash,job.requestHash==Self.sourceHash,job.lease.created==issued,job.lease.deadline==issued+30000,
              job.state == .reserved else {throw AdmissionError.invalid}
    }
}
