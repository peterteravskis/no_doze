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

private enum IconGlyph {
    case play
    case stop
    case timer
    case clock

    func draw(in rect: NSRect, color: NSColor, lineWidth: CGFloat = 2.0) {
        color.setStroke()
        color.setFill()

        switch self {
        case .play:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.2))
            path.line(to: NSPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY - rect.height * 0.2))
            path.line(to: NSPoint(x: rect.maxX - rect.width * 0.18, y: rect.midY))
            path.close()
            path.fill()
        case .stop:
            let side = min(rect.width, rect.height) * 0.52
            let square = NSRect(
                x: rect.midX - side / 2,
                y: rect.midY - side / 2,
                width: side,
                height: side
            )
            NSBezierPath(roundedRect: square, xRadius: side * 0.12, yRadius: side * 0.12).fill()
        case .timer:
            let side = min(rect.width, rect.height) * 0.68
            let bodyRect = NSRect(
                x: rect.midX - side / 2,
                y: rect.minY + rect.height * 0.18,
                width: side,
                height: side
            )
            let body = NSBezierPath(ovalIn: bodyRect)
            body.lineWidth = lineWidth
            body.stroke()

            let crownWidth = side * 0.36
            let crownRect = NSRect(
                x: rect.midX - crownWidth / 2,
                y: bodyRect.maxY - lineWidth / 2,
                width: crownWidth,
                height: side * 0.18
            )
            NSBezierPath(roundedRect: crownRect, xRadius: 2, yRadius: 2).fill()

            let hand = NSBezierPath()
            hand.lineWidth = lineWidth
            hand.lineCapStyle = .round
            hand.move(to: NSPoint(x: bodyRect.midX, y: bodyRect.midY))
            hand.line(to: NSPoint(x: bodyRect.midX, y: bodyRect.midY + bodyRect.height * 0.24))
            hand.move(to: NSPoint(x: bodyRect.midX, y: bodyRect.midY))
            hand.line(to: NSPoint(x: bodyRect.midX + bodyRect.width * 0.22, y: bodyRect.midY - bodyRect.height * 0.12))
            hand.stroke()
        case .clock:
            let bodyRect = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
            let body = NSBezierPath(ovalIn: bodyRect)
            body.lineWidth = lineWidth
            body.stroke()

            let hand = NSBezierPath()
            hand.lineWidth = lineWidth
            hand.lineCapStyle = .round
            hand.move(to: NSPoint(x: bodyRect.midX, y: bodyRect.midY))
            hand.line(to: NSPoint(x: bodyRect.midX, y: bodyRect.midY + bodyRect.height * 0.28))
            hand.move(to: NSPoint(x: bodyRect.midX, y: bodyRect.midY))
            hand.line(to: NSPoint(x: bodyRect.midX + bodyRect.width * 0.22, y: bodyRect.midY))
            hand.stroke()
        }
    }
}

private final class BackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class ChronometerPanelView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class BadgeIconView: NSView {
    var glyph: IconGlyph {
        didSet { needsDisplay = true }
    }

    init(glyph: IconGlyph) {
        self.glyph = glyph
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        glyph = .clock
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 40)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 2, dy: 2)
        let circle = NSBezierPath(ovalIn: circleRect)
        NSColor.controlBackgroundColor.setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()

        glyph.draw(in: circleRect.insetBy(dx: 8, dy: 8), color: .controlAccentColor, lineWidth: 2.1)
    }
}

private final class CircleIconButton: NSButton {
    var glyph: IconGlyph = .play {
        didSet { needsDisplay = true }
    }

    var activeStyle = false {
        didSet { needsDisplay = true }
    }

    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 78, height: 78)
    }

    private func commonInit() {
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        imagePosition = .imageOnly
        translatesAutoresizingMaskIntoConstraints = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = cell?.isHighlighted == true
        let circleRect = bounds.insetBy(dx: 4, dy: 4)
        let circle = NSBezierPath(ovalIn: circleRect)

        let fillColor: NSColor
        if activeStyle {
            fillColor = highlighted ? .selectedControlColor : .controlAccentColor
        } else if isHovering || highlighted {
            fillColor = .unemphasizedSelectedContentBackgroundColor
        } else {
            fillColor = .controlBackgroundColor
        }
        fillColor.setFill()
        circle.fill()

        (activeStyle ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        circle.lineWidth = activeStyle ? 1.5 : 1
        circle.stroke()

        let iconColor = activeStyle ? NSColor.selectedControlTextColor : NSColor.controlAccentColor
        glyph.draw(in: circleRect.insetBy(dx: 22, dy: 22), color: iconColor, lineWidth: 2.3)
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

private struct StopDeadline {
    let date: Date
    let reason: String
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTextFieldDelegate {
    private let screenSaver = ScreenSaverController()
    private let caffeinate = CaffeinateController()

    private var window: NSWindow!
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let statusSummaryMenuItem = NSMenuItem()
    private let statusTimerMenuItem = NSMenuItem()
    private let statusToggleMenuItem = NSMenuItem()
    private let statusWindowMenuItem = NSMenuItem()

    private let powerButton = CircleIconButton()
    private let titleLabel = NSTextField(labelWithString: "NoDoze")
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let detailLabel = NSTextField(labelWithString: "Timers off")

    private let durationCheckbox = NSButton(checkboxWithTitle: "Stop timer", target: nil, action: nil)
    private let durationField = NSTextField(string: "60")
    private let durationStepper = NSStepper()
    private let durationSummaryLabel = NSTextField(labelWithString: "Disabled")

    private let wallClockCheckbox = NSButton(checkboxWithTitle: "Wall clock stop", target: nil, action: nil)
    private let wallClockPicker = NSDatePicker()
    private let wallClockSummaryLabel = NSTextField(labelWithString: "Disabled")

    private var active = false
    private var autoStopTimer: Timer?
    private var countdownTimer: Timer?
    private var autoStopDeadline: Date?
    private var autoStopReason: String?
    private var lastStatusText = "Ready"

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureStatusItem()
        configureWindow()

        caffeinate.didExitUnexpectedly = { [weak self] in
            guard let self else { return }
            self.active = false
            self.cancelAutoStopTimers()
            try? self.screenSaver.restore()
            self.lastStatusText = "Stopped unexpectedly"
            self.refreshUI()
            self.showAlert(message: "caffeinate stopped unexpectedly.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop(statusText: "Ready")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenu()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === durationField {
            normalizeDurationField()
            refreshUI()
        }
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            withTitle: "Show NoDoze",
            action: #selector(showWindow),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(
            withTitle: "Start or Stop",
            action: #selector(toggle),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit NoDoze",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "NoDoze"
        statusItem = item

        statusMenu.delegate = self
        statusSummaryMenuItem.isEnabled = false
        statusTimerMenuItem.isEnabled = false

        statusToggleMenuItem.target = self
        statusToggleMenuItem.action = #selector(toggle)

        statusWindowMenuItem.target = self
        statusWindowMenuItem.action = #selector(toggleWindowVisibility)

        statusMenu.addItem(statusSummaryMenuItem)
        statusMenu.addItem(statusTimerMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(statusToggleMenuItem)
        statusMenu.addItem(statusWindowMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit NoDoze",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = statusMenu
        refreshStatusMenu()
    }

    private func configureWindow() {
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.alignment = .center

        powerButton.target = self
        powerButton.action = #selector(toggle)
        powerButton.widthAnchor.constraint(equalToConstant: 78).isActive = true
        powerButton.heightAnchor.constraint(equalToConstant: 78).isActive = true

        configureDurationControls()
        configureWallClockControls()

        let headerStack = NSStackView(views: [titleLabel, statusLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .centerX
        headerStack.spacing = 4

        let timerStack = NSStackView(views: [
            makeTimerPanel(icon: .timer, checkbox: durationCheckbox, controlRow: makeDurationControlRow(), summaryLabel: durationSummaryLabel),
            makeTimerPanel(icon: .clock, checkbox: wallClockCheckbox, controlRow: makeWallClockControlRow(), summaryLabel: wallClockSummaryLabel)
        ])
        timerStack.orientation = .vertical
        timerStack.alignment = .centerX
        timerStack.spacing = 8

        let stack = NSStackView(views: [headerStack, powerButton, detailLabel, timerStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = BackgroundView()
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NoDoze"
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshUI()
    }

    private func configureDurationControls() {
        styleCheckbox(durationCheckbox)
        durationCheckbox.target = self
        durationCheckbox.action = #selector(timerControlChanged)

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 1_440
        durationField.formatter = formatter
        durationField.delegate = self
        durationField.alignment = .right
        durationField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        durationField.textColor = .labelColor
        durationField.backgroundColor = .textBackgroundColor
        durationField.drawsBackground = true
        durationField.isBezeled = true
        durationField.bezelStyle = .roundedBezel
        durationField.focusRingType = .none
        durationField.translatesAutoresizingMaskIntoConstraints = false
        durationField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        durationField.heightAnchor.constraint(equalToConstant: 26).isActive = true

        durationStepper.minValue = 1
        durationStepper.maxValue = 1_440
        durationStepper.increment = 5
        durationStepper.integerValue = 60
        durationStepper.target = self
        durationStepper.action = #selector(durationStepperChanged)
    }

    private func configureWallClockControls() {
        styleCheckbox(wallClockCheckbox)
        wallClockCheckbox.target = self
        wallClockCheckbox.action = #selector(timerControlChanged)

        wallClockPicker.datePickerElements = [.hourMinute]
        wallClockPicker.datePickerStyle = .textFieldAndStepper
        wallClockPicker.dateValue = Date().addingTimeInterval(60 * 60)
        wallClockPicker.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        wallClockPicker.textColor = .labelColor
        wallClockPicker.backgroundColor = .textBackgroundColor
        wallClockPicker.drawsBackground = true
        wallClockPicker.isBezeled = true
        wallClockPicker.target = self
        wallClockPicker.action = #selector(timerControlChanged)
        wallClockPicker.translatesAutoresizingMaskIntoConstraints = false
        wallClockPicker.widthAnchor.constraint(equalToConstant: 112).isActive = true
        wallClockPicker.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func styleCheckbox(_ checkbox: NSButton) {
        checkbox.font = .systemFont(ofSize: 13, weight: .semibold)
        checkbox.contentTintColor = .controlAccentColor
    }

    private func makeTimerPanel(
        icon: IconGlyph,
        checkbox: NSButton,
        controlRow: NSView,
        summaryLabel: NSTextField
    ) -> NSView {
        let panel = ChronometerPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let iconView = BadgeIconView(glyph: icon)
        iconView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 40).isActive = true

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.alignment = .left

        let textStack = NSStackView(views: [checkbox, controlRow, summaryLabel])
        textStack.orientation = .vertical
        textStack.alignment = .left
        textStack.spacing = 3

        let row = NSStackView(views: [iconView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(row)

        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: 340),
            panel.heightAnchor.constraint(equalToConstant: 82),
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: panel.centerYAnchor)
        ])

        return panel
    }

    private func makeDurationControlRow() -> NSView {
        let unitLabel = makePanelLabel("min")
        let row = NSStackView(views: [durationField, durationStepper, unitLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeWallClockControlRow() -> NSView {
        let row = NSStackView(views: [wallClockPicker])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makePanelLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func toggle() {
        active ? stop(statusText: "Ready") : start()
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshStatusMenu()
    }

    @objc private func toggleWindowVisibility() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
        refreshStatusMenu()
    }

    @objc private func timerControlChanged() {
        normalizeDurationField()
        refreshUI()
    }

    @objc private func durationStepperChanged() {
        durationField.integerValue = durationStepper.integerValue
        refreshUI()
    }

    private func start() {
        do {
            normalizeDurationField()
            let configuredDeadline = nextConfiguredStopDeadline()

            try screenSaver.disable()
            try caffeinate.start()

            active = true
            lastStatusText = "Running"
            autoStopDeadline = configuredDeadline?.date
            autoStopReason = configuredDeadline?.reason
            scheduleAutoStop()
            refreshUI()
        } catch {
            caffeinate.stop()
            cancelAutoStopTimers()
            try? screenSaver.restore()
            active = false
            lastStatusText = "Ready"
            refreshUI()
            showAlert(message: error.localizedDescription)
        }
    }

    private func stop(statusText: String) {
        cancelAutoStopTimers()
        caffeinate.stop()
        do {
            try screenSaver.restore()
        } catch {
            showAlert(message: error.localizedDescription)
        }
        active = false
        lastStatusText = statusText
        refreshUI()
    }

    private func stopAutomatically() {
        let reason = autoStopReason ?? "timer"
        stop(statusText: "Stopped by \(reason)")
    }

    private func scheduleAutoStop() {
        cancelAutoStopTimers()

        if let autoStopDeadline {
            let interval = max(0.5, autoStopDeadline.timeIntervalSinceNow)
            autoStopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.stopAutomatically()
            }
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }
    }

    private func cancelAutoStopTimers() {
        autoStopTimer?.invalidate()
        countdownTimer?.invalidate()
        autoStopTimer = nil
        countdownTimer = nil
        autoStopDeadline = nil
        autoStopReason = nil
    }

    private func nextConfiguredStopDeadline() -> StopDeadline? {
        let now = Date()
        var deadlines: [StopDeadline] = []

        if durationCheckbox.state == .on {
            let durationDate = now.addingTimeInterval(TimeInterval(durationMinutes() * 60))
            deadlines.append(StopDeadline(date: durationDate, reason: "stop timer"))
        }

        if wallClockCheckbox.state == .on {
            deadlines.append(StopDeadline(date: wallClockStopDate(after: now), reason: "wall clock"))
        }

        return deadlines.min { $0.date < $1.date }
    }

    private func wallClockStopDate(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let clockParts = calendar.dateComponents([.hour, .minute], from: wallClockPicker.dateValue)
        var targetParts = calendar.dateComponents([.year, .month, .day], from: now)
        targetParts.hour = clockParts.hour
        targetParts.minute = clockParts.minute
        targetParts.second = 0

        guard var target = calendar.date(from: targetParts) else {
            return now.addingTimeInterval(60 * 60)
        }

        if target <= now {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? now.addingTimeInterval(24 * 60 * 60)
        }

        return target
    }

    private func durationMinutes() -> Int {
        max(1, min(1_440, durationField.integerValue))
    }

    private func normalizeDurationField() {
        let minutes = durationMinutes()
        durationField.integerValue = minutes
        durationStepper.integerValue = minutes
    }

    private func refreshUI() {
        powerButton.glyph = active ? .stop : .play
        powerButton.activeStyle = active
        powerButton.setAccessibilityLabel(active ? "Stop NoDoze" : "Start NoDoze")

        statusLabel.stringValue = active ? "Running" : lastStatusText
        statusLabel.textColor = active ? .controlAccentColor : .secondaryLabelColor

        let detail = detailText()
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty

        refreshTimerSummaries()
        refreshControlStates()
        refreshStatusMenu()
    }

    private func refreshTimerSummaries() {
        if durationCheckbox.state == .on {
            durationSummaryLabel.stringValue = "After \(durationMinutes()) min"
            durationSummaryLabel.textColor = .controlAccentColor
        } else {
            durationSummaryLabel.stringValue = "Disabled"
            durationSummaryLabel.textColor = .secondaryLabelColor
        }

        if wallClockCheckbox.state == .on {
            wallClockSummaryLabel.stringValue = wallClockSummaryText()
            wallClockSummaryLabel.textColor = .controlAccentColor
        } else {
            wallClockSummaryLabel.stringValue = "Disabled"
            wallClockSummaryLabel.textColor = .secondaryLabelColor
        }
    }

    private func refreshControlStates() {
        durationCheckbox.isEnabled = !active
        wallClockCheckbox.isEnabled = !active
        durationField.isEnabled = !active && durationCheckbox.state == .on
        durationStepper.isEnabled = !active && durationCheckbox.state == .on
        wallClockPicker.isEnabled = !active && wallClockCheckbox.state == .on
    }

    private func refreshStatusMenu() {
        statusItem?.button?.image = statusImage(active: active)
        statusItem?.button?.toolTip = active ? "NoDoze running" : "NoDoze ready"

        statusSummaryMenuItem.title = active ? "NoDoze: Running" : "NoDoze: \(lastStatusText)"
        statusTimerMenuItem.title = menuTimerText()
        statusToggleMenuItem.title = active ? "Stop" : "Start"
        statusWindowMenuItem.title = window?.isVisible == true ? "Hide Window" : "Show Window"
    }

    private func detailText() -> String {
        if active, let autoStopDeadline {
            return "Stops in \(remainingText(until: autoStopDeadline)) at \(timeFormatter.string(from: autoStopDeadline))"
        }

        if active {
            return "Manual stop"
        }

        if durationCheckbox.state == .on || wallClockCheckbox.state == .on {
            return "Timer armed for next start"
        }

        return ""
    }

    private func menuTimerText() -> String {
        if active, let autoStopDeadline {
            return "Auto-stop: \(remainingText(until: autoStopDeadline))"
        }

        if durationCheckbox.state == .off && wallClockCheckbox.state == .off {
            return "Auto-stop: Disabled"
        }

        return "Auto-stop: Armed for next start"
    }

    private func wallClockSummaryText() -> String {
        let target = wallClockStopDate()
        let timeText = timeFormatter.string(from: target)
        if Calendar.current.isDateInToday(target) {
            return "At \(timeText)"
        }
        return "Tomorrow at \(timeText)"
    }

    private func remainingText(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        return "\(remainingSeconds)s"
    }

    private func statusImage(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let circle = NSBezierPath(ovalIn: circleRect)
            (active ? NSColor.controlAccentColor : NSColor.clear).setFill()
            circle.fill()

            (active ? NSColor.controlAccentColor : NSColor.labelColor).setStroke()
            circle.lineWidth = 1.4
            circle.stroke()

            let glyphRect = circleRect.insetBy(dx: 4.8, dy: 4.8)
            (active ? IconGlyph.stop : IconGlyph.play).draw(
                in: glyphRect,
                color: active ? .selectedControlTextColor : .labelColor,
                lineWidth: 1.8
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private func showAlert(message: String) {
        guard window != nil else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "NoDoze"
        alert.informativeText = message

        if window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
