import XCTest
import IOKit.pwr_mgt
@testable import NoDoze

final class UserActivityTests: XCTestCase {
    func testActivityRenewsAndTracksReplacementAssertionIDs() throws {
        var receivedIDs: [IOPMAssertionID] = []
        var releasedIDs: [IOPMAssertionID] = []
        let controller = UserActivityController(refreshInterval: 0.02, declareActivity: { id in
            receivedIDs.append(id)
            id += 1
            return kIOReturnSuccess
        }, releaseActivity: { id in
            releasedIDs.append(id)
            return kIOReturnSuccess
        })
        defer { controller.stop() }

        try controller.start()
        try controller.start()
        XCTAssertEqual(receivedIDs, [0])
        runUntil { receivedIDs.count >= 3 }
        XCTAssertGreaterThanOrEqual(receivedIDs.count, 3)
        XCTAssertEqual(Array(receivedIDs.prefix(3)), [0, 1, 2])
        let finalID = IOPMAssertionID(receivedIDs.count)

        controller.stop()
        controller.stop()
        XCTAssertEqual(releasedIDs, [finalID])
        let countAfterStop = receivedIDs.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(receivedIDs.count, countAfterStop)

        try controller.start()
        XCTAssertEqual(receivedIDs.last, 0)
    }

    func testInitialFailureDoesNotStartRenewals() {
        var attempts = 0
        let controller = UserActivityController(refreshInterval: 0.01, declareActivity: { _ in
            attempts += 1
            return kIOReturnError
        })
        XCTAssertThrowsError(try controller.start())
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertEqual(attempts, 1)
    }

    func testRenewalFailureReleasesAssertionAndReportsFailureOnce() throws {
        var attempts = 0
        var releases = 0
        var failures = 0
        let controller = UserActivityController(refreshInterval: 0.01, declareActivity: { id in
            attempts += 1
            id = 42
            return attempts == 1 ? kIOReturnSuccess : kIOReturnError
        }, releaseActivity: { id in
            XCTAssertEqual(id, 42)
            releases += 1
            return kIOReturnSuccess
        })
        controller.didFail = { _ in failures += 1 }
        try controller.start()
        runUntil { failures > 0 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(failures, 1)
    }
}

final class CaffeinateTests: XCTestCase {
    func testRepeatedStartKeepsOneProcessAndStopTerminatesIt() throws {
        let controller = CaffeinateController()
        defer { controller.stop() }
        try controller.start()
        let pid = try XCTUnwrap(controller.processIdentifier)
        try controller.start()
        XCTAssertEqual(controller.processIdentifier, pid)
        XCTAssertTrue(controller.isRunning)

        controller.stop()
        XCTAssertFalse(controller.isRunning)
        runUntil { kill(pid, 0) != 0 }
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    func testOldTerminationCallbacksCannotStopANewSession() throws {
        let controller = CaffeinateController()
        defer { controller.stop() }
        var unexpectedExits = 0
        var stoppedPIDs: [Int32] = []
        controller.didExitUnexpectedly = { unexpectedExits += 1 }

        for _ in 0..<5 {
            try controller.start()
            stoppedPIDs.append(try XCTUnwrap(controller.processIdentifier))
            controller.stop()
        }
        try controller.start()
        let currentPID = controller.processIdentifier
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(unexpectedExits, 0)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(controller.processIdentifier, currentPID)
        for pid in stoppedPIDs {
            XCTAssertNotEqual(kill(pid, 0), 0)
        }
    }

    func testUnexpectedTerminationIsReported() throws {
        let controller = CaffeinateController()
        defer { controller.stop() }
        var unexpectedExits = 0
        controller.didExitUnexpectedly = { unexpectedExits += 1 }
        try controller.start()
        let pid = try XCTUnwrap(controller.processIdentifier)
        XCTAssertEqual(kill(pid, SIGTERM), 0)
        runUntil { unexpectedExits > 0 }
        XCTAssertEqual(unexpectedExits, 1)
        XCTAssertNil(controller.processIdentifier)
        XCTAssertFalse(controller.isRunning)
    }
}

final class ScreenSaverTests: XCTestCase {
    private var domain: CFString!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "local.nodoze.tests.\(UUID().uuidString)"
        domain = suite as CFString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        setIdleTime(nil)
        defaults.removePersistentDomain(forName: suite)
    }

    func testNonzeroTimerIsRestoredAfterRepeatedStartAndStop() throws {
        setIdleTime(1800)
        let controller = makeController()
        try controller.disable()
        try controller.disable()
        XCTAssertEqual(idleTime, 0)
        try controller.restore()
        try controller.restore()
        XCTAssertEqual(idleTime, 1800)
        XCTAssertFalse(controller.hasPendingInterruptedRestore)
    }

    func testMissingPreferenceIsRemovedOnRestore() throws {
        XCTAssertNil(idleTime)
        let controller = makeController()
        try controller.disable()
        XCTAssertEqual(idleTime, 0)
        try controller.restore()
        XCTAssertNil(idleTime)
    }

    func testAlreadyDisabledTimerStaysDisabled() throws {
        setIdleTime(0)
        let controller = makeController()
        try controller.disable()
        XCTAssertFalse(controller.hasPendingInterruptedRestore)
        try controller.restore()
        XCTAssertEqual(idleTime, 0)
    }

    func testInterruptedRunBlocksStartAndRecoversOriginalTimer() throws {
        setIdleTime(900)
        try makeController().disable()
        let relaunchedController = makeController()
        let details = try XCTUnwrap(relaunchedController.pendingRestoreDetails)
        XCTAssertEqual(details.restoreState, ScreenSaverIdleState(wasSet: true, seconds: 900))
        XCTAssertEqual(details.currentState, ScreenSaverIdleState(wasSet: true, seconds: 0))
        XCTAssertThrowsError(try relaunchedController.disable())
        try relaunchedController.restorePendingInterruptedState(details.restoreState)
        XCTAssertEqual(idleTime, 900)
        XCTAssertFalse(relaunchedController.hasPendingInterruptedRestore)
    }

    func testKeepCurrentDiscardsRecoveryWithoutChangingPreference() throws {
        setIdleTime(600)
        try makeController().disable()
        let relaunchedController = makeController()
        relaunchedController.discardPendingInterruptedState()
        XCTAssertEqual(idleTime, 0)
        XCTAssertFalse(relaunchedController.hasPendingInterruptedRestore)
    }

    private func makeController() -> ScreenSaverController {
        ScreenSaverController(domain: domain, defaults: defaults)
    }

    private var idleTime: Int? {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return (CFPreferencesCopyValue("idleTime" as CFString, domain,
                                       kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? NSNumber)?.intValue
    }

    private func setIdleTime(_ seconds: Int?) {
        CFPreferencesSetValue("idleTime" as CFString, seconds.map { NSNumber(value: $0) }, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        XCTAssertTrue(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost))
    }
}

private func runUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}
