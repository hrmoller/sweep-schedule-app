import AppKit
import CoreGraphics

/// Development aid for producing the README screenshots without granting Screen Recording
/// permission to anything: an app may always image its own windows.
///
/// Environment variables recognised by the app (all optional, all for development only):
///   SWEEP_SCHEDULE_SHOW=settings,review,menu   open these on launch
///   SWEEP_SCHEDULE_SNAPSHOT_DIR=<dir>           write a PNG of every own window to <dir>, then quit
///   SWEEP_SCHEDULE_SUPPORT_DIR=<dir>            use <dir> instead of ~/Library/Application Support/SweepSchedule
///   SWEEP_SCHEDULE_IGNORE_ADDED_DATE=1          age files by modification date only (demo files are brand new)
///   SWEEP_SCHEDULE_HOME=<dir>                   `~` in watched-folder paths expands against <dir>
///
/// Every on-screen window owned by this process (regular windows, the status item, an open menu)
/// is written to `<dir>/<index>-<title>.png` and the app then quits.
@MainActor
enum Snapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SWEEP_SCHEDULE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func captureAllWindowsAndQuit(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []

        var index = 0
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, number,
                                                      [.boundsIgnoreFraming, .bestResolution]) else { continue }
            let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
            let title = (entry[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (layer == 0 ? "window" : (layer >= 100 ? "menu" : "statusitem"))
            let safe = title.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression).lowercased()
            index += 1
            let url = dir.appendingPathComponent("\(index)-\(safe).png")
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
        NSApp.terminate(nil)
    }
}
