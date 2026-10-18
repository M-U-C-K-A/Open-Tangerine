# Trial build status

Version 0.1.0, 18 October 2026.

This supersedes the earlier image-only prototype. The active app is `NativeApp/Sources`, substantially derived from MIT-licensed Satsuma; the old exploratory code in `Prototypes` is not compiled.

Build environment: Apple silicon, macOS 26.2, Swift 6.3.3 / Xcode 26.6. Direct `swiftc` build avoids a SwiftPM nested-sandbox failure in the development environment. No sandbox protections were disabled.

Validation: inherited deterministic suite 20/20 passed. Real conversion and output-safety checks are in `NativeApp/Tests/IntegrationTests.swift`; the final results will be recorded after execution. Compiler deprecation warnings inherited from upstream remain, primarily older AVFoundation and SwiftUI APIs.

The app is ad-hoc signed for local testing, not notarized and not sandboxed. Full route/tool coverage, reliable Finder drag behavior across apps and monitors, performance on large batches, and malicious-file testing are not yet verified. The GitHub workflow is provided but is not claimed to have passed until its actual run completes.

Archive conversion is disabled. All other catalogue entries remain experimental; see README for missing features and security limits.
