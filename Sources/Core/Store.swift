import Foundation

/// Reads and writes config, state and the history log in
/// ~/Library/Application Support/SweepSchedule.
struct Store {
    let dir: URL

    init(dir: URL = Store.defaultDir) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static var defaultDir: URL {
        // Development aid (used for README screenshots): point the app at a throwaway support folder.
        if let override = ProcessInfo.processInfo.environment["SWEEP_SCHEDULE_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SweepSchedule", isDirectory: true)
    }

    var configURL: URL { dir.appendingPathComponent("config.json") }
    var stateURL: URL { dir.appendingPathComponent("state.json") }
    var historyURL: URL { dir.appendingPathComponent("history.log") }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Config

    func loadConfig() -> Config {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: configURL) {
            if var cfg = try? makeDecoder().decode(Config.self, from: data) {
                cfg.checkHour = min(max(cfg.checkHour, 0), 23)
                return cfg
            }
            // Unreadable: keep a copy so a hand-edit is never silently lost.
            let backup = dir.appendingPathComponent("config.json.bak")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: configURL, to: backup)
        }
        let cfg = Config.default
        saveConfig(cfg)
        return cfg
    }

    func saveConfig(_ config: Config) {
        if let data = try? makeEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    // MARK: State

    func loadState() -> State {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? makeDecoder().decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    func saveState(_ state: State) {
        if let data = try? makeEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    // MARK: History

    func appendHistory(_ lines: [String]) {
        guard !lines.isEmpty,
              let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: historyURL)
        }
    }
}
