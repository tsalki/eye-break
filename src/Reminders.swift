import AppKit

/// Shows a reminder on screen for the Scheduler.
func presentReminder(_ kind: ReminderKind, done: @escaping (Outcome) -> Void) -> Reminder {
    switch kind {
    case .nudge: Nudge(done: done)
    case .warning(let allowSnooze): Warning(allowSnooze: allowSnooze, done: done)
    case .overlay: Overlay(done: done)
    }
}

// MARK: - Building blocks

/// A timer that keeps firing while a menu or button is being clicked.
func repeatingTimer(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
    RunLoop.main.add(timer, forMode: .common)
    return timer
}

func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .monospacedDigitSystemFont(ofSize: size, weight: .light)
    field.textColor = color
    field.alignment = .center
    return field
}

/// Small panel in the top-right corner, sized to fit its contents.
/// Non-activating, so it never steals focus from what you're typing.
func cornerPanel(views: [NSView]) -> NSPanel {
    let row = NSStackView(views: views)
    row.spacing = 12
    let fitting = row.fittingSize
    let size = NSSize(width: fitting.width + 40, height: max(56, fitting.height + 24))

    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    let background = NSVisualEffectView()
    background.material = .hudWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 12

    row.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(row)
    NSLayoutConstraint.activate([
        row.centerXAnchor.constraint(equalTo: background.centerXAnchor),
        row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
    ])

    panel.contentView = background
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    if let screen = NSScreen.main?.visibleFrame {
        panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 16))
    }
    return panel
}

func fade(_ window: NSWindow, to alpha: CGFloat, then done: (() -> Void)? = nil) {
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.4
        window.animator().alphaValue = alpha
    }, completionHandler: done)
}

// MARK: - Gentle mode

/// A reminder that waits for you. The countdown only runs while you're
/// hands-off, and restarts if you touch anything.
final class Nudge: NSObject, Reminder {
    private let done: (Outcome) -> Void
    private let text = label("", size: 15, color: .labelColor)
    private var panel: NSPanel!
    private var timer: Timer?
    private let shown = Date()

    init(done: @escaping (Outcome) -> Void) {
        self.done = done
        super.init()
        update(handsOff: 0)  // longest text, so the panel is sized for it
        panel = cornerPanel(views: [
            text,
            NSButton(title: "Later", target: self, action: #selector(later)),
            NSButton(title: "Skip", target: self, action: #selector(skip)),
        ])
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fade(panel, to: 1)
        timer = repeatingTimer(0.2) { [weak self] in self?.tick() }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(shown)
        // Only time since the reminder appeared counts.
        let handsOff = min(Checks.idleSeconds(), elapsed)

        if handsOff >= Settings.breakLength {
            NSSound(named: "Glass")?.play()
            close(.taken(seconds: Int(elapsed.rounded())))
        } else if elapsed >= Settings.nudgeTimeout {
            close(.ignored)
        } else {
            update(handsOff: handsOff)
        }
    }

    private func update(handsOff: TimeInterval) {
        let seconds = Settings.breakLength
        text.stringValue = handsOff < 1
            ? "Look away for \(Int(seconds))s, whenever you're ready"
            : "Looking away… \(Int((seconds - handsOff).rounded(.up)))"
    }

    private func close(_ outcome: Outcome) {
        guard stop() else { return }
        fade(panel, to: 0) { [self] in
            panel.orderOut(nil)
            done(outcome)
        }
    }

    func cancel() {
        if stop() { panel.orderOut(nil) }
    }

    /// Stops the countdown first, so a tick during the fade can't close it
    /// again with a different result. False if it was already stopped.
    private func stop() -> Bool {
        guard let timer else { return false }
        timer.invalidate()
        self.timer = nil
        return true
    }

    @objc private func later() { close(.later) }
    @objc private func skip() { close(.skipped) }
}

// MARK: - Strict mode

/// Countdown to the black overlay.
final class Warning: NSObject, Reminder {
    private let done: (Outcome) -> Void
    private let text = label("", size: 15, color: .labelColor)
    private var panel: NSPanel!
    private var timer: Timer?
    private var remaining = Settings.warning

    init(allowSnooze: Bool, done: @escaping (Outcome) -> Void) {
        self.done = done
        super.init()
        update()
        var views: [NSView] = [text]
        if allowSnooze {
            views.append(NSButton(title: "Snooze 2 min", target: self, action: #selector(snooze)))
        }
        panel = cornerPanel(views: views)
        panel.orderFrontRegardless()
        timer = repeatingTimer(1) { [weak self] in self?.tick() }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { close(.go) } else { update() }
    }

    private func update() { text.stringValue = "Eye break in \(remaining)s" }

    private func close(_ outcome: Outcome) {
        cancel()
        done(outcome)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    @objc private func snooze() { close(.snoozed) }
}

/// Borderless windows can't become key by default; this one must, so typing
/// during a break lands here instead of in the app underneath.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {}
}

/// Black window over every screen. The countdown restarts whenever there's
/// input, so the break only counts if you actually look away.
final class Overlay: Reminder {
    private let done: (Outcome) -> Void
    private var windows: [NSWindow] = []
    private var countdowns: [NSTextField] = []
    private var timer: Timer?
    private let shown = Date()
    private var start = Date()
    private var lastTink = Date.distantPast

    init(done: @escaping (Outcome) -> Void) {
        self.done = done

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.alphaValue = 0

            let countdown = label("\(Int(Settings.breakLength))", size: 120, color: .white)
            let hint = label("Look at something about 6 m away", size: 24, color: .gray)
            let stack = NSStackView(views: [countdown, hint])
            stack.orientation = .vertical
            stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
            window.contentView = content
            window.setFrame(screen.frame, display: true)

            windows.append(window)
            countdowns.append(countdown)
        }

        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()
        NSApp.activate()
        NSCursor.hide()
        windows.forEach { fade($0, to: 1) }
        timer = repeatingTimer(0.2) { [weak self] in self?.tick() }
    }

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(shown)

        if elapsed >= Settings.giveUp {
            close(.abandoned(seconds: Int(elapsed.rounded())))
            return
        }
        // Short grace period: you may still be moving the mouse as it appears.
        if elapsed > 1.5 && Checks.idleSeconds() < 0.3 {
            start = now
            if now.timeIntervalSince(lastTink) > 1 {
                NSSound(named: "Tink")?.play()
                lastTink = now
            }
        }

        let remaining = Settings.breakLength - now.timeIntervalSince(start)
        if remaining <= 0 {
            NSSound(named: "Glass")?.play()
            close(.taken(seconds: Int(elapsed.rounded())))
            return
        }
        countdowns.forEach { $0.stringValue = "\(Int(remaining.rounded(.up)))" }
    }

    private func close(_ outcome: Outcome) {
        cancel()
        done(outcome)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }
        NSCursor.unhide()
        // Hand focus back to the app you were using.
        NSApp.hide(nil)
    }
}
