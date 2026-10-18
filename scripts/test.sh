#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
find NativeApp/Sources -name '*.swift' ! -path '*/Sources/App.swift' -print0 | xargs -0 xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build/module-cache" NativeApp/Tests/SatsumaTests.swift -o .build/tests
.build/tests
find NativeApp/Sources -name '*.swift' ! -path '*/Sources/App.swift' -print0 | xargs -0 xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build/module-cache" NativeApp/Tests/IntegrationTests.swift -o .build/integration-tests
.build/integration-tests
