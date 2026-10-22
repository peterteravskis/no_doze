import Foundation
import IOKit.pwr_mgt

/// Keeps user activity alive for the entire session. caffeinate's -u assertion
/// expires after five seconds unless given a timeout; -w does not extend it.
final class UserActivityController {
    typealias DeclareActivity = (inout IOPMAssertionID) -> IOReturn

    private let refreshInterval: TimeInterval
    private let declareActivity: DeclareActivity
    private let releaseActivity: (IOPMAssertionID) -> IOReturn
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var timer: Timer?
    var didFail: ((Error) -> Void)?

    init(
        refreshInterval: TimeInterval = 15,
        declareActivity: @escaping DeclareActivity = {
            IOPMAssertionDeclareUserActivity("NoDoze keep awake" as CFString, kIOPMUserActiveLocal, &$0)
        },
        releaseActivity: @escaping (IOPMAssertionID) -> IOReturn = { IOPMAssertionRelease($0) }
    ) {
        self.refreshInterval = refreshInterval
        self.declareActivity = declareActivity
        self.releaseActivity = releaseActivity
    }

    deinit {
        stop()
    }

    func start() throws {
        guard timer == nil else { return }
        do {
            try refresh()
        } catch {
            stop()
            throw error
        }

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            do {
                try self.refresh()
            } catch {
                self.stop()
                self.didFail?(error)
            }
        }
        timer.tolerance = min(1, refreshInterval / 10)
        self.timer = timer
        // Keep protecting the session while a menu or dial is tracking input.
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if assertionID != kIOPMNullAssertionID {
            _ = releaseActivity(assertionID)
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }
    }

    private func refresh() throws {
        let result = declareActivity(&assertionID)
        guard result == kIOReturnSuccess else {
            throw NoDozeError.activityAssertionFailed(result)
        }
    }
}

final class CaffeinateController {
    private var process: Process?
    var didExitUnexpectedly: (() -> Void)?

    var isRunning: Bool { process?.isRunning == true }
    var processIdentifier: Int32? { process?.processIdentifier }

    deinit {
        stop()
    }

    func start() throws {
        guard !isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/caffeinate") else {
            throw NoDozeError.caffeinateUnavailable
        }

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // UserActivityController maintains activity separately, without a
        // five-second timeout on the disk or user-activity assertions.
        newProcess.arguments = ["-dims", "-w", "\(getpid())"]
        newProcess.standardOutput = FileHandle.nullDevice
        newProcess.standardError = FileHandle.nullDevice
        newProcess.terminationHandler = { [weak self] exitedProcess in
            DispatchQueue.main.async {
                // A delayed callback from Stop must never clear a newer run.
                guard let self, self.process === exitedProcess else { return }
                self.process = nil
                self.didExitUnexpectedly?()
            }
        }

        try newProcess.run()
        process = newProcess
    }

    func stop() {
        guard let currentProcess = process else { return }
        process = nil
        if currentProcess.isRunning {
            currentProcess.terminate()
        }
    }
}
