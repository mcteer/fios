import Foundation

// Ordinary journal bookkeeping only. Scopes/completion below are synthetic
// unit inputs; no worker, native request, SDK handle or terminal proof exists.
func runInferenceRetentionTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    let jobs=(0..<3).map {_ in UUID().uuidString.lowercased()}
    let scope=InferenceScope(host:"fixture-host",endpointHash:String(repeating:"a",count:64),
        profileHash:String(repeating:"b",count:64),managerEpoch:UUID().uuidString.lowercased(),
        nativeEpoch:"fixture-native",canonicalModel:"fixture/model",nativeModel:"fixture/model",sequence:1,sampledAt:1000)
    do {
        let journal=try Journal(directory:directory)
        for job in jobs {
            try journal.claim(job:job,attempt:0,model:scope.canonicalModel,scope:scope)
            try journal.markDispatched(job:job,attempt:0)
        }
        try journal.markUncertain(job:jobs[0],attempt:0)
        guard try journal.unresolvedCount()==3,try journal.uncertainCount()==1 else {throw JournalError.invalid}
    }
    do {
        let journal=try Journal(directory:directory)
        guard try journal.unresolvedCount()==3,try journal.uncertainCount()==3 else {throw JournalError.invalid}
        for job in jobs {
            guard let record=try journal.inferenceScope(job:job,attempt:0),record.state == .uncertain,
                  try record.scope.encoded()==scope.encoded() else {throw JournalError.invalid}
        }
        // Exercise the trusted low-level completion operation with a unit
        // scope. This is not evidence of actual native completion.
        try journal.resolveInference(job:jobs[2],attempt:0,scope:scope,outcome:.complete)
        guard try journal.unresolvedCount()==2,try journal.uncertainCount()==2,
              try journal.inferenceScope(job:jobs[0],attempt:0)?.state == .uncertain,
              try journal.inferenceScope(job:jobs[1],attempt:0)?.state == .uncertain else {throw JournalError.invalid}
    }
    print("PASS: three retained inference records reopen; newer fixture completion preserves older uncertainty")
}
