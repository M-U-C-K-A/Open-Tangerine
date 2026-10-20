import CoreImage
import SwiftUI

/// Blur & redact: faces are found and covered for you, as areas you can move, resize,
/// restyle or delete; draw more areas anywhere. What you see is what is saved.
@MainActor
struct RedactImageToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @State private var rects: [RectangleOverlay] = []
    @State private var selected: UUID?
    @State private var styles: [UUID: RedactionStyle] = [:]
    @State private var strengths: [UUID: Double] = [:]
    @State private var defaultStrength = Redaction.defaultStrength
    /// Faces as Vision found them (image pixels, top-left), so the margin can be changed later.
    @State private var faces: [UUID: CGRect] = [:]
    @State private var defaultStyle: RedactionStyle = .blur
    @State private var color = Color.black
    @State private var margin: Double = 0.3
    @State private var detecting = false
    @State private var detectionNote: String?
    @StateObject private var render = LatestRenderer<CGImage>()

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: 2000))
    }

    private var batch: Bool { session.files.count > 1 }

    private var redactions: [Redaction] {
        rects.map { overlay in
            var r = Redaction(rect: overlay.rect)
            r.style = styles[overlay.id] ?? defaultStyle
            r.strength = strengths[overlay.id] ?? defaultStrength
            r.color = color.nsColor.cgColor
            return r
        }
    }

    var body: some View {
        ToolShell(session: session, saveTitle: batch ? "Apply to \(session.files.count) images" : "Save copy", saveEnabled: !rects.isEmpty || batch, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let preview = document.preview {
                    ZoomableView {
                        RectangleEditorCanvas(image: render.output.map(ImageOps.nsImage) ?? preview, imageSize: document.size, rectangles: $rects, selected: $selected, allowMultiple: true, outlinesOnly: true)
                            .padding(12)
                    }
                } else {
                    LoadingOrError(error: document.error)
                }
            }
        } sidebar: {
            SidebarSection(title: "Faces") {
                HStack {
                    Button(detecting ? "Looking…" : "Find faces", action: findFaces)
                        .disabled(detecting || document.preview == nil)
                    Spacer()
                    Text(faceCount == 0 ? "" : "\(faceCount) found").font(.caption).foregroundStyle(.secondary)
                }
                LabeledSlider(title: "Margin around faces", value: $margin, range: 0...0.8) { String(format: "%.0f%%", $0 * 100) }
                Text(detectionNote ?? "Faces are covered as soon as the photo opens. Move or resize their areas, delete the ones you want to keep, or draw new ones.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Style") {
                Picker("", selection: styleBinding) {
                    Text("Blur").tag(RedactionStyle.blur)
                    Text("Pixelate").tag(RedactionStyle.pixelate)
                    Text("Box").tag(RedactionStyle.solid)
                }
                .pickerStyle(.segmented).labelsHidden()
                if styleBinding.wrappedValue == .solid {
                    ColorSwatchPicker(title: "Color", color: $color)
                } else {
                    LabeledSlider(title: styleBinding.wrappedValue == .blur ? "Blur strength" : "Pixel size", value: strengthBinding, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                }
                Text(selected == nil ? "Applies to every area without its own style." : "Applies to the selected area. Click outside the areas to change them all.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Areas (\(rects.count))") {
                if rects.isEmpty {
                    Text("Drag on the photo to cover an area. Drag an area to move it, its corners to resize it; ⌫ deletes the selected one.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(rects) { overlay in
                    HStack {
                        Circle().fill(overlay.id == selected ? Theme.accent : Color.secondary).frame(width: 8, height: 8)
                        Text(faces[overlay.id] == nil ? "Area \(overlay.label)" : "Face \(overlay.label)").font(.callout)
                        Text((styles[overlay.id] ?? defaultStyle).title).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { remove(overlay.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = overlay.id }
                }
                if !rects.isEmpty {
                    Button("Remove all") { rects.removeAll(); styles.removeAll(); strengths.removeAll(); faces.removeAll(); selected = nil }.controlSize(.small)
                }
            }
            if batch {
                SidebarSection(title: "Batch") {
                    Text("Each of the \(session.files.count) images gets its own faces found and covered. Areas you draw here go at the same place on every image.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: document.preview) { findFaces() }
        .onAppear { if document.preview != nil, rects.isEmpty { findFaces() } }
        .onChange(of: rects) { relabel(); scheduleRender() }
        .onChange(of: styles) { scheduleRender() }
        .onChange(of: strengths) { scheduleRender() }
        .onChange(of: defaultStrength) { scheduleRender() }
        .onChange(of: color) { scheduleRender() }
        .onChange(of: defaultStyle) { scheduleRender() }
        .onChange(of: margin) { applyMargin() }
        .onDeleteCommand { if let selected { remove(selected) } }
    }

    private var faceCount: Int { rects.filter { faces[$0.id] != nil }.count }

    private var styleBinding: Binding<RedactionStyle> {
        Binding(
            get: { selected.flatMap { styles[$0] } ?? defaultStyle },
            set: { new in
                if let selected { styles[selected] = new } else { defaultStyle = new }
                scheduleRender()
            }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { selected.flatMap { strengths[$0] } ?? defaultStrength },
            set: { new in if let selected { strengths[selected] = new } else { defaultStrength = new } }
        )
    }

    /// Faces in image pixels, origin top-left, as the areas use.
    private func findFaces() {
        guard !detecting, let preview = document.preview, let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil), document.size.width > 0 else { return }
        detecting = true
        let scale = document.size.width / CGFloat(cg.width)
        let height = CGFloat(cg.height)
        Task {
            let found = (try? await Task.detached(priority: .userInitiated) { try FaceBlur.faces(in: CIImage(cgImage: cg)) }.value) ?? []
            detecting = false
            let topLeft = found.map { CGRect(x: $0.minX * scale, y: (height - $0.maxY) * scale, width: $0.width * scale, height: $0.height * scale) }
            // A new search replaces the faces found before, and keeps hand-drawn areas.
            let previous = Set(faces.keys)
            rects.removeAll { previous.contains($0.id) }
            faces.removeAll()
            for face in topLeft {
                let id = UUID()
                faces[id] = face
                rects.append(RectangleOverlay(id: id, rect: FaceBlur.covered(face, padding: margin, in: CGRect(origin: .zero, size: document.size)), color: .orange, label: ""))
            }
            detectionNote = found.isEmpty ? "No faces found. Draw areas by hand on the photo." : nil
            relabel()
        }
    }

    private func applyMargin() {
        let bounds = CGRect(origin: .zero, size: document.size)
        for index in rects.indices {
            if let face = faces[rects[index].id] {
                rects[index].rect = FaceBlur.covered(face, padding: margin, in: bounds)
            }
        }
    }

    private func remove(_ id: UUID) {
        rects.removeAll { $0.id == id }
        styles.removeValue(forKey: id)
        strengths.removeValue(forKey: id)
        faces.removeValue(forKey: id)
        if selected == id { selected = nil }
    }

    private func relabel() {
        var faceNumber = 0, areaNumber = 0
        for index in rects.indices {
            let label: String
            if faces[rects[index].id] != nil { faceNumber += 1; label = "\(faceNumber)" } else { areaNumber += 1; label = "\(areaNumber)" }
            if rects[index].label != label { rects[index].label = label }
        }
    }

    /// The effect is always shown under the outlines, at preview size, one render at a time.
    private func scheduleRender() {
        guard let preview = document.preview, let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil), document.size.width > 0 else { return }
        let scale = CGFloat(cg.width) / document.size.width
        let scaled = redactions.map { r -> Redaction in
            var copy = r
            copy.rect = r.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
            return copy
        }
        render.submit {
            ImageToolSupport.cgImage(ImageOps.redact(CIImage(cgImage: cg), redactions: scaled))
        }
    }

    private func save() {
        let size = document.size
        let style = defaultStyle, margin = margin
        let strength = defaultStrength
        let manual = rects.filter { faces[$0.id] == nil }.map { overlay -> (CGRect, RedactionStyle, Double) in
            // Hand-drawn areas as fractions, to land at the same place on every image.
            (CGRect(x: overlay.rect.minX / size.width, y: overlay.rect.minY / size.height, width: overlay.rect.width / size.width, height: overlay.rect.height / size.height), styles[overlay.id] ?? style, strengths[overlay.id] ?? strength)
        }
        let edited = redactions
        let color = color.nsColor.cgColor
        if !batch, let original = document.original {
            ImageToolSupport.save(session, suffix: "redacted") {
                guard let image = ImageToolSupport.cgImage(ImageOps.redact(CIImage(cgImage: original), redactions: edited)) else { throw OpenTangerineError.encodeFailed("Rendering failed") }
                return image
            }
            return
        }
        ImageToolSupport.saveEach(session, suffix: "redacted", title: session.tool.progressTitle, detail: "\(session.files.count) images") { _, image in
            let input = CIImage(cgImage: image)
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let height = CGFloat(image.height)
            var areas = ((try? FaceBlur.faces(in: input)) ?? []).map { face -> Redaction in
                var r = Redaction(rect: FaceBlur.covered(CGRect(x: face.minX, y: height - face.maxY, width: face.width, height: face.height), padding: margin, in: bounds), style: style, strength: strength)
                r.color = color
                return r
            }
            areas += manual.map { fraction, areaStyle, areaStrength in
                var r = Redaction(rect: CGRect(x: fraction.minX * bounds.width, y: fraction.minY * bounds.height, width: fraction.width * bounds.width, height: fraction.height * bounds.height), style: areaStyle, strength: areaStrength)
                r.color = color
                return r
            }
            guard let output = ImageToolSupport.cgImage(ImageOps.redact(input, redactions: areas)) else { throw OpenTangerineError.encodeFailed("Rendering failed") }
            return output
        }
    }
}
