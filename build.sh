#!/bin/bash
# Builds VinylWidget.app — a universal (Apple Silicon + Intel) binary.
set -euo pipefail
cd "$(dirname "$0")"

APP="VinylWidget.app"
BIN="VinylWidget"
BUNDLE_ID="io.github.vinylwidget"
MIN_MACOS="13.0"
SOURCES=(Sources/Theme.swift Sources/ArtworkPalette.swift Sources/Settings.swift Sources/SpotifyController.swift
         Sources/WidgetView.swift Sources/SettingsView.swift Sources/main.swift)

if ! command -v swiftc >/dev/null 2>&1; then
    echo "✗ Swift isn't installed."
    echo "  Run this, let it finish, then try again:   xcode-select --install"
    exit 1
fi

rm -rf "$APP" .build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build

compile() {   # $1 = arch triple, $2 = output
    swiftc -O -target "$1" -framework AppKit -framework SwiftUI \
        "${SOURCES[@]}" -o "$2" 2>".build/$(basename "$2").log"
}

echo "› compiling…"
BUILT=()
for arch in arm64 x86_64; do
    if compile "${arch}-apple-macos${MIN_MACOS}" ".build/${BIN}-${arch}"; then
        BUILT+=(".build/${BIN}-${arch}")
        echo "  ✓ ${arch}"
    else
        echo "  ! ${arch} failed (see .build/${BIN}-${arch}.log)"
    fi
done

if [ ${#BUILT[@]} -eq 0 ]; then
    echo "✗ build failed:"
    cat .build/*.log
    exit 1
fi

lipo -create -output "$APP/Contents/MacOS/$BIN" "${BUILT[@]}"
echo "› architectures: $(lipo -archs "$APP/Contents/MacOS/$BIN")"

[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Vinyl Widget</string>
    <key>CFBundleDisplayName</key><string>Vinyl Widget</string>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Vinyl Widget needs this to show what Spotify is playing and to control playback.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (ad-hoc signing skipped)"
rm -rf .build
echo "✓ built $(pwd)/$APP"
