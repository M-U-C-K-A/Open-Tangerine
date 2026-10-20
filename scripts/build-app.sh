#!/bin/bash
set -euo pipefail
# 0.3.0 (fork): color palette, document scanning, searchable PDFs, video enhancement, social formats, Markdown ↔ HTML ↔ Word.
cd "$(dirname "$0")/.."
app="$PWD/dist/Open Tangerine.app"
mkdir -p "$app/Contents/MacOS" "$PWD/.build/module-cache"
find NativeApp/Sources -name '*.swift' -print0 | xargs -0 xcrun swiftc -swift-version 5 -O -parse-as-library -module-cache-path "$PWD/.build/module-cache" -o "$app/Contents/MacOS/OpenTangerine"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OpenTangerine</string>
<key>CFBundleIdentifier</key><string>com.syntaxerror.opentangerine</string>
<key>CFBundleName</key><string>Open Tangerine</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>16</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSSpeechRecognitionUsageDescription</key><string>Open Tangerine turns what is said in your videos and recordings into subtitles, on this Mac.</string>
<key>NSServices</key><array>
<dict><key>NSMenuItem</key><dict><key>default</key><string>Convert with Open Tangerine</string></dict><key>NSMessage</key><string>convertFiles</string><key>NSSendFileTypes</key><array><string>public.item</string></array></dict>
<dict><key>NSMenuItem</key><dict><key>default</key><string>Open Tangerine Tools</string></dict><key>NSMessage</key><string>openTools</string><key>NSSendFileTypes</key><array><string>public.item</string></array></dict>
<dict><key>NSMenuItem</key><dict><key>default</key><string>Open Tangerine File Actions</string></dict><key>NSMessage</key><string>fileActions</string><key>NSSendFileTypes</key><array><string>public.item</string></array></dict>
</array>
<key>NSAppleEventsUsageDescription</key><string>Open Tangerine asks Finder which files are selected when you open the wheel by holding Shift alone. Nothing else is read.</string>
</dict></plist>
PLIST
mkdir -p "$app/Contents/Resources"
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" NativeApp/Sources/UI/BrandArtwork.swift scripts/make-icon.swift -o .build/make-icon
.build/make-icon "$PWD/.build/AppIcon.iconset"
python3 scripts/package-icon.py .build/AppIcon.iconset "$app/Contents/Resources/AppIcon.icns"
cp LICENSE "$app/Contents/Resources/GPL-3.0.txt"
cp NativeApp/LICENSE "$app/Contents/Resources/Satsuma-MIT.txt"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
# Developer trials use ad-hoc signing. Developer ID + notarization is required for trusted public distribution.
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app"
else
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"
test -x "$app/Contents/MacOS/OpenTangerine"
plutil -lint "$app/Contents/Info.plist"
printf 'Built %s\n' "$app"
