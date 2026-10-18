import AppKit

/// The menu bar icon and its menu. Owns the scheduler and feeds it the clock
/// and system events (sleep, wake, lock).
final class MenuBar: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var scheduler: Scheduler!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduler = Scheduler(present: presentReminder)
        scheduler.onChange = { [weak self] in self?.refresh() }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduler.willSleep()
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduler.didWake()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduler.screenLocked()
        }

        timer = repeatingTimer(Settings.tick) { [weak self] in self?.scheduler.tick() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.write("quit")
    }

    // MARK: - Icon

    private var minutesLeft: Int {
        max(1, Int((scheduler.nextBreak.timeIntervalSinceNow / 60).rounded(.up)))
    }

    private func refresh() {
        guard let button = item?.button else { return }
        let symbol: String
        var title = ""
        if scheduler.pausedUntil != nil {
            symbol = "eye.slash"
        } else if scheduler.holdingForCamera {
            symbol = "video"
        } else if scheduler.showing {
            symbol = "eye.fill"
        } else {
            symbol = "eye"
            title = " \(minutesLeft)m"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Eye Break")
        button.title = title
    }

    // MARK: - Menu

    private var statusLine: String {
        if let until = scheduler.pausedUntil {
            return Calendar.current.isDateInToday(until)
                ? "Paused until \(until.formatted(date: .omitted, time: .shortened))"
                : "Paused until tomorrow"
        }
        if scheduler.showing { return "Break in progress" }
        if scheduler.holdingForCamera { return "Break due, waiting for the camera to turn off" }
        return minutesLeft == 1 ? "Next break in under a minute" : "Next break in \(minutesLeft) min"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(info(statusLine))
        menu.addItem(action("Take a Break Now", #selector(takeBreakNow), enabled: !scheduler.showing))
        if scheduler.pausedUntil != nil {
            menu.addItem(action("Resume", #selector(resume)))
        } else {
            menu.addItem(action("Pause for 1 Hour", #selector(pauseHour)))
            menu.addItem(action("Pause Until Tomorrow", #selector(pauseTomorrow)))
        }

        menu.addItem(.separator())
        if let stats = Log.stats() {
            menu.addItem(info("Today: \(stats.takenToday) taken · \(stats.missesToday) missed"))
            menu.addItem(info("Streak: \(stats.streak) day\(stats.streak == 1 ? "" : "s")"))
        }
        menu.addItem(action("Open Log", #selector(openLog)))

        menu.addItem(.separator())
        menu.addItem(action("Quit Eye Break", #selector(quit)))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func takeBreakNow() { scheduler.takeBreakNow() }
    @objc private func resume() { scheduler.resume() }
    @objc private func pauseHour() { scheduler.pause(until: Date() + 60 * 60, label: "1h") }

    @objc private func pauseTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        scheduler.pause(until: tomorrow, label: "tomorrow")
    }

    @objc private func openLog() { NSWorkspace.shared.open(Settings.logURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
