// Pure state primitive. The eventual journal must persist this state before
// any actual inference dispatch; this type alone is not durable enforcement.
struct InferenceOwnership: Sendable {
    private struct Entry: Sendable {
        let model: String
        var uncertain: Bool
    }
    private var entries: [String: Entry] = [:]

    var unresolvedCount: Int { entries.count }
    var uncertainCount: Int { entries.values.filter(\.uncertain).count }

    mutating func claim(request: String, model: String) throws {
        guard !request.isEmpty, request.utf8.count <= 128,
              WireScalar.model(model) else { throw PolicyError.invalidObservation }
        guard entries[request] == nil else { throw PolicyError.duplicateRequest }
        guard entries.count < 32 else { throw PolicyError.trackingLimit }
        guard entries.values.allSatisfy({ WireScalar.exactModel($0.model,model) }) else { throw PolicyError.conflictingModel }
        entries[request] = Entry(model: model, uncertain: false)
    }

    mutating func markUncertain(request: String) throws {
        guard entries[request] != nil else { throw PolicyError.unknownRequest }
        entries[request]?.uncertain = true
    }

    // Caller must possess correlated completion/non-dispatch/native proof.
    // This method is not exposed as an untrusted control operation.
    mutating func complete(request: String) throws {
        guard entries.removeValue(forKey: request) != nil else { throw PolicyError.unknownRequest }
    }

    mutating func recoverAfterRestart() {
        for key in Array(entries.keys) { entries[key]?.uncertain = true }
    }
}
