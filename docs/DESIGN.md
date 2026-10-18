# Visual design · 0.1.1

Settings now uses an 820 × 620 native window with a persistent sidebar, warm orange selected state, clearer typographic hierarchy, contextual headers and a small file-orbit illustration. The menu-bar symbol is 22 points in a 32-point item, rendered as a template for light/dark menu bars.

Motion communicates changes: sidebar selection follows a short spring; content fades and moves nine points; the header changes its symbol and turns its dotted orbit on tab selection. The illustration has a single entrance, not a permanent animation loop. The conversion wheel fades in over 160 ms without moving its drop targets.

Reduce Motion replaces spatial motion with fades or immediate changes. Reduce Transparency makes the sidebar opaque. Standard native controls, semantic sidebar labels and keyboard buttons remain intact.

Guidance consulted: [thienqo/ios-skills — swiftui-animation](https://github.com/thienqo/ios-skills/blob/main/skills/swiftui-animation/SKILL.md). Read as design guidance; no third-party installation scripts or animation dependencies were executed or incorporated.

Manual checks: open all settings tabs, move quickly between tabs, check selected-state visibility, confirm controls and scrolling remain usable, then repeat with macOS Reduce Motion. Check light/dark appearance and menu-bar legibility. No frame-rate performance claim is made without profiling.

Validation: Swift compilation and ad-hoc code-signature verification passed. Automated launch was blocked during macOS application registration (SIGABRT in _RegisterApplication, before NSApplication initialization). Visual interaction, normal/reduced-motion animation and dark/light review remain unverified for 0.1.1; use the packaged build for manual checking.
