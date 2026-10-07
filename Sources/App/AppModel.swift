import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var config: Config {
        didSet { store.saveConfig(config) }
    }
    /// Items currently inside their warning period.
    @Published private(set) var pending: [Evaluation] = []
    @Published private(set) var statusLine = "Not checked yet"
    @Published private(set) var isRunning = false
    @Published private(set) var notificationsOK = true
    @Published private(set) var errors: [String] = []

    private let store: Store
    private var state: SweepState
    /// Development aid (README screenshots): demo files are freshly created, so their "Date Added" is today.
    private let useAddedDate = ProcessInfo.processInfo.environment["SWEEP_SCHEDULE_IGNORE_ADDED_DATE"] == nil

    init(store: Store = Store()) {
        self.store = store
        self.config = store.loadConfig()
        self.state = store.loadState()
        if let last = state.lastRun {
            statusLine = "Last check: \(last.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    var historyURL: URL {
        // Make sure the file exists so "Open History Log" always has something to open.
        if !FileManager.default.fileExists(atPath: store.historyURL.path) {
            try? Data().write(to: store.historyURL)
        }
        return store.historyURL
    }

    // MARK: Scheduling

    /// A check is due once per calendar day, after the configured hour.
    /// It also runs immediately the very first time the app starts.
    func isDue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let last = state.lastRun else { return true }
        if calendar.isDate(last, inSameDayAs: now) { return false }
        return calendar.component(.hour, from: now) >= config.checkHour
    }

    func setupLoginItemIfNeeded() {
        guard !state.loginConfigured else { return }
        try? LoginItem.set(true)
        state.loginConfigured = true
        store.saveState(state)
    }

    // MARK: Checking

    /// Read-only: refreshes the list of expiring items without notifying or trashing.
    func preview() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let cfg = config, st = state, now = Date(), added = useAddedDate
        let result = await Task.detached(priority: .utility) {
            Engine.evaluate(config: cfg, state: st, now: now, useAddedDate: added)
        }.value

        pending = result.evaluations
            .filter { $0.verdict != .fresh }
            .sorted { $0.deadline < $1.deadline }
        errors = result.errors
    }

    /// The real thing: warn, then trash whatever has had its full notice period.
    func runCheck() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let cfg = config, st = state, now = Date(), added = useAddedDate
        let result = await Task.detached(priority: .utility) {
            Engine.evaluate(config: cfg, state: st, now: now, useAddedDate: added)
        }.value

        let canNotify = await Notifier.ensureAuthorized()
        notificationsOK = canNotify

        var newState = state
        let outcome = Engine.apply(evaluations: result.evaluations,
                                   state: &newState,
                                   now: now,
                                   canNotify: canNotify) { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        newState.lastRun = now
        state = newState
        store.saveState(state)

        let stamp = ISO8601DateFormatter().string(from: now)
        store.appendHistory(outcome.trashed.map { "\(stamp)\t\($0.folderName)\t\($0.item.url.path)" })

        pending = outcome.pending.sorted { $0.deadline < $1.deadline }
        errors = result.errors + outcome.failed.map { "\($0.0.name): \($0.1)" }

        if !outcome.toNotify.isEmpty {
            // List everything that is pending, not just the newly-notified items, because
            // the new notification replaces the previous one.
            let text = Summary.notification(for: outcome.pending, now: now)
            await Notifier.sendExpiring(title: text.title, body: text.body)
        }

        var parts: [String] = []
        parts.append("\(outcome.pending.count) expiring")
        if !outcome.trashed.isEmpty { parts.append("\(outcome.trashed.count) moved to Trash") }
        statusLine = "Last check: \(now.formatted(date: .omitted, time: .shortened)) — " + parts.joined(separator: ", ")
        if !canNotify {
            statusLine = "Notifications are off — nothing will be trashed"
        } else if !errors.isEmpty {
            statusLine += " (\(errors.count) problem\(errors.count == 1 ? "" : "s"))"
        }
    }

    // MARK: User actions

    /// "Keep": restarts the age clock for this item.
    func keep(_ evaluation: Evaluation) {
        guard !isRunning else { return }
        state.records[evaluation.item.url.path] = ItemRecord(keptAt: Date())
        store.saveState(state)
        pending.removeAll { $0.id == evaluation.id }
    }

    /// Returns an error message if the folder can't be watched.
    func addFolder(_ url: URL) -> String? {
        if let reason = Safety.rejectionReason(for: url) { return reason }
        let path = WatchedFolder.abbreviateTilde(url.path)
        if config.folders.contains(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) {
            return "That folder is already being watched."
        }
        config.folders.append(WatchedFolder(path: path))
        return nil
    }

    func removeFolder(id: UUID) {
        config.folders.removeAll { $0.id == id }
    }
}
