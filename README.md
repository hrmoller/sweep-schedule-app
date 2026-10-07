# Sweep Schedule

A small, native macOS menu bar app that keeps your Downloads folder (and any other folders you choose) from silently growing forever.

- Items **older than 30 days** are moved to the **Trash**. Nothing is ever deleted outright.
- **5 days before** that happens you get a notification listing what is about to go, so you have time to move things elsewhere.
- Click the notification (or the menu bar icon) to open a review window with **Reveal in Finder** and **Keep** for each item.
- You get a reminder every day until the item is gone or rescued.
- Every folder has its own age limit and warning period, configurable in a **Settings** window.

It runs in the background with no Dock icon, starts at login, and checks once a day (09:00 by default, or right after wake-up if the Mac was asleep). Everything stays on your machine: no network access, no analytics.

## Requirements

- macOS 13 (Ventura) or later
- Xcode or the Xcode Command Line Tools (`xcode-select --install`) to build it

## Install

```bash
git clone https://github.com/hrmoller/sweep-schedule-app.git
cd sweep-schedule-app
./build.sh test       # optional: run the logic tests
./build.sh install    # build, copy to ~/Applications, and launch
```

Other commands:

| Command | What it does |
|---|---|
| `./build.sh` | Build `build/SweepSchedule.app` |
| `./build.sh test` | Compile and run the core logic tests (no GUI needed) |
| `./build.sh install` | Build, copy to `~/Applications` and start it |
| `./build.sh uninstall` | Quit the app and remove it from `~/Applications` |

To use your own bundle identifier: `BUNDLE_ID=com.example.SweepSchedule ./build.sh install`.

### First launch

1. Allow **notifications** when asked. The app will not trash anything while notifications are off, because it could not warn you.
2. Allow access to **Downloads** (and any other protected folder) when macOS asks.
3. The app registers itself as a login item. Turn that off in its Settings window or under System Settings > General > Login Items.

> **Heads up:** the first check on a folder full of old files will flag all of them at once. Nothing is trashed until the notice period has passed, so open **Review Expiring Items…** and press **Keep** on anything you want to retain.

## How it decides what to trash

- **Age** is the newest of "Date Added to the folder" and "last modified". For a folder it also considers everything inside it, so a project folder you are still working in is not trashed. A freshly downloaded old file is not trashed straight away.
- **Only direct children** of a watched folder are considered; a subfolder is moved as one item.
- **Skipped:** hidden files and in-progress downloads (`.crdownload`, `.download`, `.part`, ...).
- **Full notice guaranteed:** an item is only trashed once it is past the age limit *and* at least "warn days" have passed since the first notification about it. If the app was off for a while, nothing is trashed without notice.
- **No notifications, no deletion:** if notification permission is missing, nothing is trashed.
- **Keep** restarts an item's age clock from today. It does not move the file. To keep a file permanently, move it out of the watched folder.
- Folders like `/`, your home folder, `~/Library` and system folders are refused.

To restore something the app trashed, open the Trash and choose **Put Back**.

## Files the app writes

Everything lives in `~/Library/Application Support/SweepSchedule/`:

| File | Contents |
|---|---|
| `config.json` | Watched folders, limits and the daily check hour |
| `state.json` | Which items have been warned about, and when |
| `history.log` | Tab-separated log of every item moved to the Trash |

## Project layout

```
Sources/Core/     Foundation-only logic: scanning, planning, state (unit-testable, no UI)
Sources/App/      Menu bar app, notifications, Settings and Review windows
Tests/main.swift  Plain-Swift test runner for Sources/Core (no XCTest needed)
Design/           App icon: SVG masters and the .iconset (the .icns is built by build.sh)
build.sh          Build, test, install and uninstall
```

### App icon

`Design/AppIcon.svg` is the 1024 px master (a bin with a file dropping in, inside a timer ring) and
`Design/AppIcon-small.svg` is a simplified variant used for the 16 and 32 px sizes, following Apple's
advice to reduce detail at small sizes. `Design/AppIcon.iconset/` holds the rendered PNGs; `build.sh`
turns them into `AppIcon.icns` with `iconutil`. To change the icon, edit the SVGs, re-render the PNGs
at each size into the iconset, and rebuild.

The core has no dependency on AppKit or SwiftUI, which keeps the deletion rules testable and easy to review.

## Troubleshooting

- **No notifications appear:** check System Settings > Notifications > Sweep Schedule. The menu shows a warning while notifications are disabled.
- **Permission prompts after rebuilding:** the app is ad-hoc signed, so macOS treats each rebuild as a new app and may ask again.
- **Folders on external drives** use that drive's own Trash.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. Because this app removes files, changes to the deletion rules need tests.

## License

[MIT](LICENSE)
