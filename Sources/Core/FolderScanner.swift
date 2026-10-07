import Foundation

/// Lists the direct children of a watched folder and works out how old each one is.
///
/// Age is measured from the *most recent* of:
///   - the macOS "Date Added" to the folder (so a freshly downloaded old file is not
///     trashed straight away), and
///   - the content modification date (so a file you keep editing stays),
///   - for folders: the newest modification date of anything inside them.
enum FolderScanner {
    /// Browsers' partial downloads must never be touched.
    static let inProgressSuffixes = [
        ".crdownload", ".download", ".part", ".partial", ".opdownload", ".aria2", ".tmp"
    ]

    /// Safety valve for enormous folders (e.g. an unpacked node_modules).
    static let maxDescendantsInspected = 50_000

    static func isInProgressDownload(_ name: String) -> Bool {
        let lower = name.lowercased()
        return inProgressSuffixes.contains { lower.hasSuffix($0) }
    }

    /// - Parameter useAddedDate: tests pass `false` so back-dated modification
    ///   times are honoured (a just-created test file has "added" = now).
    static func scan(folder: URL,
                     fm: FileManager = .default,
                     useAddedDate: Bool = true) throws -> [ScannedItem] {
        var keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]
        #if canImport(Darwin)
        keys.append(.addedToDirectoryDateKey)
        #endif

        let children = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var result: [ScannedItem] = []
        for url in children {
            let name = url.lastPathComponent
            if isInProgressDownload(name) { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            var date = Date.distantPast
            #if canImport(Darwin)
            if useAddedDate, let added = values.addedToDirectoryDate { date = max(date, added) }
            #endif
            if let modified = values.contentModificationDate { date = max(date, modified) }
            if date == .distantPast, let created = values.creationDate { date = created }

            let isDir = values.isDirectory ?? false
            if isDir {
                date = max(date, newestModification(in: url, fm: fm))
            }

            // No usable date at all: treat as brand new so we never delete it.
            if date == .distantPast { date = Date() }

            result.append(ScannedItem(url: url, isDirectory: isDir, date: date))
        }
        return result
    }

    private static func newestModification(in dir: URL, fm: FileManager) -> Date {
        var newest = Date.distantPast
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return newest }

        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count > maxDescendantsInspected { break }
            if let m = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                newest = max(newest, m)
            }
        }
        return newest
    }
}
