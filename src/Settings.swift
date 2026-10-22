import Foundation

/// All tuning in one place. Edit, then re-run ./install.sh. The interval and
/// break length can also be changed from the menu; those choices are saved.
/// EYE_BREAK_MODE, EYE_BREAK_INTERVAL, EYE_BREAK_SECONDS and EYE_BREAK_LOG
/// override their settings, for testing with short timings.
enum Settings {
    enum Mode: String { case gentle, strict }

    private static let env = ProcessInfo.processInfo.environment
    /// ~/Library/Preferences/com.tsalki.eye-break.plist
    private static let saved = UserDefaults(suiteName: "com.tsalki.eye-break")!

    private static func choice(_ key: String, env name: String, default value: TimeInterval) -> TimeInterval {
        env[name].flatMap { TimeInterval($0) }
            ?? (saved.object(forKey: key) as? NSNumber)?.doubleValue
            ?? value
    }

    /// gentle: small reminder at the top · strict: black screen
    static let mode = Mode(rawValue: env["EYE_BREAK_MODE"] ?? "") ?? .gentle
    /// Screen time between breaks.
    static var interval = choice("interval", env: "EYE_BREAK_INTERVAL", default: 20 * 60) {
        didSet { saved.set(interval, forKey: "interval") }
    }
    /// Length of a break.
    static var breakLength = choice("breakLength", env: "EYE_BREAK_SECONDS", default: 20) {
        didSet { saved.set(breakLength, forKey: "breakLength") }
    }
    /// What the menu offers for each.
    static let intervalChoices: [TimeInterval] = [20, 29, 42, 60].map { $0 * 60 }
    static let breakLengthChoices: [TimeInterval] = [10, 20, 30, 60]
    /// Idle this long means you left; the timer resets.
    static let away: TimeInterval = 5 * 60
    /// How often idle, lock and camera state are checked.
    static let tick: TimeInterval = 5

    // Gentle mode
    /// Ignoring a reminder once brings it back after this.
    static let later: TimeInterval = 5 * 60
    /// An ignored reminder fades after this.
    static let nudgeTimeout: TimeInterval = 2 * 60

    // Strict mode
    /// Warning before the screen goes dark.
    static let warning = 10
    /// How far a snooze pushes the break.
    static let snooze: TimeInterval = 2 * 60
    /// One snooze per this long.
    static let snoozeWindow: TimeInterval = 60 * 60
    /// Stop enforcing a break after this long.
    static let giveUp: TimeInterval = 2 * 60

    static let logURL = URL(fileURLWithPath: env["EYE_BREAK_LOG"]
        ?? NSHomeDirectory() + "/Library/Logs/eye-break.log")
    static let stateDirectory = NSHomeDirectory() + "/Library/Application Support/eye-break"
}
