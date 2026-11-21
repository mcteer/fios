import Foundation

// Ordinary journal/source metadata. No native process, model or terminal proof.
func runDurableLineageTests() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer {try? FileManager.default.removeItem(at:root)}
    let directory=root.appendingPathComponent("state")
    let job=UUID().uuidString.lowercased(),other=UUID().uuidString.lowercased()
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),profileHash:String(repeating:"b",count:64),
        managerEpoch:UUID().uuidString.lowercased(),nativeEpoch:String(repeating:"1",count:32),canonicalModel:"test/model",nativeModel:"test/model",sequence:1,sampledAt:10000)
    let peer=NativeControlPeer(pid:42,start:UInt64.max,executable:try VerifiedExecutable(path:"/fixture/native",sha256:String(repeating:"c",count:64)))
    let id=try scope.nativeRequestCorrelationID(job:job,attempt:0)
    func sample(_ sequence:UInt64,at:Int64,root:UInt64=UInt64.max,found:Bool=true)->NativeRequestLineageSample {
        NativeRequestLineageSample(peer:peer,sampledAt:at,lineage:NativeRequestLineage(instance:scope.nativeEpoch,correlationID:id,
            sampleSequence:sequence,rootSequence:found ? root:0,found:found,uncertain:!found,references:found ? 1:0,
            owners:found ? 1:0,ingress:0,preparing:found ? 1:0,active:0,responding:0))
    }
    func live(_ value:NativeRequestLineageObservation) {guard case .live=value else {fatalError("Ordinary durable lineage was lost")}}
    func unknown(_ value:NativeRequestLineageObservation) {guard case .unknown=value else {fatalError("Unknown lineage became native authority")}}
    do {
        let journal=try Journal(directory:directory)
        try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
        try journal.markDispatched(job:job,attempt:0)
        live(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(1,at:10000),now:10000))
        unknown(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(2,at:10001,found:false),now:10001))
        guard try journal.unresolvedCount()==1 else {throw JournalError.invalid}
    }
    do {
        let journal=try Journal(directory:directory)
        unknown(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(1,at:10002),now:10002))
        live(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(3,at:10003),now:10003))
        guard try journal.inferenceScope(job:job,attempt:0)?.state == .uncertain else {throw JournalError.invalid}
        // A newer unit completion cannot delete the older native correlation.
        try journal.claim(job:other,attempt:0,model:scope.canonicalModel,scope:scope)
        try journal.markDispatched(job:other,attempt:0)
        try journal.resolveInference(job:other,attempt:0,scope:scope,outcome:.complete)
        unknown(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(4,at:10004,root:7),now:10004))
        guard try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {throw JournalError.invalid}
    }
    do {
        let journal=try Journal(directory:directory)
        unknown(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(5,at:10005),now:10005))
        guard try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {throw JournalError.invalid}
    }
    do {_=try ArtifactStore(directory:directory.appendingPathComponent("artifacts"),availableBytes:{100<<30})}
    let backup=root.appendingPathComponent("backup"),restored=root.appendingPathComponent("restored")
    let receipt=try StoppedStateBackup.create(directory:directory,destination:backup)
    _=try StoppedStateBackup.restore(directory:backup,expectedSHA256:receipt.sha256,destination:restored)
    do {
        let journal=try Journal(directory:restored)
        unknown(try journal.observeLineage(job:job,attempt:0,scope:scope,peer:peer,sample:sample(6,at:10006),now:10006))
        guard try journal.unresolvedCount()==1,try journal.uncertainCount()==1 else {throw JournalError.invalid}
    }
    print("PASS: durable full-width native root/peer, sequence and unknown-gap retention across restart; newer unit completion preserves older uncertainty; sticky changed-root refusal survives stopped backup/restore")
}
