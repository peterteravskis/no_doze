import AppKit
import CoreFoundation
import Foundation

enum NoDozeError: LocalizedError {
    case preferenceSyncFailed
    case caffeinateUnavailable

    var errorDescription: String? {
        switch self {
        case .preferenceSyncFailed:
            return "Could not save the screen saver setting."
        case .caffeinateUnavailable:
            return "Could not find /usr/bin/caffeinate."
        }
    }
}

final class ScreenSaverController {
    private let domain = "com.apple.screensaver" as CFString
    private let key = "idleTime" as CFString
    private var savedIdleTime: CFPropertyList?
    private var captured = false

    func disable() throws {
        if !captured {
            savedIdleTime = CFPreferencesCopyValue(
                key,
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            captured = true
        }

        CFPreferencesSetValue(
            key,
            NSNumber(value: 0),
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        guard CFPreferencesSynchronize(
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            throw NoDozeError.preferenceSyncFailed
        }
    }

    func restore() throws {
        guard captured else { return }

        CFPreferencesSetValue(
            key,
            savedIdleTime,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        guard CFPreferencesSynchronize(
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            throw NoDozeError.preferenceSyncFailed
        }

        savedIdleTime = nil
        captured = false
    }
}

final class CaffeinateController {
    private var process: Process?
    private var stopping = false
    var didExitUnexpectedly: (() -> Void)?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() throws {
        guard !isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/caffeinate") else {
            throw NoDozeError.caffeinateUnavailable
        }

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        newProcess.arguments = ["-dimsu", "-w", "\(getpid())"]
        newProcess.standardOutput = Pipe()
        newProcess.standardError = Pipe()
        newProcess.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.stopping {
                    self.process = nil
                    self.didExitUnexpectedly?()
                }
                self.stopping = false
            }
        }

        try newProcess.run()
        process = newProcess
    }

    func stop() {
        guard let currentProcess = process else { return }
        stopping = true

        if currentProcess.isRunning {
            currentProcess.terminate()
        }

        process = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let screenSaver = ScreenSaverController()
    private let caffeinate = CaffeinateController()
    private var window: NSWindow!
    private let toggleButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "NoDoze")
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private var active = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureWindow()

        caffeinate.didExitUnexpectedly = { [weak self] in
            guard let self else { return }
            self.active = false
            try? self.screenSaver.restore()
            self.refreshUI()
            self.showAlert(message: "caffeinate stopped unexpectedly.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            withTitle: "Quit NoDoze",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureWindow() {
        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        titleLabel.alignment = .center

        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        toggleButton.target = self
        toggleButton.action = #selector(toggle)
        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .large
        toggleButton.font = .systemFont(ofSize: 18, weight: .medium)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.widthAnchor.constraint(equalToConstant: 160).isActive = true
        toggleButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let stack = NSStackView(views: [titleLabel, statusLabel, toggleButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NoDoze"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshUI()
    }

    @objc private func toggle() {
        active ? stop() : start()
    }

    private func start() {
        do {
            try screenSaver.disable()
            try caffeinate.start()
            active = true
            refreshUI()
        } catch {
            caffeinate.stop()
            try? screenSaver.restore()
            active = false
            refreshUI()
            showAlert(message: error.localizedDescription)
        }
    }

    private func stop() {
        caffeinate.stop()
        do {
            try screenSaver.restore()
        } catch {
            showAlert(message: error.localizedDescription)
        }
        active = false
        refreshUI()
    }

    private func refreshUI() {
        toggleButton.title = active ? "Stop" : "Start"
        statusLabel.stringValue = active ? "Running" : "Ready"
    }

    private func showAlert(message: String) {
        guard window != nil else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "NoDoze"
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
