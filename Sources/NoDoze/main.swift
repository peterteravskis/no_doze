import AppKit
import CoreFoundation
import Foundation

private let appAccentColor = NSColor.systemOrange

private func fittingSystemFont(
    for text: String,
    maxWidth: CGFloat,
    baseSize: CGFloat,
    weight: NSFont.Weight,
    minSize: CGFloat
) -> NSFont {
    var size = baseSize
    while size > minSize {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        if textWidth <= maxWidth {
            return font
        }
        size -= 0.5
    }
    return NSFont.systemFont(ofSize: minSize, weight: weight)
}

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
        }
    }
}

private final class BackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class DialView: NSControl {
    enum Mode {
        case timer
        case clock24
    }

    var mode: Mode = .timer {
        didSet {
            setAccessibilityRole(mode == .timer ? .button : .incrementor)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var valueText = "--" {
        didSet { needsDisplay = true }
    }

    var progress: CGFloat = 0 {
        didSet {
            progress = min(1, max(0, progress))
            needsDisplay = true
        }
    }

    var showsTicks = false {
        didSet { needsDisplay = true }
    }

    var isArmed = false {
        didSet { needsDisplay = true }
    }

    var currentMinuteOfDay = 0 {
        didSet { needsDisplay = true }
    }

    var stopMinuteOfDay = 0 {
        didSet { needsDisplay = true }
    }

    var timerNumberClicked: (() -> Void)?
    var clockMinuteChanged: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override var acceptsFirstResponder: Bool { true }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 80, height: 80)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: mode == .timer ? .pointingHand : .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)

        switch mode {
        case .timer:
            timerNumberClicked?()
        case .clock24:
            NSCursor.closedHand.set()
            updateClockMinute(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, mode == .clock24 else { return }
        updateClockMinute(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .clock24 else { return }
        NSCursor.openHand.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height) - 5
        let scale = side / 160
        let circleRect = NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
        let radius = side / 2 - (7 * scale)
        let featureRadius = radius - scale

        let circle = NSBezierPath(ovalIn: circleRect.insetBy(dx: 8 * scale, dy: 8 * scale))
        NSColor.controlBackgroundColor.setFill()
        circle.fill()

        NSColor.separatorColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()

        switch mode {
        case .timer:
            if showsTicks {
                drawTicks(center: center, radius: radius + (7 * scale))
            }
            drawProgress(center: center, radius: radius)
        case .clock24:
            drawTicks(center: center, radius: featureRadius)
            drawClockMarkers(center: center, radius: featureRadius)
        }

        drawValue(in: circleRect)
    }

    private func drawTicks(center: NSPoint, radius: CGFloat) {
        let tickCount = mode == .clock24 ? 96 : 32
        let scale = max(0.45, radius / 80)

        for index in 0..<tickCount {
            let angle = pointAngle(for: CGFloat(index) / CGFloat(tickCount))
            let isHourTick = mode == .clock24 && index % 4 == 0
            let isHalfHourTick = mode == .clock24 && index % 2 == 0
            let tickLength: CGFloat
            if isHourTick || (mode == .timer && index % 4 == 0) {
                tickLength = 13 * scale
            } else if isHalfHourTick {
                tickLength = 8 * scale
            } else {
                tickLength = 4 * scale
            }
            let tickLineWidth = max(1.0, (isHourTick || isHalfHourTick) ? 2.6 * scale : 1.55 * scale)
            let endRadius = max(0, radius - tickLineWidth / 2)
            let innerRadius = endRadius - tickLength
            let start = NSPoint(
                x: center.x + cos(angle) * innerRadius,
                y: center.y + sin(angle) * innerRadius
            )
            let end = NSPoint(
                x: center.x + cos(angle) * endRadius,
                y: center.y + sin(angle) * endRadius
            )

            let tick = NSBezierPath()
            tick.move(to: start)
            tick.line(to: end)
            tick.lineCapStyle = .round
            tick.lineWidth = tickLineWidth
            (isArmed ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
            tick.stroke()
        }
    }

    private func drawProgress(center: NSPoint, radius: CGFloat) {
        guard isArmed || progress > 0 else { return }
        let scale = max(0.45, radius / 73)

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - (360 * progress),
            clockwise: true
        )
        arc.lineCapStyle = .round
        arc.lineWidth = max(2.5, 8 * scale)
        (isArmed ? appAccentColor : NSColor.separatorColor).setStroke()
        arc.stroke()
    }

    private func drawClockMarkers(center: NSPoint, radius: CGFloat) {
        let scale = max(0.45, radius / 80)
        drawMarker(
            minute: currentMinuteOfDay,
            center: center,
            radius: radius,
            color: isArmed ? .white : .secondaryLabelColor,
            lineWidth: max(1.0, 2.6 * scale),
            length: 20 * scale,
            knobSize: max(3, 6 * scale)
        )

        let stopMarkerColor = isArmed ? appAccentColor : NSColor.systemGray.withAlphaComponent(0.72)
        drawMarker(
            minute: stopMinuteOfDay,
            center: center,
            radius: radius,
            color: stopMarkerColor,
            lineWidth: max(1.8, 4.4 * scale),
            length: 26 * scale,
            knobSize: max(5, 10 * scale)
        )
    }

    private func drawMarker(
        minute: Int,
        center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        lineWidth: CGFloat,
        length: CGFloat,
        knobSize: CGFloat
    ) {
        let angle = pointAngle(for: CGFloat(minute) / 1_440.0)
        let markerRadius = max(0, radius - (knobSize / 2))
        let innerRadius = markerRadius - length
        let start = NSPoint(
            x: center.x + cos(angle) * innerRadius,
            y: center.y + sin(angle) * innerRadius
        )
        let end = NSPoint(
            x: center.x + cos(angle) * markerRadius,
            y: center.y + sin(angle) * markerRadius
        )

        let marker = NSBezierPath()
        marker.move(to: start)
        marker.line(to: end)
        marker.lineCapStyle = .round
        marker.lineWidth = lineWidth
        color.setStroke()
        marker.stroke()

        let knobRect = NSRect(
            x: end.x - knobSize / 2,
            y: end.y - knobSize / 2,
            width: knobSize,
            height: knobSize
        )
        color.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    private func drawValue(in rect: NSRect) {
        guard !valueText.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let baseSize = max(10, min(30, bounds.width * 0.18))
        let font = fittingSystemFont(
            for: valueText,
            maxWidth: rect.width - 16,
            baseSize: baseSize,
            weight: .bold,
            minSize: 8
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let attributedValue = NSAttributedString(string: valueText, attributes: attributes)
        let textRect = NSRect(
            x: rect.minX + 8,
            y: rect.midY - attributedValue.size().height / 2,
            width: rect.width - 16,
            height: attributedValue.size().height
        )
        attributedValue.draw(in: textRect)
    }

    private func updateClockMinute(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let angle = atan2(point.y - center.y, point.x - center.x)
        var fraction = ((.pi / 2) - angle) / (2 * .pi)
        while fraction < 0 { fraction += 1 }
        while fraction >= 1 { fraction -= 1 }

        let rawMinute = Int((fraction * 1_440).rounded())
        let snappedMinute = ((rawMinute + 7) / 15 * 15) % 1_440
        clockMinuteChanged?(snappedMinute)
    }

    private func pointAngle(for fraction: CGFloat) -> CGFloat {
        (.pi / 2) - (fraction * 2 * .pi)
    }
}

private final class TimerTextControl: NSControl {
    var minutes: Int {
        get { storedMinutes }
        set {
            storedMinutes = clampedMinutes(newValue)
            if !isEditingMinutes {
                draftMinutesText = String(storedMinutes)
            }
            setAccessibilityValue("\(storedMinutes) minutes")
            needsDisplay = true
        }
    }

    var countdownText: String? {
        didSet { needsDisplay = true }
    }

    var isArmed = false {
        didSet { needsDisplay = true }
    }

    var minutesChanged: ((Int) -> Void)?
    var editingBegan: (() -> Void)?

    private var isEditingMinutes = false
    private var selectsMinuteDigits = false
    private var draftMinutesText = "60"
    private var storedMinutes = 60
    private var hourPrefixText: String?
    private var mouseDownPoint: NSPoint?
    private var scrubStartMinutes = 60
    private var isScrubbingMinutes = false
    private let scrubPixelsPerStep: CGFloat = 8
    private let scrubStepMinutes = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 74, height: 26)
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Stop timer minutes")
        setAccessibilityValue("\(minutes) minutes")
    }

    func beginEditing(selectAll: Bool = true) {
        guard isEnabled else { return }
        isEditingMinutes = true
        selectsMinuteDigits = selectAll
        draftMinutesText = String(minutes)
        hourPrefixText = nil
        window?.makeFirstResponder(self)
        editingBegan?()
        needsDisplay = true
    }

    func commitEditing() {
        guard isEditingMinutes else { return }
        commitDraft()
        isEditingMinutes = false
        selectsMinuteDigits = false
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        commitEditing()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        scrubStartMinutes = minutes
        isScrubbingMinutes = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let mouseDownPoint else { return }

        let point = convert(event.locationInWindow, from: nil)
        let deltaY = point.y - mouseDownPoint.y
        guard isScrubbingMinutes || abs(deltaY) >= scrubPixelsPerStep else { return }

        if !isScrubbingMinutes {
            isScrubbingMinutes = true
            isEditingMinutes = false
            selectsMinuteDigits = false
            hourPrefixText = nil
            editingBegan?()
        }

        let steps = Int((deltaY / scrubPixelsPerStep).rounded(.towardZero))
        let scrubbedMinutes = clampedMinutes(scrubStartMinutes + (steps * scrubStepMinutes))
        guard scrubbedMinutes != minutes else { return }

        minutes = scrubbedMinutes
        draftMinutesText = String(scrubbedMinutes)
        minutesChanged?(scrubbedMinutes)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            isScrubbingMinutes = false
        }

        if !isScrubbingMinutes {
            beginEditing(selectAll: true)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEditingMinutes else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            cancelEditing()
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            commitEditing()
            window?.makeFirstResponder(nil)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            if selectsMinuteDigits {
                draftMinutesText = ""
                hourPrefixText = nil
                selectsMinuteDigits = false
            } else if hourPrefixText != nil, draftMinutesText.isEmpty {
                draftMinutesText = hourPrefixText ?? ""
                hourPrefixText = nil
            } else {
                draftMinutesText = String(draftMinutesText.dropLast())
            }
            publishDraft()
            return
        }

        guard let characters = event.charactersIgnoringModifiers else { return }
        let editableCharacters = characters.filter { $0.isNumber || $0 == ":" }
        if editableCharacters.contains(":") {
            applyHourMinuteShortcutInput(editableCharacters)
            return
        }

        let digits = characters.filter(\.isNumber)
        guard !digits.isEmpty else { return }

        if selectsMinuteDigits {
            draftMinutesText = ""
            hourPrefixText = nil
            selectsMinuteDigits = false
        }

        if draftMinutesText == "0" {
            draftMinutesText = ""
        }

        let maxDigits = hourPrefixText == nil ? 5 : 2
        let room = max(0, maxDigits - draftMinutesText.count)
        draftMinutesText += String(digits.prefix(room))
        publishDraft()
    }

    override func draw(_ dirtyRect: NSRect) {
        if let countdownText {
            drawCentered(countdownText, color: .secondaryLabelColor)
            return
        }

        drawEditableDuration()
    }

    private func drawCentered(_ text: String, color: NSColor) {
        let font = fittingSystemFont(
            for: text,
            maxWidth: bounds.width,
            baseSize: max(10, min(19, bounds.width * 0.205)),
            weight: .bold,
            minSize: 8
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let size = attributedText.size()
        let rect = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        attributedText.draw(in: rect)
    }

    private func drawEditableDuration() {
        let minuteText = editingMinuteText
        let suffixText = ":00"
        let fullText = minuteText + suffixText
        let font = fittingSystemFont(
            for: fullText,
            maxWidth: bounds.width,
            baseSize: max(10, min(19, bounds.width * 0.205)),
            weight: .bold,
            minSize: 8
        )
        let textColor = isArmed || isEditingMinutes ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        let suffixColor = isArmed || isEditingMinutes ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let suffixAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: suffixColor
        ]
        let minuteSize = (minuteText as NSString).size(withAttributes: attributes)
        let suffixSize = (suffixText as NSString).size(withAttributes: suffixAttributes)
        let totalWidth = minuteSize.width + suffixSize.width
        let textHeight = max(minuteSize.height, suffixSize.height)
        let startX = bounds.midX - totalWidth / 2
        let startY = bounds.midY - textHeight / 2

        if isEditingMinutes && selectsMinuteDigits {
            let highlightRect = NSRect(
                x: startX - 2,
                y: startY + 2,
                width: minuteSize.width + 4,
                height: textHeight - 3
            )
            NSColor.systemGray.withAlphaComponent(0.62).setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: 3, yRadius: 3).fill()
        }

        (minuteText as NSString).draw(at: NSPoint(x: startX, y: startY), withAttributes: attributes)
        (suffixText as NSString).draw(at: NSPoint(x: startX + minuteSize.width, y: startY), withAttributes: suffixAttributes)

        if isEditingMinutes && !selectsMinuteDigits {
            let caretX = startX + minuteSize.width + 1
            let caret = NSBezierPath()
            caret.move(to: NSPoint(x: caretX, y: startY + 4))
            caret.line(to: NSPoint(x: caretX, y: startY + textHeight - 4))
            caret.lineWidth = 1
            NSColor.systemGray.setStroke()
            caret.stroke()
        }
    }

    private func publishDraft() {
        let parsed = currentDraftMinutes()
        minutes = parsed
        minutesChanged?(parsed)
    }

    private func commitDraft() {
        let parsed = currentDraftMinutes()
        minutes = parsed
        draftMinutesText = String(parsed)
        hourPrefixText = nil
        minutesChanged?(parsed)
    }

    private func cancelEditing() {
        isEditingMinutes = false
        selectsMinuteDigits = false
        draftMinutesText = String(minutes)
        hourPrefixText = nil
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    private var editingMinuteText: String {
        if hourPrefixText != nil {
            return String(currentDraftMinutes())
        }
        return draftMinutesText.isEmpty ? "0" : draftMinutesText
    }

    private func currentDraftMinutes() -> Int {
        if let hourPrefixText {
            let hours = Int(hourPrefixText) ?? 0
            let minutesPart = Int(draftMinutesText) ?? 0
            return clampedMinutes((hours * 60) + minutesPart)
        }
        return clampedMinutes(Int(draftMinutesText) ?? 1)
    }

    private func applyHourMinuteShortcutInput(_ input: String) {
        if selectsMinuteDigits, let parsed = parsedHourMinuteShortcut(input) {
            selectsMinuteDigits = false
            hourPrefixText = nil
            draftMinutesText = String(parsed)
            publishDraft()
            return
        }

        if selectsMinuteDigits {
            draftMinutesText = ""
            selectsMinuteDigits = false
        }

        if hourPrefixText == nil {
            hourPrefixText = draftMinutesText.isEmpty ? "0" : draftMinutesText
            draftMinutesText = ""
        }

        if let suffix = input.split(separator: ":", maxSplits: 1).last, input.contains(":") {
            let digits = suffix.filter(\.isNumber)
            let room = max(0, 2 - draftMinutesText.count)
            draftMinutesText += String(digits.prefix(room))
        }

        publishDraft()
    }

    private func parsedHourMinuteShortcut(_ input: String) -> Int? {
        let parts = input.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutesPart = Int(parts[1]),
              minutesPart >= 0
        else {
            return nil
        }

        return clampedMinutes((hours * 60) + minutesPart)
    }

    private func clampedMinutes(_ value: Int) -> Int {
        max(1, min(99_999, value))
    }
}

private final class OrangeToggle: NSControl {
    var state: NSControl.StateValue = .off {
        didSet {
            setAccessibilityValue(state == .on ? "on" : "off")
            needsDisplay = true
        }
    }

    override var isEnabled: Bool {
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
        NSSize(width: 38, height: 22)
    }

    override var acceptsFirstResponder: Bool { true }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
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

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 {
            toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 0.5, dy: 1)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)

        let on = state == .on
        let trackColor: NSColor
        if !isEnabled {
            trackColor = .quaternaryLabelColor
        } else if on {
            trackColor = appAccentColor
        } else if isHovering {
            trackColor = NSColor.systemGray.withAlphaComponent(0.85)
        } else {
            trackColor = .systemGray
        }

        trackColor.setFill()
        track.fill()

        let knobSize = trackRect.height - 2
        let knobX = on ? trackRect.maxX - knobSize - 1 : trackRect.minX + 1
        let knobRect = NSRect(
            x: knobX,
            y: trackRect.midY - knobSize / 2,
            width: knobSize,
            height: knobSize
        )
        let knob = NSBezierPath(ovalIn: knobRect)
        NSColor.controlBackgroundColor.setFill()
        knob.fill()
    }

    private func toggle() {
        state = state == .on ? .off : .on
        sendAction(action, to: target)
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
        NSSize(width: 39, height: 39)
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
        let circleRect = bounds.insetBy(dx: 7.5, dy: 7.5)
        let circle = NSBezierPath(ovalIn: circleRect)

        let fillColor: NSColor
        if activeStyle {
            fillColor = highlighted ? appAccentColor.withAlphaComponent(0.82) : appAccentColor
        } else if isHovering || highlighted {
            fillColor = .unemphasizedSelectedContentBackgroundColor
        } else {
            fillColor = .controlBackgroundColor
        }
        fillColor.setFill()
        circle.fill()

        (activeStyle ? appAccentColor : NSColor.separatorColor).setStroke()
        circle.lineWidth = activeStyle ? 1.5 : 1
        circle.stroke()

        let iconInset = max(7, circleRect.width * 0.2)
        let iconColor = activeStyle ? NSColor.white : appAccentColor
        glyph.draw(in: circleRect.insetBy(dx: iconInset, dy: iconInset), color: iconColor, lineWidth: 1.2)
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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

    private let durationDial = DialView()
    private let durationToggle = OrangeToggle()
    private let durationTitleLabel = NSTextField(labelWithString: "Stop timer")
    private let durationEditor = TimerTextControl()
    private let durationInfoLabel = NSTextField(labelWithString: "")

    private let wallClockDial = DialView()
    private let wallClockToggle = OrangeToggle()
    private let wallClockTitleLabel = NSTextField(labelWithString: "Wall clock stop")
    private let wallClockInfoLabel = NSTextField(labelWithString: "")

    private var active = false
    private var autoStopTimer: Timer?
    private var uiRefreshTimer: Timer?
    private var autoStopDeadline: Date?
    private var autoStopReason: String?
    private var lastStatusText = "Ready"
    private var durationMinutesValue = 60
    private var wallClockStopMinuteOfDay = 0

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var dialTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureStatusItem()
        configureWindow()
        startUIRefreshTimer()

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
        uiRefreshTimer?.invalidate()
        stop(statusText: "Ready")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenu()
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
        titleLabel.font = .systemFont(ofSize: 11, weight: .light)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        powerButton.target = self
        powerButton.action = #selector(toggle)
        powerButton.widthAnchor.constraint(equalToConstant: 106).isActive = true
        powerButton.heightAnchor.constraint(equalToConstant: 106).isActive = true

        configureDurationControls()
        configureWallClockControls()

        durationDial.mode = .timer
        durationDial.setAccessibilityLabel("Edit stop timer")
        durationDial.timerNumberClicked = { [weak self] in
            self?.focusDurationEditor()
        }
        durationDial.widthAnchor.constraint(equalToConstant: 106).isActive = true
        durationDial.heightAnchor.constraint(equalToConstant: 106).isActive = true
        durationDial.addSubview(durationEditor)
        NSLayoutConstraint.activate([
            durationEditor.centerXAnchor.constraint(equalTo: durationDial.centerXAnchor),
            durationEditor.centerYAnchor.constraint(equalTo: durationDial.centerYAnchor),
            durationEditor.widthAnchor.constraint(equalToConstant: 93),
            durationEditor.heightAnchor.constraint(equalToConstant: 33)
        ])

        wallClockDial.mode = .clock24
        wallClockDial.setAccessibilityLabel("Adjust wall clock stop time")
        wallClockDial.clockMinuteChanged = { [weak self] minute in
            self?.setWallClockMinuteOfDay(minute, enableStop: true, refresh: true)
        }
        wallClockDial.widthAnchor.constraint(equalToConstant: 106).isActive = true
        wallClockDial.heightAnchor.constraint(equalToConstant: 106).isActive = true
        wallClockDial.showsTicks = true

        let durationColumn = makeDialColumn(
            dial: durationDial,
            titleLabel: durationTitleLabel,
            toggle: durationToggle,
            infoLabel: durationInfoLabel
        )
        let centerColumn = makeCenterColumn()
        let wallClockColumn = makeDialColumn(
            dial: wallClockDial,
            titleLabel: wallClockTitleLabel,
            toggle: wallClockToggle,
            infoLabel: wallClockInfoLabel
        )

        let stack = NSStackView(views: [durationColumn, centerColumn, wallClockColumn])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .equalSpacing
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = BackgroundView()
        contentView.addSubview(stack)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: titleLabel.topAnchor, constant: -6),
            titleLabel.widthAnchor.constraint(equalToConstant: 138),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 213),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NoDoze"
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshUI()
    }

    private func configureDurationControls() {
        styleToggle(durationToggle, label: durationTitleLabel)
        durationToggle.target = self
        durationToggle.action = #selector(durationToggleChanged)

        durationEditor.minutes = durationMinutesValue
        durationEditor.minutesChanged = { [weak self] minutes in
            guard let self else { return }
            self.durationMinutesValue = minutes
            self.refreshUI()
        }
        durationEditor.editingBegan = { [weak self] in
            guard let self, !self.active else { return }
            self.selectDurationStop()
            self.refreshUI()
        }
    }

    private func configureWallClockControls() {
        styleToggle(wallClockToggle, label: wallClockTitleLabel)
        wallClockToggle.target = self
        wallClockToggle.action = #selector(wallClockToggleChanged)

        wallClockStopMinuteOfDay = roundedQuarterMinute(minuteOfDay(from: Date().addingTimeInterval(60 * 60)))
    }

    private func styleToggle(_ toggle: OrangeToggle, label: NSTextField) {
        toggle.widthAnchor.constraint(equalToConstant: 38).isActive = true
        toggle.heightAnchor.constraint(equalToConstant: 22).isActive = true

        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
    }

    private func makeCenterColumn() -> NSView {
        let stack = NSStackView(views: [powerButton, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: 106),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor),
            statusLabel.widthAnchor.constraint(equalTo: wrapper.widthAnchor)
        ])

        return wrapper
    }

    private func makeDialColumn(
        dial: DialView,
        titleLabel: NSTextField,
        toggle: OrangeToggle,
        infoLabel: NSTextField
    ) -> NSView {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        infoLabel.font = .systemFont(ofSize: 8, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.alignment = .center
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let stack = NSStackView(views: [dial, titleLabel, toggle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: 131),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor),
            titleLabel.widthAnchor.constraint(equalTo: wrapper.widthAnchor)
        ])

        return wrapper
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

    @objc private func durationToggleChanged() {
        if durationToggle.state == .on {
            wallClockToggle.state = .off
        }
        refreshUI()
    }

    @objc private func wallClockToggleChanged() {
        if wallClockToggle.state == .on {
            durationToggle.state = .off
        }
        refreshUI()
    }

    private func focusDurationEditor() {
        guard !active else { return }

        selectDurationStop()
        refreshUI()
        durationEditor.beginEditing(selectAll: true)
    }

    private func start() {
        do {
            durationEditor.commitEditing()
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
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        if let autoStopDeadline {
            let interval = max(0.5, autoStopDeadline.timeIntervalSinceNow)
            autoStopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.stopAutomatically()
            }
        }
    }

    private func cancelAutoStopTimers() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        autoStopDeadline = nil
        autoStopReason = nil
    }

    private func startUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshTimeSensitiveUI()
        }
    }

    private func refreshTimeSensitiveUI() {
        refreshDialViews()
        refreshTimerInfoLabels()
        refreshStatusMenu()
    }

    private func nextConfiguredStopDeadline() -> StopDeadline? {
        let now = Date()
        var deadlines: [StopDeadline] = []

        if durationToggle.state == .on {
            let durationDate = now.addingTimeInterval(TimeInterval(durationMinutes() * 60))
            deadlines.append(StopDeadline(date: durationDate, reason: "stop timer"))
        }

        if wallClockToggle.state == .on {
            deadlines.append(StopDeadline(date: wallClockStopDate(after: now), reason: "wall clock"))
        }

        return deadlines.min { $0.date < $1.date }
    }

    private func wallClockStopDate(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        var targetParts = calendar.dateComponents([.year, .month, .day], from: now)
        targetParts.hour = wallClockStopMinuteOfDay / 60
        targetParts.minute = wallClockStopMinuteOfDay % 60
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
        durationMinutesValue
    }

    private func selectDurationStop() {
        durationToggle.state = .on
        wallClockToggle.state = .off
    }

    private func selectWallClockStop() {
        wallClockToggle.state = .on
        durationToggle.state = .off
    }

    private func setWallClockMinuteOfDay(_ minute: Int, enableStop: Bool, refresh: Bool) {
        if enableStop && !active {
            selectWallClockStop()
        }

        wallClockStopMinuteOfDay = roundedQuarterMinute(minute)

        if refresh {
            refreshUI()
        }
    }

    private func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private func roundedQuarterMinute(_ minute: Int) -> Int {
        let normalized = ((minute % 1_440) + 1_440) % 1_440
        return ((normalized + 7) / 15 * 15) % 1_440
    }

    private func dateForMinuteOfDay(_ minute: Int, relativeTo date: Date = Date()) -> Date {
        let normalized = ((minute % 1_440) + 1_440) % 1_440
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = normalized / 60
        components.minute = normalized % 60
        components.second = 0

        return Calendar.current.date(from: components) ?? date
    }

    private func clockText(for minute: Int) -> String {
        dialTimeFormatter.string(from: dateForMinuteOfDay(minute))
    }

    private func clampedDurationMinutes(_ minutes: Int) -> Int {
        max(1, min(99_999, minutes))
    }

    private func refreshUI() {
        powerButton.glyph = active ? .stop : .play
        powerButton.activeStyle = active
        powerButton.setAccessibilityLabel(active ? "Stop NoDoze" : "Start NoDoze")

        statusLabel.stringValue = active ? "Running" : lastStatusText
        statusLabel.textColor = active ? appAccentColor : .secondaryLabelColor

        refreshDialViews()
        refreshTimerInfoLabels()
        refreshControlStates()
        refreshStatusMenu()
    }

    private func refreshDialViews() {
        let durationArmed = durationToggle.state == .on
        durationTitleLabel.stringValue = "\(durationMinutes()) min timer"
        durationTitleLabel.textColor = durationArmed ? .secondaryLabelColor : .tertiaryLabelColor
        durationDial.isArmed = durationArmed
        durationDial.valueText = ""
        durationEditor.minutes = durationMinutes()
        durationEditor.isArmed = durationArmed || active

        if active, autoStopReason == "stop timer", let autoStopDeadline {
            durationEditor.countdownText = compactRemainingText(until: autoStopDeadline)
            durationDial.progress = durationProgress(until: autoStopDeadline)
        } else {
            durationEditor.countdownText = nil
            durationDial.progress = durationArmed ? 1 : 0
        }

        let wallClockArmed = wallClockToggle.state == .on
        let exactClockMinute = minuteOfDay(from: Date())
        let currentClockMinute = roundedQuarterMinute(exactClockMinute)
        let stopClockMinute = wallClockStopMinuteOfDay
        wallClockTitleLabel.stringValue = "Off at \(clockText(for: stopClockMinute))"
        wallClockTitleLabel.textColor = wallClockArmed ? .secondaryLabelColor : .tertiaryLabelColor
        wallClockDial.currentMinuteOfDay = currentClockMinute
        wallClockDial.stopMinuteOfDay = stopClockMinute
        wallClockDial.isArmed = wallClockArmed
        wallClockDial.valueText = clockText(for: exactClockMinute)
        wallClockDial.progress = wallClockArmed ? 1 : 0
    }

    private func refreshTimerInfoLabels() {
        durationInfoLabel.stringValue = ""
        wallClockInfoLabel.stringValue = ""
        durationInfoLabel.textColor = .secondaryLabelColor
        wallClockInfoLabel.textColor = .secondaryLabelColor

        guard active, let autoStopDeadline, let autoStopReason else { return }

        if autoStopReason == "stop timer" {
            durationInfoLabel.stringValue = ""
        } else if autoStopReason == "wall clock" {
            wallClockInfoLabel.stringValue = "ETA \(timeFormatter.string(from: autoStopDeadline))"
            wallClockInfoLabel.textColor = appAccentColor
        }
    }

    private func refreshControlStates() {
        durationDial.isEnabled = !active
        wallClockDial.isEnabled = !active
        durationToggle.isEnabled = !active
        wallClockToggle.isEnabled = !active
        durationEditor.isEnabled = !active
    }

    private func refreshStatusMenu() {
        statusItem?.button?.image = statusImage(active: active)
        statusItem?.button?.toolTip = active ? "NoDoze running" : "NoDoze ready"

        statusSummaryMenuItem.title = active ? "NoDoze: Running" : "NoDoze: \(lastStatusText)"
        statusTimerMenuItem.title = menuTimerText()
        statusToggleMenuItem.title = active ? "Stop" : "Start"
        statusWindowMenuItem.title = window?.isVisible == true ? "Hide Window" : "Show Window"
    }

    private func menuTimerText() -> String {
        if active, let autoStopDeadline {
            return "Auto-stop: \(remainingText(until: autoStopDeadline))"
        }

        if durationToggle.state == .off && wallClockToggle.state == .off {
            return "Auto-stop: Disabled"
        }

        return "Auto-stop: Armed for next start"
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

    private func compactRemainingText(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func durationProgress(until date: Date) -> CGFloat {
        let totalSeconds = max(1, durationMinutes() * 60)
        let remainingSeconds = max(0, date.timeIntervalSinceNow)
        return CGFloat(min(1, remainingSeconds / TimeInterval(totalSeconds)))
    }

    private func statusImage(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let circle = NSBezierPath(ovalIn: circleRect)
            (active ? appAccentColor : NSColor.clear).setFill()
            circle.fill()

            (active ? appAccentColor : NSColor.secondaryLabelColor).setStroke()
            circle.lineWidth = 1.4
            circle.stroke()

            let glyphRect = circleRect.insetBy(dx: 4.8, dy: 4.8)
            (active ? IconGlyph.stop : IconGlyph.play).draw(
                in: glyphRect,
                color: active ? .white : .secondaryLabelColor,
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
