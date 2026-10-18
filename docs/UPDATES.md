# Updates and notch · 0.1.2

Notch is the new default, including a one-time migration from earlier trials. Users can switch back to Card afterward. The original citrus character animates at 12 frames/second while work is active, stops when idle and respects Reduce Motion. Up to three job rows are visible; larger batches scroll. No Codex hooks, agent monitoring or permissions were added.

The referenced app was [Coucou](https://github.com/Louis-CFM/coucou). Its source is MIT but [LICENSE-ASSETS.md](https://github.com/Louis-CFM/coucou/blob/main/LICENSE-ASSETS.md) reserves the Mochi character, expressions and animations. No Coucou source or artwork was copied. Open Tangerine uses its own citrus character.

The menu-bar Check for Updates command checks this repository's latest public GitHub release, compares strict three-part versions numerically, and opens the fixed repository release page on request. Automatic checks occur at most once daily after successful checks; requests send no filenames, file content or account credentials. GitHub receives normal connection metadata. Offline, rate-limited and unpublished-release cases are reported for manual checks.

This is an update notification/download flow, **not automatic installation**. A signed update channel (for example Sparkle with a protected signing key), notarized binaries and rollback verification are required before shipping in-app replacement. Do not disable macOS security to install an update.

The release workflow tests, builds and publishes a versioned ZIP when the build-script version changes. It never overwrites an existing release. A GitHub Actions failure means that release is not published; local packaged builds remain available separately.

## Character interaction

The wheel opens a watching preview in notch mode. Hovering different options changes the gaze and caption. Enqueueing a job triggers acknowledgment, followed by processing. Successful completion triggers delivery then a happy expression; failures and cancellation have separate expressions. Delayed transitions use generation tokens so stale animation completions cannot overwrite newer states. Version comparison and interrupted character transitions passed the dedicated interaction tests. Live visual review remains necessary because this execution environment has blocked native app registration.
