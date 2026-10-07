# CLAUDE.md

Guidance for Claude Code (and other AI assistants) working in this repository.

## What this is

Sweep Schedule is a native macOS menu bar app (Swift, AppKit shell + SwiftUI windows, macOS 13+). It moves items older than N days from watched folders (default `~/Downloads`, 30 days) to the Trash, after warning the user via notification M days in advance (default 5). Zero dependencies; built with plain `swiftc`.

## Commands

```bash
./build.sh test       # compile Sources/Core + Tests/main.swift and run the checks
./build.sh            # build build/SweepSchedule.app (ad-hoc signed)
./build.sh install    # build, copy to ~/Applications, launch
./build.sh package    # universal build zipped into dist/ (APP_VERSION=x.y.z stamps the version)
./build.sh uninstall
BUNDLE_ID=com.example.SweepSchedule ./build.sh build   # override the bundle identifier
```

There is no Xcode project or Package.swift. These commands require macOS with Xcode or the Command Line Tools; they cannot run on Linux. Run `./build.sh test` after any change to `Sources/Core`.

## Architecture

- `Sources/Core/` is **Foundation-only** and contains every decision:
  - `Models.swift`: `Config`, `WatchedFolder`, `SweepState`, `ItemRecord`, `ScannedItem`, `Evaluation`, `Verdict`
  - `FolderScanner.swift`: lists direct children, computes each item's age date
  - `Planner.swift`: `Planner.evaluate` (pure per-item verdict), `Engine.evaluate` (scan everything, no side effects), `Engine.apply` (trash what is due, record warnings, decide who to notify), `Summary` (notification text)
  - `Safety.swift`: refuses to watch `/`, the home folder, `~/Library`, system folders
  - `Store.swift`: JSON persistence in `~/Library/Application Support/SweepSchedule`
- `Sources/App/` is UI and system glue: `AppDelegate` (status item, menu, scheduler, windows), `AppModel` (observable state, runs checks), `Notifier` (UserNotifications, login item), `SettingsView`, `ReviewView`, `Entry` (`@main`).
- `Design/` holds the app icon: `AppIcon.svg` (1024 px master), `AppIcon-small.svg` (16/32 px variant) and `AppIcon.iconset/`. `build.sh` generates `AppIcon.icns` from the iconset with `iconutil`; the `.icns` is git-ignored.
- `Tests/main.swift` is a plain-Swift test runner (no XCTest). It is compiled together with `Sources/Core`, so Core must not import AppKit/SwiftUI.

## Rules that must not be broken

This app deletes (trashes) users' files. Treat these as invariants and keep tests for them:

1. An item is trashed only if (a) it is past its age limit, (b) a notification was actually sent for it (`firstWarned` set), and (c) at least `warnDays` have passed since `firstWarned`. Never-warned items get a full notice period starting now.
2. If notification permission is unavailable, nothing is trashed and nothing is marked as warned.
3. Use `FileManager.trashItem`. Never `removeItem` on user files.
4. Skip hidden files and in-progress downloads (`FolderScanner.inProgressSuffixes`).
5. Age = newest of "Date Added" and modification date (and, for folders, newest descendant modification).
6. "Keep" only restarts the age clock (`ItemRecord.keptAt`); it does not move or exempt the file permanently.

## Conventions

- Swift 5 language mode (`-swift-version 5`), target `macos13.0`.
- No third-party dependencies, no network calls, no telemetry.
- Keep behaviour changes in Core and cover them in `Tests/main.swift`; keep the UI layer thin.
- Never hardcode personal paths, names or identifiers. Use generic examples (`/Users/alice`) in tests and docs.
- Don't point manual testing at a real Downloads folder: add a scratch folder in Settings.

## Development environment variables

All optional, for development and the README screenshots only; see `Sources/App/Snapshots.swift`:
`SWEEP_SCHEDULE_SHOW` (open settings/review/menu on launch), `SWEEP_SCHEDULE_SNAPSHOT_DIR` (write PNGs of the app's own windows, then quit), `SWEEP_SCHEDULE_SUPPORT_DIR`, `SWEEP_SCHEDULE_HOME`, `SWEEP_SCHEDULE_IGNORE_ADDED_DATE`. The screenshots are taken against a throwaway home folder with made-up files so nothing from a real machine appears; never commit screenshots of real folders.

## Releases

`.github/workflows/release.yml` publishes a GitHub release on every push to `main` (except docs-only changes): version = `VERSION` file (`major.minor`) + commit count, universal binary, zip + sha256. A local `./build.sh package` uses `<major>.<minor>.0` unless `APP_VERSION` is set; only the workflow adds the commit count. Don't create tags or releases by hand. The workflow can't be exercised locally beyond `./build.sh package`; changes to it are checked by the pull request run, which builds but does not publish.

## Gotchas

- `UNUserNotificationCenter` crashes unless the process runs from a real `.app` bundle, so the executable can't be run bare. Use `./build.sh install`.
- Each rebuild is ad-hoc signed, so macOS may re-prompt for notification and folder permissions.
- `addedToDirectoryDate` only exists on Darwin; `FolderScanner` guards it with `#if canImport(Darwin)` and the tests pass `useAddedDate: false` so back-dated mtimes work.
