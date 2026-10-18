# Open Tangerine — Product Requirements and Research

Version 0.1 • 18 October 2026 • Owner: Syntax Error Private Limited (intended; title and contribution agreements to verify)

Status: development proposal, not a production readiness or legal opinion. Working name. Independent from Tangerine for Mac. Final owner instruction permits commercial sale and prioritizes genuine open source. Selected license: GPL-3.0-only. Earlier no-sale and source-available proposals are superseded.

Evidence key: **Certain** = directly documented by the linked source or observed in the workspace; **Likely** = engineering inference/recommendation; **Unverified** = requires testing, legal review or unavailable evidence. All requirements below are proposed behavior, not claims of implemented functionality.

## 1. Product decision

Build a native macOS file utility: select or drag a file, choose a relevant operation, obtain a new result locally. No accounts, usage allowance, mandatory cloud connection or conversion billing. Optional future cloud AI uses the user's own provider account, with direct requests and explicit disclosure. Personal files do not pass through Syntax Error infrastructure.

**Likely:** SwiftUI plus AppKit and Apple frameworks best fit a lightweight Mac-only first release. Start with narrow verified format support; add independently tested engines. Do not promise “any file to any format.” A file extension is not a codec, and a supported input does not imply every output is meaningful.

**Likely:** The durable differentiator is trustworthy file handling, clear quality trade-offs and reusable workflows. Being free alone does not establish a distinctive product. Maintainability and security updates are continuing work even without server costs.

## 2. Tangerine: observed capabilities and limits

**Certain — vendor claims, not independently benchmarked:** Tangerine advertises 275 conversion options, 26 tools and six file actions, processed locally. Its workflow uses Shift for conversions, Command for tools and Control for actions while dragging. The key can be released while the wheel remains visible. The website lists Apple silicon and macOS 13+. File actions include AirDrop, Float, Copy, Move, Copy Path and Terminal. Supported families cover raster images, media, PDFs, documents, slides, spreadsheets, EPUB, subtitles and archives. Some formats are input-only, including SVG and RAR. [S1]

**Certain — supplied screenshot text:** Settings expose remappable drag modifiers, appearance options, login launch, sound/haptics, float behavior, terminal selection, per-format settings, metadata preservation and a directional compatibility matrix. The JPG panel exposes compression and image-size controls. Screenshot OCR is adequate for these labels, not for reconstructing every compatibility checkmark.

**Unverified:** The 20-item limit is the user's report, not a pricing claim independently confirmed in this research. The full 26-tool inventory and current purchase price were not independently verified. The website is an interactive simulation, not evidence that the installed native app behaves identically. [S1]

**Certain — store listing:** Tool categories include photo adjustments/annotation/redaction, media trimming and splitting, audio normalization and bleeping, PDF organization, metadata editing and QR reading. [S2] The words in the user's initial description may refer to “Annotate” and “Redact”; do not invent tools called “Anonymous” or “Radiate.”

**Unverified:** Tangerine's internal code, dependencies, licenses for bundled components, permission architecture and security posture were not inspected. Local processing is a vendor privacy claim, not a third-party audit. No binary extraction, decompilation or copying of its paid features/assets was performed.

## 3. How a similar app can work

**Likely — proposed architecture, not Tangerine internals:** AppKit handles drag destinations and a floating panel. SwiftUI renders settings, queues and previews. A capability registry maps detected types to valid operations. ImageIO/Core Graphics handle still images; AVFoundation handles a limited set of media combinations; PDFKit handles basic PDF operations; Vision supplies supported on-device recognition. Optional helper processes extend formats. [S3–S5]

The hardest interaction is detecting another application's active drag and presenting a destination without stealing the drag. Run a dedicated technical spike before promising system-wide modifier behavior. Ordinary drop support is available through NSDraggingDestination; it does not by itself establish reliable global drag detection. Test Finder, Desktop, Mail attachments and browser downloads separately. Use public APIs, document actual permissions, and retain a menu-bar/window drop fallback. Never collect ordinary typed text or copy unrelated clipboard contents. [S3]

## 4. Users and jobs

- Personal Mac users: convert HEIC photos, prepare email attachments, resize screenshots, combine PDFs.
- Designers and creators: preserve transparency, select dimensions, understand color/quality changes.
- Privacy-conscious users: remove location metadata, inspect sensitive fields and redact deliberately.
- Contributors: add one engine or operation through documented code and fixtures.

Businesses may use and sell the GPL-licensed software subject to its terms. Ordinary converted user files do not become GPL merely because the utility processed them. Private modifications need not be published; distribution triggers applicable source obligations.

## 5. Scope and milestones

| Milestone | Deliverable | Exit evidence |
|---|---|---|
| M0: foundation | PRD, license decision record, clean native conversion prototype | Build + converter tests; explicit limitations |
| M1: interaction spike | Menu-bar drop, global drag experiment, accessible command palette | Drag matrix on supported macOS; permission denial fallback; no accidental file operations |
| M2: private alpha | Images, safe output transaction, queue and basic PDF operations | Fixture matrix, sandbox/worker checks, source-byte invariance |
| M3: expanded beta | Selected media formats, reviewed helpers, presets | Exact engine versions, licenses, malformed input and cancellation testing |
| M4: public release | Final brand/license, contributors process, signed/notarized build | Legal checklist, security gates, installation and update verification |
| Later | Office engines, archives, local AI, optional BYOK | Each module separately meets format, privacy and license gates |

These are ordered gates, not promised delivery dates. The global drag spike, office fidelity and licensing may alter the schedule.

## 6. Functional requirements

### Entry and operation selection

FR1. Accept files through a window, file picker and later menu-bar destination. Global modifier activation follows only after M1 validation.

FR2. Offer an original command palette design with Convert / Tools / Actions. A radial mode is optional. Keyboard-only users can select files, search operations, confirm and cancel; support VoiceOver and Reduce Motion. Avoid visual copying of Tangerine's assets and layout.

FR3. Show only meaningful operations for the selected content and installed engines. Mixed batches display eligible count and explicit per-file skips. Never silently convert a folder or recursively scan it. File promises/iCloud placeholders require progress and a clear download dependency.

FR4. Choose output location and relevant quality controls before a lossy operation. Keep original files by default. Provide success, failure and cancellation per item; a failed item does not invalidate successful independent results.

### Conversion coverage

| Family | Initial product scope | Later expansion / caveat |
|---|---|---|
| Images | JPEG, PNG, TIFF; HEIC where capability tested | WebP/AVIF via reviewed codecs; SVG rasterization only with external resources disabled |
| PDF | Merge, split, reorder, extract text, page images | OCR after language tests; PDF-to-DOCX is reconstruction, not exact round-trip |
| Video | Tested MP4/MOV codec pairs using AVFoundation | FFmpeg pack for MKV/WebM/legacy formats after build/license review |
| Audio | Tested WAV/AIFF/M4A paths | FFmpeg for MP3/FLAC/Opus/OGG and normalization |
| Text/subtitles | TXT; validated SRT↔VTT | Respect encodings, timing and overlapping cues; no regex-only general parser |
| Documents | Deferred from first alpha | Pandoc for structural formats; LibreOffice for office layouts |
| Spreadsheets/slides | Deferred | CSV/TSV escaping, formula injection policy, locale, formulas and layout must be specified |
| Archives | Deferred | ZIP/TAR through bounded extraction; no RAR creation promise |

FR5. Maintain a generated directional compatibility matrix from tested capabilities. Distinguish read, write, lossy, metadata, multipage and animation support. Never infer a successful conversion from exit code alone: reopen and validate structure.

FR6. Before a destructive fidelity change, explain loss: transparency, animation, HDR, bit depth, color gamut, metadata, searchable PDF text, spreadsheet formulas or document formatting. Preserve originals and name the trade-off. An image cannot become an editable vector merely by changing its extension.

FR7. Image tools: resize, crop, rotate and metadata view/removal first. Add compression preview, annotations and irreversible pixel redaction after tests. Solid redaction preferred for sensitive text; blur is not a guarantee of privacy. No “anonymous” guarantee.

FR8. File actions: Reveal and Copy Path first; later Copy/Move with overwrite policy, AirDrop via system UI and floating shelf. Move must be explicit and recoverable. Opening a terminal must pass structured arguments; never interpolate filenames into a shell command.

FR9. Conversions should not “compress” a file into a larger output without explaining that outcome. Target-size operations report achieved size and quality limitations rather than guaranteeing an impossible target.

### Improvements worth prioritizing

**Likely:** Repeatable recipes (resize → omit location → convert), metadata before/after comparison, a visible fidelity-loss summary, per-file batch recovery and keyboard access create clearer value than inflating conversion counts. Introduce presets only after operations are stable. Local history should be opt-in, clearable and avoid retaining document contents.

## 7. Reuse assessment

These are candidate projects, not installed or audited dependencies. Exact pinned revisions and all transitive licenses must be reviewed before adoption.

| Project | Evidence / license | Proposed use and decision |
|---|---|---|
| [Convierto](https://github.com/nuance-dev/convierto) | Certain: MIT; native SwiftUI converter [S6] | Compare UX and native media paths; inspect code before selective reuse |
| [Verto](https://github.com/aalemoro/Verto) | Certain: MIT; native image/media/PDF architecture [S7] | Strong engine reference; no assumption its advertised results are verified |
| [DropConvert](https://github.com/mpotter2002/DropConvert) | Certain: menu-bar converter; website claims MIT [S8] | Useful interaction reference; verify actual LICENSE at adopted revision before copying |
| [Clop](https://github.com/FuzzyIdeas/Clop) | Certain: GPLv3; public repo says development moved private [S9] | GPLv3-compatible reuse is now possible; preserve upstream notices and review source quality |
| [Caesium](https://github.com/Lymphatus/caesium-image-compressor) | Certain: GPLv3 image compressor [S10] | Benchmark/reference; GPL-compatible reuse requires notices and source review |
| [FFmpeg](https://ffmpeg.org/legal.html) | Certain: LGPL baseline; optional GPL/nonfree build implications [S11] | Later media helper with exact build flags, source and notices; separation alone is not legal clearance |
| [libvips](https://github.com/libvips/libvips) | Certain: LGPL-2.1-or-later [S12] | Optional memory-efficient images if native path proves insufficient |
| [qpdf](https://github.com/qpdf/qpdf) | Certain: Apache-2.0 [S13] | Candidate PDF structural operations; not a semantic redaction engine |
| [oxipng](https://github.com/oxipng/oxipng) | Certain: MIT [S14] | Candidate lossless PNG optimization |
| [ExifTool](https://github.com/exiftool/exiftool) | Certain: README offers Perl Artistic or GPL terms [S15] | Metadata coverage; review selected license and runtime distribution |
| [Pandoc](https://pandoc.org/) | Certain: GPL [S16] | Optional document helper, subject to distribution/combination review |
| [LibreOffice](https://www.libreoffice.org/licenses/) | Certain: licensing page documents project terms [S17] | Optional large office engine; inspect MPL/LGPL and bundled components at pinned version |
| [libarchive](https://github.com/libarchive/libarchive) | Candidate archive engine [S18] | Review exact BSD-family and dependency notices; extraction safety is still our responsibility |
| [rembg](https://github.com/danielgatis/rembg) | Candidate local background removal [S19] | Defer heavy Python runtime; model weights have separate rights and download costs |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Candidate update framework [S20] | Signed updates after first release; verify exact license and update configuration |

**Certain — newly verified primary repository:** [Satsuma](https://github.com/plyght/satsuma) is an MIT-licensed implementation explicitly inspired by the Tangerine workflow. Its README claims 188 conversions, 25 tools, native-first processing and optional FFmpeg/unar. It targets macOS 26+ and uses the author's Brisk build tool. Its LICENSE was read; it permits reuse with preservation of copyright/license notices. No Satsuma code has yet been copied into this prototype.

**Likely — updated build decision:** Evaluate Satsuma first as the closest potential foundation, before building feature parity from scratch. Retain our small native image slice as a baseline. A fork should preserve Satsuma's MIT notice, clearly distinguish new GPL-covered work and retain notices for dependencies. MIT permission does not prove provenance of every asset or dependency; inspect the full tree before adoption.

**Certain — limited static inspection, not an audit:** DragMonitor.swift polls at 30 Hz idle / 60 Hz during dragging and installs global mouse monitors. Debug output can include full paths. Shell.swift reads complete stdout/stderr into memory, with no explicit output cap or deadline visible in that runner. ArchiveEngine.swift delegates extraction to external tools without application-level expansion limits visible in that file. These require performance/privacy/resource-limit review; they are not demonstrated exploits. No path-traversal exploit or shell injection was established. The gzip branch uses quoted positional shell parameters, not raw filename interpolation.

Inspected file object SHAs: README 9dc53ec5bf20ffd85cb78676b177d45beb14f6bc; LICENSE 16d4ecaf848bbeb92b672ef6f93de10c33abedcc; Shell 7562b2af67dd5eaab37bdc574961c117b83b3591; ArchiveEngine ce354a82004175db780a0fbaba00f6c7218d5113; DragMonitor cea6d87e5d1b57eef71526c015f4bb4ba12837fc. These identify inspected files, not a pinned reproducible release. Full dependency review, build and interactive testing remain necessary.

## 8. Security design and release gates

Assets: original files, outputs, metadata, credentials and OS permissions. Adversaries: malformed files, malicious archives/documents, substituted helper binaries, compromised updates and hostile extensions. “Offline” removes an upload path but does not make parsers safe.

SR1. Use an App Sandbox where feasible. Convert in a separate constrained worker with no network entitlement; grant only user-selected input/output access. Prove entitlements and resource enforcement in packaged builds. If global interaction needs different privileges, isolate it and document the trade-off.

SR2. Stable input snapshots or verified file descriptors prevent input replacement during processing. Reject unexpected devices, pipes and symlink escapes. Bound input bytes, decoded pixels, pages, duration, memory, output bytes and execution time before expensive work where possible.

SR3. Write into an exclusive private temporary location on the destination filesystem; validate the output; publish with no-replace atomic semantics; clean failed/cancelled jobs. Never follow a pre-existing destination symlink or overwrite a source. Test full disk and permission loss.

SR4. Launch helpers by verified absolute path and argument arrays, with restricted environment, working directory, protocol access, timeouts and child-process termination. No shell strings, arbitrary filters, downloadable executable plugins or execution of document macros. Bound stderr/stdout capture to avoid memory exhaustion and redact private paths.

SR5. Archive extraction rejects absolute paths, traversal, escaping links, device entries and excessive expansion/nesting. Do not disable quarantine or automatically execute extracted content.

SR6. Documents/HTML/SVG must not fetch remote resources or local arbitrary files. Disable macros and unsupported external references. Reject encrypted inputs without clear user-supplied passwords; do not save passwords to logs/history.

SR7. Metadata removal must describe which fields and containers were inspected. PDF redaction requires removing underlying text, annotations, attachments and stale incremental revisions, then residual-content tests. Painting a rectangle alone is insufficient. Automatic detectors require human review and disclose missed detections.

SR8. No telemetry in initial product. Crash reports opt-in and scrubbed. No contents or API keys in diagnostics. Dependencies pinned; notices/SBOM and hashes accompany releases; review upstream vulnerabilities and rebuild affected engines.

SR9. Protect release credentials, use reviewed CI changes and signed/notarized distributions. Notarization is malware screening and distribution trust, not a correctness audit. [S21] Enable private vulnerability reporting before public availability.

## 9. AI and costs

**Likely:** No AI is needed for core conversion. Vision can support local recognition/foreground masking on supported macOS versions. Local model features may require OS capabilities or model downloads, but not necessarily paid APIs. [S4]

Future cloud AI is separately disabled by default: the user selects provider and model, stores their key in macOS Keychain, sees what data leaves the device, and confirms the request. Send directly to the provider. Never proxy keys or files through a Syntax Error service. Provider charges, retention and training policies must be explained per integration, not generalized. No cloud fallback without permission. User-controlled endpoints require a clear warning about credential destination.

Free use does not mean zero operating cost for the maintainer: signing/distribution, CI, support and security maintenance remain. No current price estimate is asserted. Donations can be explored but must not silently introduce a use quota.

## 10. License, ownership and naming

**Certain:** OSI open source permits commercial use and redistribution; “no sale” terms are source available, not OSI open source. MIT permits sale; GPL also permits sale and adds source/license obligations. Public GitHub visibility is not itself a suitable reuse license. [L1–L4]

**Selected policy: GPL-3.0-only.** People may use, inspect, modify, redistribute and sell the software. Distributing covered modified versions requires GPL licensing and corresponding source under the applicable license provisions. It does not require publishing every private change or contributing changes back to our repository. GPL alone does not impose AGPL's network-service source requirement. Users can sell ordinary converted files. The unmodified license text is included in LICENSE; no no-sale clause is added.

**Certain:** A contributor license grant and copyright assignment are different. [L6] Syntax Error retains rights in its own original material; contributors keep ownership of their contributions unless they sign an assignment. GPL contributions provide the project reuse rights without requiring transfer. Third-party engines remain their owners' property. A company copyright notice alone does not prove chain of title. Confirm employment/contractor rights and jurisdiction-specific treatment of AI-assisted work before making exclusive ownership claims. A valid GPL grant cannot simply be withdrawn from compliant existing recipients. [L3]

**Likely:** GPLv3 is a closer match than MIT to the owner's revised desire for community access: both permit sale, but GPL protects recipients' source and modification rights for distributed covered derivatives. It is not a mechanism to force contributions into our repository.

**Likely:** “Open Tangerine” risks suggesting affiliation. Use it privately as the requested working name; select and clear a distinctive release name/logo. General ideas and methods differ from protected expression, but that is not blanket clearance for similar branding, designs, patents or copied code. The cited US copyright/trademark guidance illustrates the issues; it does not settle Indian or worldwide rights. [L7–L8]

## 11. Contribution and release operations

Host the eventual repository under the company's verified GitHub organization/account. Enable protected main branch, required tests and private security reporting. Give contributors a fork → branch → pull request path; a maintainer reviews and merges. New engines require a source/license record, fixture and safe invocation. Keep release credentials restricted.

Before launch: final LICENSE, README with honest status and installation instructions, CONTRIBUTING with inbound rights, SECURITY with private channel, issue templates, code of conduct, changelog, third-party notices and CI. Use tagged releases and checksums; distinguish development artifacts from signed releases. Publish a roadmap and small starter issues. Copyleft affects compatibility and distribution choices; it does not prohibit commercial forks. Prefer direct notarized distribution first and review any future App Store terms for GPL compatibility.

## 12. Acceptance tests and performance goals

- Originals remain byte-identical after success, cancellation and failure.
- Existing filenames/symlinks never cause overwrite; names with spaces, Unicode, newlines and leading hyphens are safe.
- Image fixtures cover EXIF orientation, alpha, ICC/HDR policy, malformed files, huge dimensions, animated/multipage rejection or preservation.
- Media tests cover actual codec/container pairs, durations, audio channels and cancellation.
- PDF tests cover rotated/multipage files, encryption, embedded attachments and hidden text.
- Mixed batches show per-file results; cancel stops pending work and cleans unfinished output.
- Core operations work without network; instrument packaged worker network attempts.
- Keyboard, VoiceOver, permission denial, multi-monitor and screen-edge drag scenarios pass.
- On an 8 GB Apple silicon Mac, default to one heavy job; measure peak memory and UI responsiveness. Proposed targets: palette response under 150 ms after activation, idle CPU under 1%, idle memory under 100 MB. These are unmeasured goals, not current claims.

## 13. Initial implementation status

The accompanying prototype contains a Swift package, a native drop/picker window, an ImageIO conversion core and focused tests. Outputs are PNG/JPEG/TIFF, metadata-omitting, 8-bit sRGB; JPEG uses a white background. It uses exclusive new output names. The UI caps batches at 50; core limits inputs to 100 MB / 40 megapixels and rejects multiframe inputs and input symlinks. It has no AI, helper downloads or network code.

Not yet implemented: global drag palette, menu-bar entry, broad format support, metadata preservation, sandboxed worker, transactional output cleanup and notarized distribution. This is a development slice, not the promised complete product. See BUILD-STATUS.md for actual checks and blockers. GPLv3 has been applied locally. The GitHub connector identified the account but exposes no repository-creation operation; GitHub CLI authentication failed. No public repository or release has been created.

## Sources

Research accessed 18 October 2026. Project READMEs describe their authors' claims, not independent security or quality validation.

S1 https://tangerineformac.com/ and https://tangerineformac.com/privacy
S2 https://apps.apple.com/mx/app/tangerine-file-converter/id6813034065?mt=12
S3 https://developer.apple.com/documentation/appkit/nsdraggingdestination
S4 https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
S5 https://github.com/aalemoro/Verto (architecture example)
S6 https://github.com/nuance-dev/convierto
S7 https://github.com/aalemoro/Verto
S8 https://dropconvert.app/ and https://github.com/mpotter2002/DropConvert
S9 https://github.com/FuzzyIdeas/Clop
S10 https://github.com/Lymphatus/caesium-image-compressor
S11 https://ffmpeg.org/legal.html
S12 https://github.com/libvips/libvips
S13 https://github.com/qpdf/qpdf
S14 https://github.com/oxipng/oxipng
S15 https://github.com/exiftool/exiftool
S16 https://pandoc.org/
S17 https://www.libreoffice.org/licenses/
S18 https://github.com/libarchive/libarchive
S19 https://github.com/danielgatis/rembg
S20 https://github.com/sparkle-project/Sparkle
S21 https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
L1 https://opensource.org/osd
L2 https://choosealicense.com/licenses/mit/
L3 https://www.gnu.org/licenses/gpl-faq.en.html
L4 https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
L5 https://polyformproject.org/licenses/noncommercial/1.0.0
L6 https://www.apache.org/licenses/contributor-agreements.html
L7 https://www.copyright.gov/circs/circ33.pdf
L8 https://www.uspto.gov/trademarks/search/likelihood-confusion
