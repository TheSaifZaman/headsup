#!/bin/bash
# Builds Heads Up and produces shareable artifacts in dist/:
#   - "Heads Up.app"  (runnable locally)
#   - HeadsUp.dmg      (share this — includes install instructions)
#   - HeadsUp.zip      (alternative to the dmg)
# Tries a universal (Apple Silicon + Intel) build, falls back to native arch.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="2.1"

echo "==> Building…"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN=".build/apple/Products/Release/HeadsUp"
    echo "    Universal binary (arm64 + x86_64)"
else
    echo "    Universal build unavailable; building native arch"
    swift build -c release
    BIN=".build/release/HeadsUp"
fi

APP="dist/Heads Up.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/HeadsUp"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HeadsUp</string>
    <key>CFBundleIdentifier</key>
    <string>local.headsup.app</string>
    <key>CFBundleName</key>
    <string>Heads Up</string>
    <key>CFBundleDisplayName</key>
    <string>Heads Up</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Heads Up reads your calendars to show full-screen alerts before your meetings so you never miss one.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "==> App bundle: $APP"

echo "==> Packaging DMG and ZIP…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/How to Install.txt" <<'EOF'
HEADS UP — install instructions
===================================

1. Drag "Heads Up.app" onto the "Applications" shortcut in this window.

2. FIRST LAUNCH ONLY — this app isn't notarized by Apple, so macOS will warn you:
   - Open Applications, RIGHT-CLICK "Heads Up" and choose "Open",
     then click "Open" in the dialog.
   - If macOS still blocks it: System Settings -> Privacy & Security ->
     scroll down and click "Open Anyway".
   - Stubborn cases (terminal):
       xattr -dr com.apple.quarantine "/Applications/Heads Up.app"

3. Grant calendar access when asked.

4. Look for the eyes icon in your menu bar. Click it:
   - "Settings…" to pick calendars, add a Google Calendar secret iCal URL,
     set how many minutes before a meeting the alert fires, choose a theme.
   - "Schedule…" to see all past/upcoming meetings and reminders in a list
     or month calendar.
   - "New Reminder…" for one-off reminders (with an optional meeting link).
   - "Test Alert…" to preview the full-screen alert.

Google Calendar sync: Google Calendar (web) -> Settings -> pick your
calendar -> "Secret address in iCal format" -> copy the URL and paste it
in the app's Settings.

Requires macOS 14 or later.
EOF

hdiutil create -volname "Heads Up" -srcfolder "$STAGING" -ov -format UDZO "dist/HeadsUp-${VERSION}.dmg" >/dev/null
ditto -c -k --keepParent "$APP" "dist/HeadsUp-${VERSION}.zip"
rm -rf "$STAGING"

echo "==> Done:"
echo "    dist/Heads Up.app          (run locally:  open \"$APP\")"
echo "    dist/HeadsUp-${VERSION}.dmg (share this)"
echo "    dist/HeadsUp-${VERSION}.zip (alternative)"

# ./build.sh install — copy to /Applications so Spotlight/Launchpad find it.
if [[ "${1:-}" == "install" ]]; then
    TARGET="/Applications/Heads Up.app"
    if [[ ! -w /Applications ]]; then
        TARGET="$HOME/Applications/Heads Up.app"
        mkdir -p "$HOME/Applications"
    fi
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    echo "==> Installed: $TARGET"
fi
