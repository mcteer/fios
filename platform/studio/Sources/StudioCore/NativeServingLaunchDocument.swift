import Foundation
import Darwin

// Decoded reviewed configuration is metadata only. No factory here loads a
// policy, reads a credential, issues a reservation or starts a process.
struct NativeServingLaunchDocument:Sendable {
    static let credentialSlot="<fios-serving-credential>"
    let host:String
    let uid:uid_t
    let reviewSHA256:String
    let managerSHA256:String
    let supervisorSHA256:String
    let serverSHA256:String
    let applicationSHA256:String
    let serverArtifact:MLXServingProcessProfile.ServerArtifact
    let revision:String
    let statePath:String
    let workingDirectory:String
    private let arguments:[String]
    private let environment:[String:String]
    private let argumentCredential:Bool
    var usesArgumentCredential:Bool {argumentCredential}
    init(_ bytes:Data)throws {
        do {
            try StrictJSON.validate(bytes,maximum:32768)
            guard let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  let version=WireScalar.integer(value["version"],maximum:2),[1,2].contains(version),
                  Set(value.keys)==Set(["version","purpose","host","uid","review_sha256","manager_sha256","supervisor_sha256","server_sha256","application_sha256","revision","state_path","working_directory","arguments","environment","credential_channel"]+(version==2 ? ["server_artifact"]:[])),
                  version==1 || value["server_artifact"] as? String=="reviewed_fios_native",
                  value["purpose"] as? String=="reviewed_native_serving_launch",
                  let host=value["host"] as? String,["fios-edge-a.lab","fios-edge-b.lab"].contains(host),
                  let uid=WireScalar.integer(value["uid"],maximum:Int64(UInt32.max)),uid>0,
                  let review=value["review_sha256"] as? String,WireScalar.sha256(review),
                  let manager=value["manager_sha256"] as? String,WireScalar.sha256(manager),
                  let supervisor=value["supervisor_sha256"] as? String,WireScalar.sha256(supervisor),
                  let server=value["server_sha256"] as? String,WireScalar.sha256(server),
                  let application=value["application_sha256"] as? String,WireScalar.sha256(application),
                  let revision=value["revision"] as? String,WireScalar.uuid(revision),
                  let state=value["state_path"] as? String,
                  state.hasPrefix("/"),!state.hasSuffix("/"),state.utf8.count<Int(MAXPATHLEN),
                  !state.contains("\0"),!state.contains("//"),!state.split(separator:"/").contains(where:{$0=="." || $0==".."}),
                  let cwd=value["working_directory"] as? String,
                  cwd.hasPrefix("/"),cwd.utf8.count<Int(MAXPATHLEN),!cwd.contains("\0"),!cwd.contains("//"),
                  (cwd=="/" || !cwd.hasSuffix("/")),!cwd.split(separator:"/").contains(where:{$0=="." || $0==".."}),
                  let args=value["arguments"] as? [String],(1...128).contains(args.count),
                  args.allSatisfy({!$0.contains("\0") && $0.utf8.count<=4096}),
                  args.first=="serve" || (args.first?.hasPrefix("--")==true && args.contains("--serve")),
                  let env=value["environment"] as? [String:String],env.count<=15,
                  env.allSatisfy({key,value in
                      ["PATH","HOME","LANG","LC_ALL","DYLD_LIBRARY_PATH","MLX_METAL_PATH"].contains(key) &&
                      !value.contains("\0") && value.utf8.count<=4096 && !value.contains(Self.credentialSlot)
                  }),env["PATH"]=="/usr/bin:/bin",env["LANG"]=="C",env["LC_ALL"]=="C",
                  let home=env["HOME"],(try? CommandEnvironment.sanitized(["HOME":home])) != nil,
                  let channel=value["credential_channel"] as? String,["argument","environment"].contains(channel) else {throw RuntimeError.invalid}
            let argumentCredential=channel=="argument"
            let slots=args.indices.filter {args[$0]==Self.credentialSlot}
            if argumentCredential {
                guard slots.count==1,let index=slots.first,index>0,args[index-1]=="--api-key" else {throw RuntimeError.invalid}
            } else {guard slots.isEmpty,!args.contains("--api-key") else {throw RuntimeError.invalid}}
            // Validate the named channel with a synthetic value, never a real
            // credential. Literal argument credentials cannot enter this file.
            var validationEnv=env
            if !argumentCredential {validationEnv["FIOS_MLX_SERVING_API_KEY"]="profile-validation"}
            _=try NativeServingLaunchInputs(arguments:args,environment:validationEnv,workingDirectory:cwd)
            self.host=host;self.uid=uid_t(uid);reviewSHA256=review;managerSHA256=manager;supervisorSHA256=supervisor
            serverSHA256=server;applicationSHA256=application;serverArtifact = version==1 ? .vendorBundle:.reviewedFiosNative;self.revision=revision
            statePath=state;workingDirectory=cwd;arguments=args;environment=env;self.argumentCredential=argumentCredential
        } catch {throw RuntimeError.invalid}
    }
    // Read-only target construction needs no serving secret. Unsupported local
    // bindings refuse construction instead of probing the old default port.
    func makeHealthProbe()throws->ServiceHealthProbe {
        try ServiceHealthProbe(reviewedInputs:resolvingCredential("health-target-only"))
    }
    // Correlation only: the manager can derive the expected profile without
    // reading the native serving key. Named credential values are excluded.
    func recoveryProfileHash(base:String,reviewedConfigurationSHA256:String)throws->String {
        let inputs=try resolvingCredential("profile-correlation-only")
        return try ServiceLaunchProfile.nativeDigest(base:base,arguments:inputs.arguments,environment:inputs.environment,
            workingDirectory:inputs.workingDirectory,reviewedConfigurationSHA256:reviewedConfigurationSHA256)
    }
    func resolvingCredential(_ secret:String)throws->NativeServingLaunchInputs {
        guard !secret.isEmpty,!secret.contains("\0"),secret.utf8.count<=4096 else {throw RuntimeError.invalid}
        var args=arguments,env=environment
        if argumentCredential {args=args.map {$0==Self.credentialSlot ? secret:$0}}
        else {env["FIOS_MLX_SERVING_API_KEY"]=secret}
        return try NativeServingLaunchInputs(arguments:args,environment:env,workingDirectory:workingDirectory)
    }
}
