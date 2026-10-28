import Foundation

public struct SandboxConfiguration: Codable, Sendable, Equatable {
    public let job: String
    public let nonce: String
    public let image: String
    public let memory: UInt64
    public let cpus: Int
    public var name: String { "fios-sandbox-" + job }

    public init(job: String, nonce: String, image: String, memory: UInt64, cpus: Int) throws {
        guard let uuid = UUID(uuidString:job), uuid.uuidString.lowercased() == job,
              nonce.utf8.count == 64, nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              image.hasPrefix("sha256:"), image.utf8.count == 71,
              image.dropFirst(7).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              memory >= 512 << 20, memory <= 2 << 30, (1...2).contains(cpus)
        else { throw RuntimeError.invalid }
        self.job=job; self.nonce=nonce; self.image=image; self.memory=memory; self.cpus=cpus
    }
    public var createArguments: [String] {
        ["create","--name",name,"--pull=never","--network=none","--read-only",
         "--user=65532:65532","--cap-drop=ALL","--security-opt=no-new-privileges:true",
         "--pids-limit=64","--memory=\(memory)","--memory-swap=\(memory)","--cpus=\(cpus)",
         "--tmpfs=/workspace:rw,nosuid,nodev,size=134217728,mode=0700,uid=65532,gid=65532",
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
    public init(executable: VerifiedExecutable, socket: String) throws {
        guard socket.hasPrefix("/"), !socket.contains("\0"), !socket.contains("..") else { throw RuntimeError.invalid }
        self.executable=executable; self.socket=socket
    }
    func command(_ arguments: [String], timeout: TimeInterval = 10) throws -> CommandResult {
        try executable.run(arguments:["--host","unix://" + socket] + arguments, timeout:timeout,
                           environment:["DOCKER_CONFIG":"/var/empty", "DOCKER_CLI_HINTS":"false"])
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
        // Remove by verified full daemon ID, not a reusable name or forged label.
        let removed = try command(["rm","--force",savedID])
        guard removed.status == 0 else { throw RuntimeError.launch }
    }
}
