import AppKit
import SwiftUI

/// Color palette: the picture's main colors, and an eyedropper for any pixel. Clicking a
/// color copies it, in HEX, RGB, HSL or as a SwiftUI literal.
@MainActor
struct ColorPaletteToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @AppStorage("palette.count") private var count = 6
    @AppStorage("palette.notation") private var notation: PaletteColor.Notation = .hex
    @State private var grid: PixelGrid?
    @State private var palette: [PaletteColor] = []
    @State private var picked: [PaletteColor] = []
    @State private var hover: CGPoint?
    @State private var copied: String?

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: 2000))
    }

    var body: some View {
        ToolShell(session: session, saveTitle: "Save palette", saveEnabled: !palette.isEmpty || !picked.isEmpty, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let preview = document.preview {
                    GeometryReader { proxy in
                        let fit = FitGeometry(container: proxy.size, image: preview.size)
                        ZStack(alignment: .topLeading) {
                            Image(nsImage: preview)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: fit.displayRect.width, height: fit.displayRect.height)
                                .offset(x: fit.displayRect.minX, y: fit.displayRect.minY)
                            if let hover, fit.displayRect.contains(hover) {
                                loupe(at: hover, in: fit.displayRect, container: proxy.size)
                            }
                        }
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let point) = phase { hover = point } else { hover = nil }
                        }
                        .onTapGesture { point in
                            guard fit.displayRect.contains(point), let color = color(at: point, in: fit.displayRect) else { return }
                            if !picked.contains(color) { picked.insert(color, at: 0) }
                            copy(color.text(notation))
                        }
                        .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
                    }
                    .padding(16)
                } else {
                    LoadingOrError(error: document.error)
                }
                if let copied {
                    VStack {
                        Spacer()
                        Text("Copied \(copied)")
                            .font(.callout.monospaced())
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.65), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(14)
                    }
                    .transition(.opacity)
                }
            }
        } sidebar: {
            SidebarSection(title: "Palette") {
                Stepper("\(count) colors", value: $count, in: 3...12)
                swatches(palette)
                Text("The picture's main colors, the most present first. Click one to copy it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Eyedropper (\(picked.count))") {
                if picked.isEmpty {
                    Text("Click anywhere on the picture to pick that pixel's color; it is copied too.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    swatches(picked)
                    Button("Clear") { picked.removeAll() }.controlSize(.small)
                }
                Button("Pick from the Screen…", action: pickFromScreen).controlSize(.small)
            }
            SidebarSection(title: "Copy as") {
                Picker("", selection: $notation) {
                    ForEach(PaletteColor.Notation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack {
                    Button("Copy all") { copy(ColorPalette.text(picked + palette, notation: notation), label: "\(picked.count + palette.count) colors") }
                    Button("Copy as CSS") { copy(ColorPalette.text(picked + palette, notation: notation, css: true), label: "CSS variables") }
                }
                .controlSize(.small)
                .disabled(palette.isEmpty && picked.isEmpty)
            }
        }
        .onChange(of: document.original) { analyze() }
        .onChange(of: count) { analyze() }
        .onAppear(perform: analyze)
    }

    private func swatches(_ colors: [PaletteColor]) -> some View {
        VStack(spacing: 4) {
            ForEach(colors) { color in
                Button { copy(color.text(notation)) } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: color.nsColor))
                            .frame(width: 26, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.15)))
                        Text(color.text(notation)).font(.caption.monospaced()).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        if color.share > 0 {
                            Text(color.share < 0.005 ? "<1%" : "\(Int((color.share * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy \(color.text(notation))")
            }
        }
    }

    /// A magnified square of pixels under the pointer, its centre outlined, with its code.
    private func loupe(at point: CGPoint, in rect: CGRect, container: CGSize) -> some View {
        let x = (point.x - rect.minX) / rect.width, y = (point.y - rect.minY) / rect.height
        let patch = grid?.neighborhood(atX: x, y: y, radius: 5)
        let color = grid?.color(atX: x, y: y)
        let side: CGFloat = 110
        // Beside the pointer, flipped to stay inside the window.
        let left = point.x + 24 + side > container.width ? point.x - 24 - side : point.x + 24
        let top = point.y + 24 + side + 26 > container.height ? point.y - 24 - side - 26 : point.y + 24
        return VStack(spacing: 4) {
            ZStack {
                if let patch {
                    Image(nsImage: ImageOps.nsImage(patch)).resizable().interpolation(.none)
                }
                Rectangle().strokeBorder(.white, lineWidth: 1.5).frame(width: side / 11 + 2, height: side / 11 + 2)
                Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 0.5).frame(width: side / 11 + 4, height: side / 11 + 4)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.8), lineWidth: 2))
            .shadow(radius: 6)
            Text(color?.text(notation == .swiftUI ? .hex : notation) ?? "transparent")
                .font(.caption.monospaced())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
        }
        .offset(x: left, y: top)
        .allowsHitTesting(false)
    }

    private func color(at point: CGPoint, in rect: CGRect) -> PaletteColor? {
        grid?.color(atX: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }

    private func analyze() {
        guard let original = document.original else { return }
        let count = count
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (PixelGrid?, [PaletteColor]) in
                let grid = PixelGrid(original)
                return (grid, grid?.palette(count: count) ?? [])
            }.value
            grid = result.0
            palette = result.1
        }
    }

    private func copy(_ text: String, label: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copied = label ?? text }
        let shown = copied
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copied == shown { withAnimation { copied = nil } }
        }
    }

    private func pickFromScreen() {
        ScreenColorPicker.pick { color in
            if !picked.contains(color) { picked.insert(color, at: 0) }
            copy(color.text(notation))
        }
    }

    private func save() {
        let colors = picked + palette
        let notation = notation
        ImageToolSupport.save(session, suffix: "palette", format: .png, title: "Saving palette") {
            guard let image = ColorPalette.image(colors, notation: notation) else { throw OpenTangerineError.encodeFailed("the palette") }
            return image
        }
    }
}

/// The macOS eyedropper, anywhere on the screen.
@MainActor
enum ScreenColorPicker {
    private static var sampler: NSColorSampler?

    static func pick(_ done: @escaping (PaletteColor) -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { color in
            Self.sampler = nil
            guard let color, let picked = PaletteColor(color) else { return }
            done(picked)
        }
    }

    /// From the menu bar: pick a color, copy its HEX code, and say so in the notch.
    static func pickAndCopy() {
        pick { color in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(color.hex, forType: .string)
            JobRunner.shared.run(title: "Copied \(color.hex)", detail: "\(color.text(.rgb)) · \(color.text(.hsl))", symbol: "eyedropper.halffull") { _ in [] }
        }
    }
}
