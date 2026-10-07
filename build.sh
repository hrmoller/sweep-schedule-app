#!/usr/bin/env bash
# Build, test, install or uninstall SweepSchedule.
#
#   ./build.sh            build build/SweepSchedule.app
#   ./build.sh test       compile and run the core logic tests (no GUI needed)
#   ./build.sh install    build, copy to ~/Applications and launch
#   ./build.sh uninstall  quit the app and remove it from ~/Applications
#
# Needs the Xcode Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

NAME="SweepSchedule"
APP="build/$NAME.app"
TARGET="$(uname -m)-apple-macos13.0"

build_app() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    swiftc -O -swift-version 5 -parse-as-library -target "$TARGET" \
        Sources/Core/*.swift Sources/App/*.swift \
        -o "$APP/Contents/MacOS/$NAME"
    cp Info.plist "$APP/Contents/Info.plist"
    mkdir -p "$APP/Contents/Resources"
    # App icon: build the .icns from the iconset if it is missing or stale.
    if [[ ! -f Design/AppIcon.icns || Design/AppIcon.iconset -nt Design/AppIcon.icns ]]; then
        iconutil -c icns Design/AppIcon.iconset -o Design/AppIcon.icns
    fi
    cp Design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    # Optional: use your own reverse-DNS bundle identifier, e.g.
    #   BUNDLE_ID=com.example.SweepSchedule ./build.sh install
    if [[ -n "${BUNDLE_ID:-}" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
    fi
    # Ad-hoc signature: enough for notifications and the login item on your own Mac.
    codesign --force --sign - "$APP"
    echo "Built $APP"
}

run_tests() {
    mkdir -p build
    swiftc -swift-version 5 Sources/Core/*.swift Tests/main.swift -o build/coretests
    ./build/coretests
}

case "${1:-build}" in
    build)
        build_app
        ;;
    test)
        run_tests
        ;;
    install)
        build_app
        pkill -x "$NAME" 2>/dev/null || true
        mkdir -p "$HOME/Applications"
        rm -rf "$HOME/Applications/$NAME.app"
        cp -R "$APP" "$HOME/Applications/$NAME.app"
        open "$HOME/Applications/$NAME.app"
        echo "Installed to ~/Applications/$NAME.app and started."
        ;;
    uninstall)
        pkill -x "$NAME" 2>/dev/null || true
        rm -rf "$HOME/Applications/$NAME.app"
        echo "Removed the app. Settings are kept in ~/Library/Application Support/SweepSchedule."
        echo "If it is still listed under System Settings > General > Login Items, remove it there."
        ;;
    *)
        echo "Usage: $0 [build|test|install|uninstall]" >&2
        exit 1
        ;;
esac
