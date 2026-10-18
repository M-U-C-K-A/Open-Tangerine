#!/bin/bash
set -euo pipefail
# 0.1.2: deterministic transition tests and nonactivating companion panel.
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
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$app/Contents/Resources"
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" NativeApp/Sources/UI/BrandArtwork.swift scripts/make-icon.swift -o .build/make-icon
.build/make-icon "$PWD/.build/AppIcon.iconset"
python3 scripts/package-icon.py .build/AppIcon.iconset "$app/Contents/Resources/AppIcon.icns"
cp LICENSE "$app/Contents/Resources/GPL-3.0.txt"
cp NativeApp/LICENSE "$app/Contents/Resources/Satsuma-MIT.txt"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
