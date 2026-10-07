import Foundation

/// Guards against pointing the cleaner at something catastrophic.
enum Safety {
    private static let blockedPrefixes = [
        "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/etc", "/dev", "/cores"
    ]
    private static let blockedExact = ["/", "/Users", "/Volumes", "/private", "/var", "/opt", "/tmp"]

    /// Returns a human-readable reason if the folder must not be watched, otherwise nil.
    static func rejectionReason(
        for url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        let h = home.standardizedFileURL.resolvingSymlinksInPath().path

        if p == h { return "Your home folder can't be watched." }
        if p == h + "/Library" || p.hasPrefix(h + "/Library/") {
            return "Your Library folder can't be watched."
        }
        if blockedExact.contains(p) { return "This is a system folder and can't be watched." }
        if blockedPrefixes.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) {
            return "This is a system folder and can't be watched."
        }
        return nil
    }
}
