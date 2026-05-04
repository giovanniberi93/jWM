import Foundation

/// Per-hour usage counters persisted to disk. Storage lives at
/// `~/Library/Application Support/jwm/usage-stats.json` so it survives app
/// reinstalls and is shared between debug and release builds.
///
/// Hour buckets use the user's local time zone (wall-clock hours are what the
/// user cares about). Buckets older than `retentionDays` are dropped on each
/// write.
enum UsageStats {
    enum EventKind: String, Codable {
        case focus
        case tile
        case focusTile
        case mouseSnap
    }

    private static let retentionDays = 30
    private static let queue = DispatchQueue(label: "com.giovanniberi93.jwm.usage-stats")

    private static let bucketFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH"
        return f
    }()

    static func record(_ kind: EventKind, at date: Date = Date()) {
        queue.async {
            let key = bucketFormatter.string(from: date)
            var store = load()
            var bucket = store.hourly[key] ?? [:]
            bucket[kind.rawValue, default: 0] += 1
            store.hourly[key] = bucket
            prune(&store, now: date)
            save(store)
        }
    }

    // MARK: - Storage

    private struct Store: Codable {
        var hourly: [String: [String: Int]]
    }

    private static var fileURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("jwm", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("usage-stats.json")
    }

    private static func load() -> Store {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store(hourly: [:])
        }
        return store
    }

    private static func save(_ store: Store) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func prune(_ store: inout Store, now: Date) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        let cutoffKey = bucketFormatter.string(from: cutoff)
        store.hourly = store.hourly.filter { $0.key >= cutoffKey }
    }
}
