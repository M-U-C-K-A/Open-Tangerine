# Trial build status

Version 0.1.0, 18 October 2026.

This supersedes the earlier image-only prototype. The active app is `NativeApp/Sources`, substantially derived from MIT-licensed Satsuma; the old exploratory code in `Prototypes` is not compiled.

Build environment: Apple silicon, macOS 26.2, Swift 6.3.3 / Xcode 26.6. Direct `swiftc` build avoids a SwiftPM nested-sandbox failure in the development environment. No sandbox protections were disabled.

Validation: inherited deterministic suite 20/20 passed. Real PNG → JPEG, TIFF and PDF conversion checks passed, as did occupied-destination protection, original preservation, malformed-image rejection, archive disabling and literal subprocess arguments. Settings and FFmpeg 9.0.1 detection were verified in the running app. Tests are in `NativeApp/Tests/IntegrationTests.swift`; HEIC encoding was attempted and failed in the restricted execution environment (IOSurface bridge error); it is not counted as verified. Compiler deprecation warnings inherited from upstream remain, primarily older AVFoundation and SwiftUI APIs.

The app is ad-hoc signed for local testing, not notarized and not sandboxed. Full route/tool coverage, reliable Finder drag behavior across apps and monitors, performance on large batches, and malicious-file testing are not yet verified. The GitHub workflow is provided but is not claimed to have passed until its actual run completes.

Archive conversion is disabled. All other catalogue entries remain experimental; see README for missing features and security limits.

Packaging: Info.plist validation and ad-hoc signature verification passed. LaunchServices returned -10827 when opening the bundle from this restricted workspace; launching its executable directly opened the Settings window successfully. Applications directories are not writable in this session, so no system installation is claimed.
