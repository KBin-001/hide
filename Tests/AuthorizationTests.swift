import XCTest
@testable import CalculatorCore

private actor DelayedAuthorization {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

final class AuthorizationTests: XCTestCase {
    @MainActor
    func testUnresponsiveServiceTimesOutWithoutJoiningAndRejectsDuplicate() async {
        let probe = AuthorizationProbe()
        let service = DelayedAuthorization()
        let timedOut = expectation(description: "Unresponsive service stops showing an endless request")
        let returned = expectation(description: "Late system result is accepted")
        probe.onEvent = { event in
            switch event {
            case .timedOut: timedOut.fulfill()
            case .completed(.approved): returned.fulfill()
            default: break
            }
        }
        XCTAssertTrue(probe.start(timeoutNanoseconds: 50_000_000) { report in
            report(.requesting)
            await service.wait()
            return .approved
        })
        await fulfillment(of: [timedOut], timeout: 2)
        XCTAssertTrue(probe.isPending, "Timeout cannot cancel an OS authorization request")
        XCTAssertFalse(probe.start { _ in XCTFail("Must not start duplicate requests"); return .denied })
        await service.release()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertFalse(probe.isPending)
    }

    @MainActor
    func testStageProgressAfterTimeoutRearmsDeadlineAndAcceptsLateSuccess() async {
        let probe = AuthorizationProbe()
        let initializing = DelayedAuthorization()
        let requesting = DelayedAuthorization()
        let firstTimeout = expectation(description: "Initialization waits too long")
        let requestProgress = expectation(description: "Late initialization still advances")
        let secondTimeout = expectation(description: "New stage has its own deadline")
        let completed = expectation(description: "Late approval remains valid")
        probe.onEvent = { event in
            switch event {
            case .timedOut(.initializing): firstTimeout.fulfill()
            case .progress(.requesting): requestProgress.fulfill()
            case .timedOut(.requesting): secondTimeout.fulfill()
            case .completed(.approved): completed.fulfill()
            default: break
            }
        }
        probe.start(timeoutNanoseconds: 100_000_000) { report in
            report(.initializing)
            await initializing.wait()
            report(.requesting)
            await requesting.wait()
            return .approved
        }
        await fulfillment(of: [firstTimeout], timeout: 2)
        await initializing.release()
        await fulfillment(of: [requestProgress, secondTimeout], timeout: 2, enforceOrder: true)
        XCTAssertFalse(probe.start { _ in XCTFail("Pending request must not be duplicated"); return .denied })
        await requesting.release()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertFalse(probe.isPending)
    }

    @MainActor
    func testDeadlineAppliesPerStageRatherThanWholeConnection() async {
        let probe = AuthorizationProbe()
        let completed = expectation(description: "Combined duration exceeds one stage budget")
        probe.onEvent = { event in
            if case .timedOut = event { XCTFail("Progress must reset the stage deadline") }
            if case .completed(.approved) = event { completed.fulfill() }
        }
        probe.start(timeoutNanoseconds: 500_000_000) { report in
            report(.initializing)
            try await Task.sleep(nanoseconds: 300_000_000)
            report(.requesting)
            try await Task.sleep(nanoseconds: 300_000_000)
            return .approved
        }
        await fulfillment(of: [completed], timeout: 3)
    }

    @MainActor
    func testSystemErrorRemainsAvailableAndAllowsRetry() async {
        let probe = AuthorizationProbe()
        let failed = expectation(description: "System error is propagated")
        probe.onEvent = { event in
            if case .failed(let error) = event {
                let error = error as NSError
                XCTAssertEqual(error.domain, "AuthorizationTest")
                XCTAssertEqual(error.code, 42)
                failed.fulfill()
            }
        }
        probe.start { _ in throw NSError(domain: "AuthorizationTest", code: 42) }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertFalse(probe.isPending)
        let success = expectation(description: "Retry returns authorization")
        probe.onEvent = { if case .completed(.approved) = $0 { success.fulfill() } }
        XCTAssertTrue(probe.start { _ in .approved })
        await fulfillment(of: [success], timeout: 2)
    }
}
