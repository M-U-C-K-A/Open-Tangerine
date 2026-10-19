import AppKit
import CoreImage
import SwiftUI

@MainActor
struct RemoveBackgroundToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @State private var softness: Double = 0
    @State private var cropToSubject = false
    @State private var showOriginal = false
    @State private var subject: Subject?
    @State private var detectionError: String?
    @State private var detecting = false
    @State private var rendered: NSImage?
    @State private var renderTask: Task<Void, Never>?
    /// The outline of the crop, normalised to the image, while "Crop to subject" is on.
    @State private var cropOutline: CGRect?

    // Refining by hand, one image at a time.
    @State private var tool: RefineTool = .wand
    @State private var keep = false
    @State private var tolerance: Double = 0.15
    @State private var brushSize: Double = 0.03
    @State private var refinements: [BackgroundRemoval.Refinement] = []
    @State private var mask: BackgroundRemoval.MaskBuffer?
    @State private var stroke: [CGPoint] = []
    @State private var strokeKeeps = false
    @State private var pointer: CGPoint?
    /// 1 fits the picture in the window; up to 12 times that, to reach small leftovers.
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1

    enum RefineTool: String, CaseIterable, Identifiable {
        case wand, brush
        var id: String { rawValue }
    }

    /// The preview image with its Vision mask and pixels, computed once; edits, softness and cropping only re-blend.
    struct Subject {
        let image: CIImage
        let mask: BackgroundRemoval.MaskBuffer
        let pixels: BackgroundRemoval.Pixels
        var size: CGSize { CGSize(width: pixels.width, height: pixels.height) }
    }

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: 1600))
    }

    /// Hand edits belong to one picture, so they are offered for a single image.
    private var refinable: Bool { session.files.count == 1 }

    private var options: BackgroundRemoval.Options {
        BackgroundRemoval.Options(softness: softness, cropToSubject: cropToSubject)
    }

    private var saveTitle: String {
        session.files.count == 1 ? "Save PNG" : "Remove from \(session.files.count) images"
    }

    var body: some View {
        ToolShell(session: session, saveTitle: saveTitle, saveEnabled: session.files.count > 1 || subject != nil, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let subject, showOriginal ? document.preview != nil : rendered != nil {
                    GeometryReader { proxy in
                        let fit = Self.fitted(subject.size, in: proxy.size)
                        let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)
                        // Zoomed in, the picture scrolls: two fingers on a trackpad, or the wheel (Shift for sideways).
                        ScrollView([.horizontal, .vertical]) {
                            canvas(size)
                                .frame(width: max(size.width + 24, proxy.size.width), height: max(size.height + 24, proxy.size.height))
                        }
                        .scrollIndicators(zoom > 1 ? .automatic : .hidden)
                        .defaultScrollAnchor(.center)
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in setZoom(zoomAtGestureStart * value.magnification) }
                                .onEnded { _ in zoomAtGestureStart = zoom }
                        )
                    }
                } else if detecting {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the subject…").foregroundStyle(.secondary)
                    }
                } else {
                    LoadingOrError(error: detectionError ?? document.error)
                }
                if subject != nil {
                    VStack {
                        HStack {
                            Spacer()
                            zoomControls
                        }
                        Spacer()
                    }
                    .padding(12)
                }
                VStack {
                    Spacer()
                    Picker("", selection: $showOriginal) {
                        Text("Before").tag(true)
                        Text("After").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(document.preview == nil)
                    // The checkerboard is dark in both appearances.
                    .environment(\.colorScheme, .dark)
                    .padding(12)
                }
            }
        } sidebar: {
            if refinable {
                SidebarSection(title: "Refine") {
                    Picker("", selection: $tool) {
                        Label("Magic wand", systemImage: "wand.and.stars").tag(RefineTool.wand)
                        Label("Brush", systemImage: "paintbrush.pointed").tag(RefineTool.brush)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Picker("", selection: $keep) {
                        Text("Remove").tag(false)
                        Text("Keep").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if tool == .wand {
                        LabeledSlider(title: "Tolerance", value: $tolerance, range: 0.02...0.6) { String(format: "%.0f%%", $0 * 100) }
                    } else {
                        LabeledSlider(title: "Brush size", value: $brushSize, range: 0.005...0.15) { String(format: "%.1f%%", $0 * 100) }
                    }
                    HStack {
                        Button("Undo", action: undo)
                            .keyboardShortcut("z", modifiers: .command)
                            .disabled(refinements.isEmpty)
                        Button("Reset", action: resetRefinements)
                            .disabled(refinements.isEmpty)
                        Spacer()
                        Text(refinements.isEmpty ? "" : "\(refinements.count) edit\(refinements.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(tool == .wand
                         ? "Click a leftover patch to remove it, or a missing part to bring it back. Similar connected colors go with it. Hold ⌥ to swap Remove and Keep."
                         : "Paint over what should go, or what should stay. Hold ⌥ to swap Remove and Keep.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Pinch or press ⌘+ to zoom in on the edges, scroll to move around, ⌘0 to fit.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            SidebarSection(title: "Edges") {
                LabeledSlider(title: "Softness", value: $softness, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                Toggle("Crop to subject", isOn: $cropToSubject)
            }
            SidebarSection(title: "Output") {
                Text(session.files.count == 1
                     ? "A transparent PNG next to the original, named “\(session.baseName) \(BackgroundRemoval.suffix).png”."
                     : "A transparent PNG next to each original, named like “\(session.baseName) \(BackgroundRemoval.suffix).png”.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Apple Vision finds the people, animals and objects in front and clears everything else, on this Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if session.files.count > 1 {
                SidebarSection(title: "Batch") {
                    Text("The same edges are applied to all \(session.files.count) images. Each one gets its own job; an image without a clear subject fails alone. Open a single image to refine it by hand.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: detectSubject)
        .onChange(of: document.preview) { detectSubject() }
        .onChange(of: softness) { scheduleRender() }
        .onChange(of: cropToSubject) { scheduleRender() }
    }

    // MARK: - Zoom

    static let zoomRange: ClosedRange<CGFloat> = 1...12

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// Zoom out, fit, zoom in; pinch works too. ⌘+, ⌘− and ⌘0 from the keyboard.
    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { setZoom(zoom / 1.5); zoomAtGestureStart = zoom } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom <= Self.zoomRange.lowerBound)
                .help("Zoom out (⌘−)")
            Button { setZoom(1); zoomAtGestureStart = 1 } label: {
                Text(zoom <= 1.001 ? "Fit" : "\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Fit the picture in the window (⌘0)")
            Button { setZoom(zoom * 1.5); zoomAtGestureStart = zoom } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoom >= Self.zoomRange.upperBound)
                .help("Zoom in (⌘+)")
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        // The checkerboard is dark in both appearances.
        .environment(\.colorScheme, .dark)
    }

    /// The picture at `size`, its crop outline and the surface that takes clicks and strokes.
    private func canvas(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if showOriginal, let preview = document.preview {
                    Image(nsImage: preview).resizable().interpolation(zoom > 2 ? .none : .high)
                } else if let rendered {
                    Image(nsImage: rendered).resizable().interpolation(zoom > 2 ? .none : .high)
                }
            }
            .frame(width: size.width, height: size.height)
            if cropToSubject, let cropOutline {
                Rectangle()
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: cropOutline.width * size.width, height: cropOutline.height * size.height)
                    .offset(x: cropOutline.minX * size.width, y: cropOutline.minY * size.height)
                    .allowsHitTesting(false)
            }
            if refinable {
                refineSurface(size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - The wand and brush surface

    /// A transparent layer over the picture that turns clicks and strokes into refinements.
    private func refineSurface(_ frame: CGSize) -> some View {
        let short = min(frame.width, frame.height)
        return ZStack {
            Color.clear.contentShape(Rectangle())
            if tool == .brush, let pointer {
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    .background(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 3))
                    .frame(width: brushSize * short * 2, height: brushSize * short * 2)
                    .position(pointer)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pointer = value.location
                    guard tool == .brush else { return }
                    brush(to: Self.normalised(value.location, in: frame))
                }
                .onEnded { value in
                    switch tool {
                    case .brush:
                        finishStroke()
                    case .wand:
                        guard hypot(value.translation.width, value.translation.height) < 4 else { return }
                        wand(at: Self.normalised(value.startLocation, in: frame))
                    }
                }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
        .pointerStyle(tool == .wand ? .rectSelection : .default)
        .disabled(subject == nil)
    }

    /// Option swaps Remove and Keep for one click or stroke.
    private var keepsNow: Bool { keep != NSEvent.modifierFlags.contains(.option) }

    private func wand(at point: CGPoint) {
        guard let subject, var current = mask else { return }
        let refinement = BackgroundRemoval.Refinement.wand(point: point, tolerance: tolerance, keep: keepsNow)
        BackgroundRemoval.apply(refinement, to: &current, pixels: subject.pixels)
        mask = current
        refinements.append(refinement)
        scheduleRender()
    }

    private func brush(to point: CGPoint) {
        guard var current = mask else { return }
        if stroke.isEmpty { strokeKeeps = keepsNow }
        let segment = stroke.last.map { [$0, point] } ?? [point]
        stroke.append(point)
        BackgroundRemoval.paint(&current, path: segment, radius: brushSize, value: strokeKeeps ? 255 : 0)
        mask = current
        scheduleRender()
    }

    private func finishStroke() {
        guard !stroke.isEmpty else { return }
        refinements.append(.brush(path: stroke, radius: brushSize, keep: strokeKeeps))
        stroke = []
    }

    private func undo() {
        guard !refinements.isEmpty else { return }
        refinements.removeLast()
        replayRefinements()
    }

    private func resetRefinements() {
        refinements.removeAll()
        replayRefinements()
    }

    /// Back to Vision's mask, then every remaining edit in order.
    private func replayRefinements() {
        guard let subject else { return }
        var current = subject.mask
        BackgroundRemoval.refine(&current, with: refinements, pixels: subject.pixels)
        mask = current
        scheduleRender()
    }

    // MARK: - Detection and preview

    private func detectSubject() {
        guard subject == nil, !detecting, let preview = document.preview,
              let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        detecting = true
        detectionError = nil
        Task.detached(priority: .userInitiated) {
            do {
                let vision = try BackgroundRemoval.mask(for: cg)
                guard let pixels = BackgroundRemoval.Pixels(cg),
                      let buffer = BackgroundRemoval.MaskBuffer(vision, width: cg.width, height: cg.height) else {
                    throw OpenTangerineError.encodeFailed("the subject mask")
                }
                let found = Subject(image: CIImage(cgImage: cg), mask: buffer, pixels: pixels)
                await MainActor.run {
                    subject = found
                    mask = buffer
                    refinements = []
                    detecting = false
                    scheduleRender()
                }
            } catch {
                await MainActor.run {
                    detectionError = error.localizedDescription
                    detecting = false
                }
            }
        }
    }

    /// The preview is never cropped, so clicks land where they look; the crop shows as an outline.
    private func scheduleRender() {
        renderTask?.cancel()
        guard let subject else { return }
        let maskImage = (mask ?? subject.mask).ciImage()
        let options = BackgroundRemoval.Options(softness: softness, cropToSubject: false)
        let outline = cropToSubject
        renderTask = Task.detached(priority: .userInitiated) {
            guard let cutout = try? BackgroundRemoval.cutout(subject.image, mask: maskImage, options: options), !Task.isCancelled else { return }
            let bounds = outline ? BackgroundRemoval.opaqueBounds(cutout) : nil
            let width = CGFloat(cutout.width), height = CGFloat(cutout.height)
            let image = ImageOps.nsImage(cutout)
            await MainActor.run {
                rendered = image
                cropOutline = bounds.map { CGRect(x: $0.minX / width, y: $0.minY / height, width: $0.width / width, height: $0.height / height) }
            }
        }
    }

    private func save() {
        let options = options
        let refinements = refinable ? refinements : []
        let destinations = BackgroundRemoval.outputURLs(for: session.files) { AppSettings.shared.outputLocation.directory(for: $0) }
        ToolWindowManager.shared.close(session)
        for (source, destination) in zip(session.files, destinations) {
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                progress(0.1)
                try await Task.detached(priority: .userInitiated) {
                    let cutout = try BackgroundRemoval.remove(try ImageIOBridge.load(source), options: options, refinements: refinements)
                    try ImageIOBridge.write(cutout, to: destination, format: .png)
                }.value
                return [destination]
            }
        }
    }

    // MARK: - Geometry

    /// The picture's rectangle when fitted inside `container`, less a 12-point margin.
    static func fitted(_ size: CGSize, in container: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let available = CGSize(width: max(1, container.width - 24), height: max(1, container.height - 24))
        let scale = min(available.width / size.width, available.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    static func normalised(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x / max(size.width, 1), 0), 1), y: min(max(point.y / max(size.height, 1), 0), 1))
    }
}
