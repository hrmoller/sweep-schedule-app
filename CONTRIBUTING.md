# Contributing

Thanks for helping out. Sweep Schedule moves people's files to the Trash, so the guiding rule is: **be conservative, and never surprise the user.**

## Getting set up

You need macOS 13+ and Xcode or the Command Line Tools.

```bash
./build.sh test      # runs the logic tests
./build.sh install   # builds and launches the app
```

Use a throwaway watched folder while developing (add one in Settings) rather than your real Downloads folder.

## Ground rules

- **Keep `Sources/Core` free of UI.** It may only import `Foundation`. All decisions about what gets warned about or trashed live there so they can be tested without a GUI.
- **Changes to deletion behaviour need tests** in `Tests/main.swift`. Cover both the case that should act and the case that must not.
- **Preserve the safety invariants:**
  - an item is trashed only after a notification was actually sent for it, and the full warning period has passed
  - nothing is trashed when notifications are unavailable
  - items go to the Trash, never straight to `removeItem`
  - system folders, the home folder and `~/Library` can't be watched
- **No network access and no telemetry.**
- Keep dependencies at zero; the app builds with `swiftc` alone.
- Don't add personal paths, names or identifiers to the source, tests or docs. Use generic examples such as `/Users/alice`.

## Pull requests

1. Fork and create a branch.
2. Make your change, with tests where behaviour changes.
3. Run `./build.sh test` and `./build.sh build`; CI runs the same commands on macOS.
4. Describe what changed and why, and mention anything you could not test (for example the UI on a particular macOS version).

## Releases

Merging to `main` publishes a release automatically (`.github/workflows/release.yml`): it runs the tests, builds a universal app, and attaches a zip and checksum to a new `v<major>.<minor>.<commits>` release. Docs-only changes don't trigger one. To bump the major or minor number, edit the `VERSION` file. A local `./build.sh package` uses `<major>.<minor>.0` unless you set `APP_VERSION`; only the workflow adds the commit count. Pull requests that change `build.sh`, `Info.plist`, `VERSION`, `Design/` or the workflow run the same steps without publishing, and keep the zip as a downloadable workflow artifact.

Releases are ad-hoc signed, not notarized (that needs a paid Apple Developer ID), which is why the README explains **Open Anyway**.

## Reporting bugs

Please include your macOS version, what you expected, and what happened. If files were trashed unexpectedly, attach the relevant lines from `~/Library/Application Support/SweepSchedule/history.log` (remove anything private).
