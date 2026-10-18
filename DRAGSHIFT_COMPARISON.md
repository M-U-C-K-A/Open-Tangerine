# DragShift comparison — 18 October 2026

Reviewed the available Python/PySide6 source at https://github.com/llamaboi55/DragShift, including radial.py, glass.py, liquid.py, toasts.py, settings.py, convert.py and tools.py. This is a source review, not a runtime certification of their binaries. The repository being similar does not establish that it copied Open Tangerine.

| Area | DragShift source | Open Tangerine |
| --- | --- | --- |
| Glass and motion | Screenshot-based refraction, animated radial hover/entrance | Native macOS glass wheel; 0.1.8 adds spring entrance/hover and an optional glass notch. Pure black remains the default, with existing notch expansion retained. No Screen Recording permission added. |
| Completed results | Open, reveal, size comparison and Undo toast | 0.1.8 adds Open and Show in Finder, eight-second timeout paused on hover. Size comparison and Undo are not added. |
| Compression | Target size and before/after compression preview | Target-size compression already existed; no new compression preview added. |
| Image editor | Hold-to-compare, automatic adjustments, annotation arrows/boxes/text/numbered steps | Hold-to-compare and manual adjustments already existed; annotation and automatic enhancement remain gaps. |
| Metadata | GPS-only removal and map link | Existing editable metadata and all/sensitive removal; GPS-only/map link remain gaps. |
| Documents | PDF to DOCX with text and embedded images; DOCX to PDF/TXT | PDF to DOCX already exists, with documented layout limits. DOCX input conversion remains unavailable. |
| Image formats | Still-image GIF and ICO output | Current image targets do not include ICO or still-image GIF. Video-to-GIF is a separate existing operation. |
| Preferences/platforms | Configurable trigger, output subfolder; Windows/Linux/macOS builds | Fixed Shift/Command/Control workflows; beside-original/Downloads/Desktop outputs. Current trial is Apple silicon, macOS 26+. |
| Broader toolbox | Primarily image/PDF/document tools in reviewed source | Existing audio/video operations, subtitles, batch conversion, file actions and checksums remain available. |

0.1.8 deliberately implements the visual and result-access improvements above, not full feature parity. Its SwiftUI code is native, rather than importing the Python renderer. MIT attribution is preserved in THIRD_PARTY_NOTICES.md. DragShift's Undo implementation includes a permanent-delete fallback; that behavior was not imported.

Validation: the eight native regression suites cover image conversion, HEIC/WebP, four-file batch output naming and failure isolation, documents, image tools and media. Website consent/privacy, download classification, pagination, version checks and animation tests run separately. Platform support and document fidelity limits remain as documented in README.
