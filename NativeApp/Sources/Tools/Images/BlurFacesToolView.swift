import AppKit
import CoreImage
import SwiftUI

@MainActor
struct BlurFacesToolView: View {
    let session: ToolSession
    @State private var options = FaceBlur.Options()
    @State private var frame: CGImage?
    @State private var faces: [CGRect] = []
    @State private var preview: NSImage?
    @State private var error: String?
    @State private var loading = true

    private var isVideo: Bool { session.primaryFormat.category == .video }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save copy" : "Hide faces in \(session.files.count) files", saveEnabled: frame != nil, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let preview {
                    Image(nsImage: preview).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(24)
                } else if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for faces…").foregroundStyle(.secondary)
                    }
                } else {
                    LoadingOrError(error: error)
                }
            }
        } sidebar: {
            SidebarSection(title: "Faces") {
                Text(loading ? "Looking…" : faces.isEmpty ? "No faces in this \(isVideo ? "frame" : "picture")." : "\(faces.count) face\(faces.count == 1 ? "" : "s") found\(isVideo ? " in this frame" : "").")
                    .font(.callout)
                    .foregroundStyle(faces.isEmpty && !loading ? .orange : .primary)
                Text(isVideo
                     ? "Every frame of the video is searched, so faces that move or appear later are hidden too. The sound is kept."
                     : "Apple Vision finds the faces on this Mac; nothing leaves it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Cover") {
                Picker("", selection: $options.style) {
                    Text("Blur").tag(RedactionStyle.blur)
                    Text("Pixelate").tag(RedactionStyle.pixelate)
                    Text("Box").tag(RedactionStyle.solid)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                LabeledSlider(title: "Margin", value: $options.padding, range: 0...0.8) { String(format: "%.0f%%", $0 * 100) }
                Text("How much around each face is covered: hair, ears and chin.").font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Output") {
                Text("A copy next to each original, named “\(session.baseName) faces hidden”\(isVideo ? ", as MP4" : "").")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Covering faces is a help, not a guarantee: check the result before you share it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { await load() }
        .onChange(of: options) { render() }
    }

    private func load() async {
        do {
            let image: CGImage
            if isVideo {
                let info = await MediaInfo.load(session.primary)
                image = try await VideoOps.snapshot(session.primary, at: min(1, info.duration / 2))
            } else {
                image = ImageIOBridge.resized(try ImageIOBridge.load(session.primary), longEdge: 1600)
            }
            let found = try await Task.detached(priority: .userInitiated) { try FaceBlur.faces(in: CIImage(cgImage: image)) }.value
            frame = image
            faces = found
            loading = false
            render()
        } catch {
            self.error = error.localizedDescription
            loading = false
        }
    }

    /// The faces hidden, with a thin outline around each, so you see what was found.
    private func render() {
        guard let frame else { return }
        let input = CIImage(cgImage: frame)
        guard let hidden = ImageOps.render(FaceBlur.hide(input, faces: faces, options: options), extent: input.extent),
              let context = CGContext(data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(hidden, in: input.extent)
        context.setStrokeColor(Theme.accentNS.cgColor)
        context.setLineWidth(max(2, CGFloat(min(frame.width, frame.height)) / 300))
        for face in faces {
            context.stroke(FaceBlur.covered(face, padding: options.padding, in: input.extent))
        }
        preview = context.makeImage().map(ImageOps.nsImage)
    }

    private func save() {
        let options = options
        let quality = AppSettings.shared.jpegQuality
        ToolWindowManager.shared.close(session)
        for source in session.files {
            let video = FileFormat.detect(source)?.category == .video
            let format: FileFormat = video ? .mp4 : ImageToolSupport.outputFormat(for: source)
            let destination = ConversionMatrix.uniqueURL(directory: AppSettings.shared.outputLocation.directory(for: source), baseName: ConversionMatrix.strippedBaseName(source.lastPathComponent), suffix: "faces hidden", ext: format.fileExtension)
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                if video {
                    try await FaceBlur.applyVideo(source, options: options, to: destination, progress: progress)
                } else {
                    let result = try await Task.detached(priority: .userInitiated) { try FaceBlur.apply(try ImageIOBridge.load(source), options: options) }.value
                    try await ImageIOBridge.writeAnyFormat(result.image, to: destination, format: format, quality: quality)
                }
                return [destination]
            }
        }
    }
}
