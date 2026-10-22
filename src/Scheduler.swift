import Foundation

/// What a reminder reports when it closes.
enum Outcome {
    case taken(seconds: Int)        // nudge or overlay completed
    case skipped, ignored           // nudge
    case go, snoozed                // strict-mode warning
    case abandoned(seconds: Int)    // overlay gave up
}

enum ReminderKind {
    case nudge
    case warning(allowSnooze: Bool)
    case overlay
}

/// Something on screen that the scheduler can take down early (sleep, lock, pause).
protocol Reminder: AnyObject {
    func cancel()
}

/// The 20-20-20 timer and all its rules. Knows nothing about windows: it asks
/// `present` to show a reminder and hears back an Outcome.
final class Scheduler {
    struct Probe {
        var idle = Checks.idleSeconds
        var locked = Checks.screenLocked
        var camera = Checks.cameraInUse
        var displayHeld = Checks.displayHeldAwake
    }
    typealias Present = (ReminderKind, @escaping (Outcome) -> Void) -> Reminder

    /// Called whenever something the menu bar shows may have changed.
    var onChange: () -> Void = {}

    private(set) var nextBreak: Date
    private(set) var pausedUntil: Date?
    /// A break is due but the camera is on.
    private(set) var holdingForCamera = false
    var showing: Bool { current != nil }

    private let probe: Probe
    private let present: Present
    private let now: () -> Date
    private var current: Reminder?
    private var away = false
    private var retried = false
    private var lastSnooze: Date?

    init(probe: Probe = Probe(), now: @escaping () -> Date = Date.init, present: @escaping Present) {
        self.probe = probe
        self.present = present
        self.now = now
        nextBreak = now() + Settings.interval
        Log.write("start", Settings.mode.rawValue)
    }

    /// Runs every Settings.tick seconds.
    func tick() {
        guard current == nil else { return }
        defer { onChange() }
        let now = now()

        if let until = pausedUntil {
            guard now >= until else { return }
            resume()
        }

        // Locked screen counts as a break, even with the camera on.
        if probe.locked() { return markAway("away") }

        let idle = probe.idle()
        let due = now >= nextBreak

        // On a video call you're not away, and a due break waits until it ends.
        // Only checked when it matters, since it's the expensive probe.
        if (due || idle >= Settings.away) && probe.camera() {
            if due && !holdingForCamera { Log.write("skipped", "camera") }
            holdingForCamera = due
            return
        }
        holdingForCamera = false

        // Idle 5+ min counts as away, unless something keeps the display awake
        // (a playing video does). Short idle doesn't: reading isn't looking away.
        if idle >= Settings.away && !probe.displayHeld() { return markAway("away") }
        away = false

        if due { show(manual: false) }
    }

    func takeBreakNow() {
        guard current == nil else { return }
        show(manual: true)
        onChange()
    }

    func pause(until date: Date, label: String) {
        dismiss()
        pausedUntil = date
        holdingForCamera = false
        Log.write("paused", label)
        onChange()
    }

    func resume() {
        pausedUntil = nil
        nextBreak = now() + Settings.interval
        Log.write("resumed")
        onChange()
    }

    /// The Mac is about to sleep. Take down any reminder; didWake logs the break.
    func willSleep() {
        dismiss()
    }

    /// A tick can run just before this notification arrives and put up a
    /// reminder for the time spent asleep, so take that down too.
    func didWake() {
        dismiss()
        if pausedUntil == nil { markAway("sleep") }
        onChange()
    }

    func screenLocked() {
        dismiss()
        if pausedUntil == nil { markAway("locked") }
        onChange()
    }

    // MARK: - Private

    /// Being away counts as a break: log it once per absence and restart the timer.
    private func markAway(_ reason: String) {
        if !away { Log.write("natural", reason) }
        away = true
        retried = false
        holdingForCamera = false
        nextBreak = now() + Settings.interval
    }

    private func dismiss() {
        current?.cancel()
        current = nil
    }

    private func schedule(in seconds: TimeInterval) {
        current = nil
        nextBreak = now() + seconds
        onChange()
    }

    private func show(manual: Bool) {
        switch Settings.mode {
        case .gentle:
            current = present(.nudge) { [weak self] in self?.nudgeClosed($0) }
        case .strict where manual:
            showOverlay()
        case .strict:
            let allowSnooze = lastSnooze.map { now().timeIntervalSince($0) >= Settings.snoozeWindow } ?? true
            current = present(.warning(allowSnooze: allowSnooze)) { [weak self] outcome in
                guard let self else { return }
                if case .snoozed = outcome {
                    Log.write("snoozed")
                    lastSnooze = now()
                    schedule(in: Settings.snooze)
                } else {
                    showOverlay()
                }
            }
        }
    }

    private func nudgeClosed(_ outcome: Outcome) {
        switch outcome {
        case .taken(let seconds):
            Log.write("taken", "\(seconds)s")
            retried = false
            schedule(in: Settings.interval)
        case .skipped:
            Log.write("skipped", "user")
            retried = false
            schedule(in: Settings.interval)
        case .ignored where retried:
            // Ignored twice: wait for the next cycle.
            Log.write("missed")
            retried = false
            schedule(in: Settings.interval)
        case .ignored:
            // Ignored once: come back a bit later.
            Log.write("missed", "retrying")
            retried = true
            schedule(in: Settings.later)
        default:
            schedule(in: Settings.interval)
        }
    }

    private func showOverlay() {
        current = present(.overlay) { [weak self] outcome in
            switch outcome {
            case .taken(let seconds): Log.write("taken", "\(seconds)s")
            case .abandoned(let seconds): Log.write("abandoned", "\(seconds)s")
            default: break
            }
            self?.schedule(in: Settings.interval)
        }
    }
}
