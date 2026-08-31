#!/bin/bash
# One-command install for Vinyl Widget.
#   ./install.sh
# Builds the app from source and puts it in /Applications, then launches it.
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '%s\n' "$*"; }

say ""
say "  ▁▁▁  Vinyl Widget"
say ""

# 1. macOS version
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 13 ]; then
    say "✗ Needs macOS 13 (Ventura) or newer. You're on $(sw_vers -productVersion)."
    exit 1
fi

# 2. Swift compiler
if ! command -v swiftc >/dev/null 2>&1; then
    say "→ Apple's developer tools are needed to build this (one-time, ~1GB)."
    say "  A system dialog will open. Click Install, wait for it to finish,"
    say "  then run this script again."
    xcode-select --install 2>/dev/null || true
    exit 1
fi

# 3. Spotify
if [ ! -d "/Applications/Spotify.app" ] && ! mdfind "kMDItemCFBundleIdentifier == 'com.spotify.client'" 2>/dev/null | grep -q .; then
    say "! Spotify doesn't seem to be installed. The widget needs the Spotify"
    say "  desktop app: https://www.spotify.com/download/mac/"
    say "  Continuing anyway — install it whenever you like."
    say ""
fi

# 4. Build
./build.sh

# 5. Install
DEST="/Applications/VinylWidget.app"
if [ -d "$DEST" ]; then
    say "› replacing the copy in /Applications…"
    pkill -f "VinylWidget.app/Contents/MacOS/VinylWidget" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST"
fi
cp -R VinylWidget.app "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

say ""
say "✓ Installed to /Applications/VinylWidget.app"
say ""
say "  Launching it now. macOS will ask once for permission to control"
say "  Spotify — click Allow, or the widget can't read what's playing."
say ""
say "  Look for the ⏺ disc icon in your menu bar to customize it."
say ""
open "$DEST"
