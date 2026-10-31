import Foundation

// Dependency-free assertions: this host's Command Line Tools lack XCTest and
// Swift Testing plugins. Compiled with core sources by check-platform.mjs.
private func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs) }
private func XCTAssertTrue(_ value: Bool) { precondition(value) }
private func XCTAssertFalse(_ value: Bool) { precondition(!value) }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression() } catch { return }
    preconditionFailure("Expected rejection")
}

final class ActivityTests {
    private func observation(
        model: String? = "model-a", owners: Int = 0, loading: Bool = false,
        complete: Bool = true, sampled: Int64 = 10_000, epoch: String = "server-1"
    ) -> NativeSnapshot {
        NativeSnapshot(host: "edge-a", endpointHash: String(repeating: "a", count: 64),
                       nativeEpoch: epoch, sequence: 1, sampledAt: sampled,
                       allClientLifecycleCoverage: complete, residentModel: model,
                       outstandingOwners: owners, loading: loading)
    }

    func testIdleRequiresAuthoritativeAllClientCoverage() throws {
        XCTAssertEqual(try ActivityPolicy.evaluate(observation(), now: 10_000), .idle)
        XCTAssertEqual(try ActivityPolicy.evaluate(observation(epoch:String(repeating:"é",count:64)), now:10_000), .idle)
        XCTAssertEqual(try ActivityPolicy.evaluate(observation(complete: false), now: 10_000), .unknown)
    }

    func testQueuedPreparingAndResponseOwnersAreBusy() throws {
        XCTAssertEqual(try ActivityPolicy.evaluate(observation(owners: 1), now: 10_000), .busy(model: "model-a"))
        XCTAssertEqual(try ActivityPolicy.evaluate(observation(loading: true), now: 10_000), .preparing)
    }

    func testStaleFutureAndMalformedSamplesReject() {
        for epoch in ["", "server\u{0}1", String(repeating:"é",count:65)] {
            do {
                _ = try ActivityPolicy.evaluate(observation(epoch:epoch), now:10_000)
                fatalError("FIO_ACTIVITY_INVALID_EPOCH_ACCEPTED")
            } catch PolicyError.invalidObservation {} catch {
                fatalError("Malformed epoch reported as a different policy failure")
            }
        }
        XCTAssertThrowsError(try ActivityPolicy.evaluate(observation(sampled: 4_999), now: 10_000))
        XCTAssertThrowsError(try ActivityPolicy.evaluate(observation(sampled: 11_001), now: 10_000))
        XCTAssertThrowsError(try ActivityPolicy.evaluate(observation(owners: -1), now: 10_000))
    }

    func testIdleReplacementIsAllowedButBusySwitchIsNot() throws {
        XCTAssertTrue(try ActivityPolicy.permits(target: "model-b", snapshot: observation(), now: 10_000))
        XCTAssertTrue(try ActivityPolicy.permits(target: "model-a", snapshot: observation(owners: 2), now: 10_000))
        XCTAssertFalse(try ActivityPolicy.permits(target: "model-b", snapshot: observation(owners: 2), now: 10_000))
        XCTAssertFalse(try ActivityPolicy.permits(target: "model-a", snapshot: observation(complete: false), now: 10_000))
    }

    func testNewerSuccessDoesNotClearEarlierUncertainty() throws {
        var ownership = InferenceOwnership()
        try ownership.claim(request: "old", model: "model-a")
        try ownership.markUncertain(request: "old")
        try ownership.claim(request: "new", model: "model-a")
        try ownership.complete(request: "new")
        XCTAssertEqual(ownership.unresolvedCount, 1)
        XCTAssertThrowsError(try ownership.claim(request: "other", model: "model-b"))
    }

    func testDuplicateAndUnknownCompletionFailClosed() throws {
        var ownership = InferenceOwnership()
        try ownership.claim(request: "a", model: "model-a")
        XCTAssertThrowsError(try ownership.claim(request: "a", model: "model-a"))
        XCTAssertThrowsError(try ownership.complete(request: "missing"))
        XCTAssertEqual(ownership.unresolvedCount, 1)
    }

    func testOwnershipIsBoundedAndRestartDoesNotRelease() throws {
        var ownership = InferenceOwnership()
        for i in 0..<32 { try ownership.claim(request: "r\(i)", model: "model-a") }
        XCTAssertThrowsError(try ownership.claim(request: "overflow", model: "model-a"))
        ownership.recoverAfterRestart()
        XCTAssertEqual(ownership.unresolvedCount, 32)
        XCTAssertEqual(ownership.uncertainCount, 32)
    }
}
