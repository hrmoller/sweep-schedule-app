import Foundation

// MARK: - Configuration

/// One folder that is watched. Items directly inside it that are older than
/// `maxAgeDays` are moved to the Trash, after `warnDays` of advance notice.
struct WatchedFolder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var path: String            // may start with "~"
    var maxAgeDays: Int = 30
    var warnDays: Int = 5
    var enabled: Bool = true

    var url: URL {
        URL(fileURLWithPath: WatchedFolder.expandTilde(path), isDirectory: true)
    }

    /// Home directory used for `~` in paths. Overridable for development (README screenshots run
    /// against a throwaway home): `SWEEP_SCHEDULE_HOME=/path/to/fake-home`.
    static var homeDirectory: String {
        if let h = ProcessInfo.processInfo.environment["SWEEP_SCHEDULE_HOME"], !h.isEmpty { return h }
        return NSHomeDirectory()
    }

    static func expandTilde(_ p: String) -> String {
        if p == "~" { return homeDirectory }
        if p.hasPrefix("~/") { return homeDirectory + p.dropFirst(1) }
        return p
    }

    static func abbreviateTilde(_ p: String) -> String {
        let home = homeDirectory
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + p.dropFirst(home.count) }
        return p
    }

    var displayName: String { url.lastPathComponent }
}

struct Config: Codable, Equatable {
    var folders: [WatchedFolder]
    /// Hour of day (0-23) after which the daily check may run.
    var checkHour: Int

    static var `default`: Config {
        Config(folders: [WatchedFolder(path: "~/Downloads")], checkHour: 9)
    }
}

// MARK: - Persistent state

/// Bookkeeping for a single item, keyed by its absolute path in `SweepState.records`.
struct ItemRecord: Codable, Equatable {
    /// When the user was first notified about this item.
    var firstWarned: Date?
    /// When the most recent notification that included this item was sent.
    var lastNotified: Date?
    /// Set when the user pressed "Keep": the age clock restarts from this date.
    var keptAt: Date?
}

struct SweepState: Codable, Equatable {
    var records: [String: ItemRecord] = [:]
    var lastRun: Date?
    var loginConfigured: Bool = false
}

// MARK: - Scan / plan results

struct ScannedItem: Equatable {
    let url: URL
    let isDirectory: Bool
    /// The date the age is measured from (see `FolderScanner`).
    let date: Date
}

enum Verdict: Equatable {
    /// Not old enough to worry about yet.
    case fresh
    /// Inside the warning window: the user gets notified, nothing is deleted.
    case warn
    /// Past its deadline *and* the user has had the full notice period.
    case trash
}

struct Evaluation: Identifiable, Equatable {
    let folderID: UUID
    let folderName: String
    let item: ScannedItem
    /// Earliest moment the item may be moved to the Trash.
    let deadline: Date
    let verdict: Verdict
    /// Disk space the item takes up, in bytes (folders: everything inside, hidden files included).
    /// Only measured for items that are not `.fresh`; 0 means "not measured".
    var size: Int64 = 0

    var id: String { item.url.path }
    var name: String { item.url.lastPathComponent }

    /// Whole days until the deadline, rounded up ("in 5 days"). Never negative.
    func daysLeft(now: Date) -> Int {
        let d = deadline.timeIntervalSince(now) / 86_400
        return max(0, Int((d - 0.001).rounded(.up)))
    }
}
