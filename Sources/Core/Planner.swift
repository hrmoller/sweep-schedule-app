import Foundation

private let secondsPerDay: TimeInterval = 86_400

enum Planner {
    /// Decides what should happen to one item.
    ///
    /// Rules:
    ///  1. `expiry` = (newest date of the item, or the moment the user pressed "Keep") + maxAgeDays.
    ///  2. The user always gets the *full* warning period. The deadline is the later of
    ///     `expiry` and `firstWarned + warnDays`. An item that has never been warned about
    ///     (the app was off, or it is the very first run) is treated as if it were
    ///     warned right now.
    ///  3. Inside the warning window -> `.warn`. At or after the deadline -> `.trash`.
    static func evaluate(item: ScannedItem,
                         folder: WatchedFolder,
                         record: ItemRecord?,
                         now: Date) -> Evaluation {
        var effective = item.date
        if let kept = record?.keptAt { effective = max(effective, kept) }

        let maxAge = Double(max(1, folder.maxAgeDays)) * secondsPerDay
        let window = Double(max(1, folder.warnDays)) * secondsPerDay

        let expiry = effective.addingTimeInterval(maxAge)
        let noticeStart = record?.firstWarned ?? now
        let deadline = max(expiry, noticeStart.addingTimeInterval(window))

        let verdict: Verdict
        if now >= deadline {
            verdict = .trash
        } else if deadline.timeIntervalSince(now) <= window {
            verdict = .warn
        } else {
            verdict = .fresh
        }

        return Evaluation(folderID: folder.id,
                          folderName: folder.displayName,
                          item: item,
                          deadline: deadline,
                          verdict: verdict)
    }
}

enum Engine {
    struct RunOutcome {
        var trashed: [Evaluation] = []
        var failed: [(Evaluation, String)] = []
        /// Everything currently in its warning period (or overdue but blocked).
        var pending: [Evaluation] = []
        /// Subset of `pending` that has not been notified about today.
        var toNotify: [Evaluation] = []
        /// Items that were due but left alone because notifications are unavailable.
        var blocked = 0
    }

    /// Scans every enabled folder and evaluates every item. Has no side effects.
    static func evaluate(config: Config,
                         state: State,
                         now: Date,
                         fm: FileManager = .default,
                         useAddedDate: Bool = true) -> (evaluations: [Evaluation], errors: [String]) {
        var all: [Evaluation] = []
        var errors: [String] = []

        for folder in config.folders where folder.enabled {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.url.path, isDirectory: &isDir), isDir.boolValue else {
                errors.append("Folder not found: \(folder.path)")
                continue
            }
            if let reason = Safety.rejectionReason(for: folder.url) {
                errors.append("\(folder.path): \(reason)")
                continue
            }
            do {
                let items = try FolderScanner.scan(folder: folder.url, fm: fm, useAddedDate: useAddedDate)
                for item in items {
                    let record = state.records[item.url.path]
                    var ev = Planner.evaluate(item: item, folder: folder, record: record, now: now)
                    // Measuring a folder walks its whole tree, so only do it for items that matter.
                    if ev.verdict != .fresh { ev.size = FolderScanner.size(of: item.url, fm: fm) }
                    all.append(ev)
                }
            } catch {
                errors.append("\(folder.path): \(error.localizedDescription)")
            }
        }
        return (all, errors)
    }

    /// Applies the plan: trashes what is due, records who has been warned, and works
    /// out what still needs a notification today.
    ///
    /// Nothing is ever trashed unless the user could actually have been warned
    /// (`canNotify`) *and* a warning was really sent for that item earlier.
    static func apply(evaluations: [Evaluation],
                      state: inout State,
                      now: Date,
                      canNotify: Bool,
                      trash: (URL) throws -> Void) -> RunOutcome {
        var outcome = RunOutcome()
        var newRecords: [String: ItemRecord] = [:]
        let calendar = Calendar.current

        for ev in evaluations {
            let key = ev.item.url.path
            var record = state.records[key] ?? ItemRecord()

            switch ev.verdict {
            case .fresh:
                // Keep only the "Keep" marker; warning history is no longer relevant.
                if let kept = record.keptAt { newRecords[key] = ItemRecord(keptAt: kept) }

            case .trash:
                if canNotify && record.firstWarned != nil {
                    do {
                        try trash(ev.item.url)
                        outcome.trashed.append(ev)
                    } catch {
                        outcome.failed.append((ev, error.localizedDescription))
                        outcome.pending.append(ev)
                        newRecords[key] = record
                    }
                } else {
                    outcome.blocked += 1
                    outcome.pending.append(ev)
                    newRecords[key] = record
                }

            case .warn:
                if canNotify {
                    let notifiedToday = record.lastNotified.map { calendar.isDate($0, inSameDayAs: now) } ?? false
                    if !notifiedToday {
                        outcome.toNotify.append(ev)
                        record.lastNotified = now
                    }
                    if record.firstWarned == nil { record.firstWarned = now }
                }
                outcome.pending.append(ev)
                newRecords[key] = record
            }
        }

        state.records = newRecords
        return outcome
    }
}

enum Summary {
    /// "1.2 GB", "340 KB", ... in the same decimal units Finder uses.
    static func sizeText(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    /// Total size of the given items, e.g. "1.2 GB"; nil when nothing was measured.
    static func totalSizeText(for evaluations: [Evaluation]) -> String? {
        let total = evaluations.reduce(Int64(0)) { $0 + $1.size }
        return total > 0 ? sizeText(total) : nil
    }

    /// Text for the "these files are about to be trashed" notification.
    static func notification(for evaluations: [Evaluation],
                             now: Date,
                             maxLines: Int = 6) -> (title: String, body: String) {
        let sorted = evaluations.sorted { $0.deadline < $1.deadline }
        let n = sorted.count
        let latest = max(1, sorted.map { $0.daysLeft(now: now) }.max() ?? 1)

        let title = "\(n) \(n == 1 ? "item" : "items") will be moved to the Trash within \(latest) \(latest == 1 ? "day" : "days")"

        let multipleFolders = Set(sorted.map { $0.folderID }).count > 1
        var lines: [String] = sorted.prefix(maxLines).map { ev in
            let d = ev.daysLeft(now: now)
            let when = d <= 0 ? "today" : (d == 1 ? "tomorrow" : "in \(d) days")
            let name = multipleFolders ? "\(ev.folderName)/\(ev.name)" : ev.name
            return "• \(name) — \(when)"
        }
        if n > maxLines { lines.append("…and \(n - maxLines) more") }
        return (title, lines.joined(separator: "\n"))
    }
}
