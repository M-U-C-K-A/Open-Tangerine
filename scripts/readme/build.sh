#!/bin/bash
# Regenerate the README art in docs/readme/.
#
#   ./scripts/readme/build.sh            animated SVGs (light + dark) and hairline figures
#   ./scripts/readme/build.sh --screens  also the app screenshots (compiles the app sources, ~1 min)
#
# Preview everything with `python3 -m http.server` at the repository root, then
# open http://localhost:8000/scripts/readme/preview.html
set -euo pipefail
cd "$(dirname "$0")/../.."

node scripts/readme/build.mjs
node scripts/readme/hairline.mjs

if [[ "${1:-}" == "--screens" ]]; then
  command -v cwebp >/dev/null || { echo "cwebp is required for screenshots (brew install webp)" >&2; exit 1; }
  out="$PWD/.build/readme-screens"
  rm -rf "$out"
  mkdir -p "$out" .build/module-cache docs/readme/screens
  find NativeApp/Sources -name '*.swift' ! -path '*/Sources/App.swift' -print0 \
    | xargs -0 xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build/module-cache" scripts/readme/Screenshots.swift -o .build/readme-screenshots
  .build/readme-screenshots "$out" -AppleLanguages '(en)' -AppleLocale en_US
  for png in "$out"/*.png; do
    cwebp -quiet -q 88 -alpha_q 100 -m 6 "$png" -o "docs/readme/screens/$(basename "${png%.png}").webp"
  done
  echo "docs/readme/screens: $(ls docs/readme/screens | wc -l | tr -d ' ') files"
fi
