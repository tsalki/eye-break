import Foundation

/// Tab-separated event log, one line per event: timestamp, event, detail.
/// See SPEC.md for the events.
enum Log {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
    private static let timestamp = formatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let day = formatter("yyyy-MM-dd")

    static func write(_ event: String, _ detail: String = "-") {
        let line = Data("\(timestamp.string(from: Date()))\t\(event)\t\(detail)\n".utf8)
        let url = Settings.logURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: url)
        }
    }

    struct Stats {
        var date = ""
        /// Today's events by name, as `eye-break stats` lists them.
        var today: [String: Int] = [:]
        var takenToday = 0
        var missesToday = 0
        /// Consecutive good days; see stats().
        var streak = 0
    }

    /// Nil if nothing has been logged yet.
    static func stats() -> Stats? {
        guard let text = try? String(contentsOf: Settings.logURL, encoding: .utf8) else { return nil }
        var stats = Stats(date: day.string(from: Date()))
        var taken: [String: Int] = [:]
        var misses: [String: Int] = [:]

        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            let (date, event, detail) = (String(fields[0].prefix(10)), fields[1], fields[2])

            // A reminder still retrying isn't a miss yet.
            if date == stats.date && event != "start" && !(event == "missed" && detail == "retrying") {
                stats.today[event, default: 0] += 1
            }
            // Camera holds don't count against you.
            switch (event, detail) {
            case ("taken", _): taken[date, default: 0] += 1
            case ("missed", "-"), ("abandoned", _), ("skipped", "user"): misses[date, default: 0] += 1
            default: break
            }
        }
        stats.takenToday = taken[stats.date] ?? 0
        stats.missesToday = misses[stats.date] ?? 0

        // A good day: at least one break taken, and at least as many taken as missed.
        func good(_ date: String) -> Bool {
            let count = taken[date] ?? 0
            return count > 0 && count >= misses[date] ?? 0
        }
        // Today doesn't break the streak until it's a bad day.
        var offset = taken[stats.date] == nil && misses[stats.date] == nil ? 1 : 0
        while good(day.string(from: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!)) {
            stats.streak += 1
            offset += 1
        }
        return stats
    }

    static func printStats() {
        guard let stats = stats() else {
            print("No breaks logged yet.")
            return
        }
        print("Today (\(stats.date)):")
        for (event, count) in stats.today.sorted(by: { $0.key < $1.key }) {
            print("  \(event.padding(toLength: 10, withPad: " ", startingAt: 0)) \(count)")
        }
        print("Streak: \(stats.streak) day(s) with at least as many breaks taken as missed")
    }
}
