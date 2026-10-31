import Foundation
import CoreFoundation

public struct SandboxConfiguration: Codable, Sendable, Equatable {
    public let job: String
    public let nonce: String
    public let image: String
    public let memory: UInt64
    public let cpus: Int
    public let workspace: UInt64
    public var name: String { "fios-sandbox-" + job }

    public init(job: String, nonce: String, image: String, memory: UInt64, cpus: Int, workspace:UInt64 = 128<<20) throws {
        guard let uuid = UUID(uuidString:job), uuid.uuidString.lowercased() == job,
              nonce.utf8.count == 64, nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              image.hasPrefix("sha256:"), image.utf8.count == 71,
              image.dropFirst(7).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              memory >= 512 << 20, memory <= 2 << 30, (1...2).contains(cpus),
              workspace>0,workspace<=256<<20
        else { throw RuntimeError.invalid }
        self.job=job; self.nonce=nonce; self.image=image; self.memory=memory; self.cpus=cpus
        self.workspace=workspace
    }
    private enum CodingKeys:String,CodingKey {case job,nonce,image,memory,cpus,workspace}
    public init(from decoder:any Decoder)throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(job:values.decode(String.self,forKey:.job),nonce:values.decode(String.self,forKey:.nonce),
                      image:values.decode(String.self,forKey:.image),memory:values.decode(UInt64.self,forKey:.memory),
                      cpus:values.decode(Int.self,forKey:.cpus),
                      workspace:values.contains(.workspace) ? values.decode(UInt64.self,forKey:.workspace):128<<20)
    }
    public func encode(to encoder:any Encoder)throws {
        var values=encoder.container(keyedBy:CodingKeys.self)
        try values.encode(job,forKey:.job);try values.encode(nonce,forKey:.nonce);try values.encode(image,forKey:.image)
        try values.encode(memory,forKey:.memory);try values.encode(cpus,forKey:.cpus)
        // Preserve the historical default configuration representation.
        if workspace != 128<<20 {try values.encode(workspace,forKey:.workspace)}
    }
    public var createArguments: [String] {
        ["create","--name",name,"--pull=never","--network=none","--read-only",
         "--user=65532:65532","--cap-drop=ALL","--security-opt=no-new-privileges:true",
         "--pids-limit=64","--memory=\(memory)","--memory-swap=\(memory)","--cpus=\(cpus)",
         "--tmpfs=/workspace:rw,nosuid,nodev,size=\(workspace),mode=0700,uid=65532,gid=65532",
         "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=67108864,mode=1777",
         "--log-driver=none","--label","fios.platform.job=\(job)",
         "--label","fios.platform.nonce=\(nonce)","--interactive",image]
    }

    // Labels alone never authorize deletion. Require saved daemon ID, exact
    // deterministic name, immutable image and creation nonce as well.
    public func verifies(inspect: [String:Any], savedID: String) -> Bool {
        guard inspect["Id"] as? String == savedID, savedID.count == 64,
              inspect["Name"] as? String == "/" + name,
              inspect["Image"] as? String == image,
              let config = inspect["Config"] as? [String:Any],
              let labels = config["Labels"] as? [String:String]
        else { return false }
        return labels["fios.platform.job"] == job && labels["fios.platform.nonce"] == nonce
    }
}

public struct DockerRuntime:Sendable {
    let executable: VerifiedExecutable
    let socket: String
    let endpointPolicy:RuntimeEndpointPolicy?
    public init(executable: VerifiedExecutable, socket: String) throws {
        guard socket.hasPrefix("/"), !socket.contains("\0"), !socket.contains("..") else { throw RuntimeError.invalid }
        self.executable=executable; self.socket=socket;endpointPolicy=nil
    }
    init(executable:VerifiedExecutable,endpoint:RuntimeEndpointPolicy) {
        self.executable=executable;socket=endpoint.path;endpointPolicy=endpoint
    }
    func command(_ arguments: [String], timeout: TimeInterval = 10) throws -> CommandResult {
        guard timeout.isFinite,timeout>0,timeout<=10 else {throw RuntimeError.invalid}
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        let pinned=try endpointPolicy?.capture(deadline:min(deadline,ProcessInfo.processInfo.systemUptime+2))
        let peer=try endpointPolicy?.peer?.connect(path:socket,deadline:min(deadline,ProcessInfo.processInfo.systemUptime+2))
        let remaining=deadline-ProcessInfo.processInfo.systemUptime
        guard remaining>0 else {throw RuntimeError.deadline}
        let result=try executable.run(arguments:["--host","unix://" + socket] + arguments, timeout:remaining,
                           environment:["DOCKER_CONFIG":"/var/empty", "DOCKER_CLI_HINTS":"false"])
        // A changed endpoint after an effect is unavailable/uncertain. Never
        // turn a locally successful CLI into permission to retry or release.
        try pinned?.verify(deadline:min(deadline,ProcessInfo.processInfo.systemUptime+2))
        _=try peer?.verify(deadline:min(deadline,ProcessInfo.processInfo.systemUptime+2))
        return result
    }
    public func create(_ configuration: SandboxConfiguration) throws -> String {
        let result = try command(configuration.createArguments)
        let id = String(decoding:result.output,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        guard result.status == 0, id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw RuntimeError.launch }
        return id
    }
    public func removeOwned(_ configuration: SandboxConfiguration, savedID: String) throws {
        guard savedID.utf8.count == 64, savedID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw RuntimeError.invalid }
        let result = try command(["inspect", "--type=container", savedID],timeout:2)
        guard result.status == 0 else { throw RuntimeError.launch }
        try StrictJSON.validate(result.output,maximum:1 << 20)
        guard let records = try JSONSerialization.jsonObject(with:result.output) as? [[String:Any]], records.count == 1,
              configuration.verifies(inspect:records[0],savedID:savedID) else { throw RuntimeError.identity }
        guard let state=records[0]["State"] as? [String:Any],
              let number=state["Running"] as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID(),
              let running=state["Running"] as? Bool else {throw RuntimeError.identity}
        guard !running else {throw RuntimeError.launch}
        // The daemon must refuse a restart racing this stopped snapshot.
        // Acknowledgement is not absence; the lifecycle still queries full ID.
        let removed = try command(["rm",savedID])
        guard removed.status == 0 else { throw RuntimeError.launch }
    }
}
