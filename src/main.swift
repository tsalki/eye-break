// eye-break: a 20-20-20 reminder that lives in the menu bar. See SPEC.md.
//
//   eye-break          run (what the LaunchAgent starts at login)
//   eye-break stats    today's breaks and the current streak

import AppKit

/// A second copy (say, a manual test run while the agent is running) would add
/// a second icon. The lock is released automatically when the process exits.
func acquireSingleInstanceLock() -> Bool {
    try? FileManager.default.createDirectory(atPath: Settings.stateDirectory, withIntermediateDirectories: true)
    let fd = open(Settings.stateDirectory + "/lock", O_CREAT | O_RDWR, 0o644)
    return fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0
}

switch CommandLine.arguments.dropFirst().first {
case nil, "run":
    guard acquireSingleInstanceLock() else {
        print("Eye Break is already running.")
        exit(0)
    }
    let app = NSApplication.shared
    let menuBar = MenuBar()
    app.delegate = menuBar
    app.setActivationPolicy(.accessory)
    // The app only holds its delegate weakly; keep it alive for the whole run.
    withExtendedLifetime(menuBar) { app.run() }
case "stats":
    Log.printStats()
default:
    FileHandle.standardError.write(Data("usage: eye-break [run | stats]\n".utf8))
    exit(64)
}
