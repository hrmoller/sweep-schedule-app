#!/usr/bin/env bash
# Build, test, package, install or uninstall SweepSchedule.
#
#   ./build.sh            build build/SweepSchedule.app
#   ./build.sh test       compile and run the core logic tests (no GUI needed)
#   ./build.sh package    universal build (Apple silicon + Intel), zipped into dist/
#   ./build.sh install    build, copy to ~/Applications and launch
#   ./build.sh uninstall  quit the app and remove it from ~/Applications
#
# Environment:
#   UNIVERSAL=1      build for arm64 and x86_64 instead of just this Mac's architecture
#   APP_VERSION=x.y.z  stamp this version into the app's Info.plist
#                    (`package` defaults to <VERSION file>.0; the release workflow adds the commit count)
#   BUNDLE_ID=...    use your own reverse-DNS bundle identifier
#
# Needs the Xcode Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

NAME="SweepSchedule"
APP="build/$NAME.app"

build_app() {
    local archs=("$(uname -m)")
    if [[ "${UNIVERSAL:-}" == "1" ]]; then archs=(arm64 x86_64); fi

    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" build

    local bins=()
    for arch in "${archs[@]}"; do
        swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos13.0" \
            Sources/Core/*.swift Sources/App/*.swift \
            -o "build/$NAME-$arch"
        bins+=("build/$NAME-$arch")
    done
    if (( ${#bins[@]} > 1 )); then
        lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/$NAME"
    else
        cp "${bins[0]}" "$APP/Contents/MacOS/$NAME"
    fi
    rm -f "${bins[@]}"

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
    # Optional: stamp a version (releases do this), e.g.  APP_VERSION=0.1.7 ./build.sh package
    if [[ -n "${APP_VERSION:-}" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
    fi
    # Ad-hoc signature: enough for notifications and the login item on your own Mac.
    codesign --force --sign - "$APP"
    echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$NAME"))"
}

run_tests() {
    mkdir -p build
    swiftc -swift-version 5 Sources/Core/*.swift Tests/main.swift -o build/coretests
    ./build/coretests
}

package_app() {
    export UNIVERSAL=1
    export APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < VERSION).0}"
    build_app

    local zip="$NAME-$APP_VERSION.zip"
    mkdir -p dist
    rm -f "dist/$zip" "dist/$zip.sha256"
    # ditto keeps the bundle's structure and signature intact (plain `zip` can break them).
    ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$zip"
    (cd dist && shasum -a 256 "$zip" > "$zip.sha256")
    echo "Packaged dist/$zip"
}

case "${1:-build}" in
    build)
        build_app
        ;;
    test)
        run_tests
        ;;
    package)
        package_app
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
        echo "Usage: $0 [build|test|package|install|uninstall]" >&2
        exit 1
        ;;
esac
