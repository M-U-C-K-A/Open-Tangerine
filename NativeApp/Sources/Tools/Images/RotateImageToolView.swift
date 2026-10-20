import AppKit
import SwiftUI

@MainActor
struct RotateImageToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @State private var quarterTurns = 0
    @State private var flipH = false
    @State private var flipV = false

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: 1600))
    }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save copy" : "Apply to \(session.files.count) images", saveEnabled: document.preview != nil, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let preview = document.preview {
                    ZoomableView {
                        Image(nsImage: preview)
                            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .rotationEffect(.degrees(Double(quarterTurns) * 90))
                            .scaleEffect(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
                            .padding(40)
                            .animation(.easeInOut(duration: 0.18), value: quarterTurns)
                    }
                } else {
                    LoadingOrError(error: document.error)
                }
            }
        } sidebar: {
            SidebarSection(title: "Rotate") {
                HStack {
                    Button { quarterTurns = (quarterTurns + 3) % 4 } label: { Label("Left", systemImage: "rotate.left") }
                    Button { quarterTurns = (quarterTurns + 1) % 4 } label: { Label("Right", systemImage: "rotate.right") }
                }
                Text("\(quarterTurns * 90)°").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Flip") {
                Toggle("Flip horizontally", isOn: $flipH)
                Toggle("Flip vertically", isOn: $flipV)
            }
            if session.files.count > 1 {
                SidebarSection(title: "Batch") {
                    Text("The same rotation and flips are applied to all \(session.files.count) images.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        let turns = quarterTurns, h = flipH, v = flipV
        ImageToolSupport.saveEach(session, suffix: "rotated", title: "Rotating", detail: "\(session.files.count) image\(session.files.count == 1 ? "" : "s")") { _, image in
            try ImageOps.rotated(image, quarterTurns: turns, flipHorizontal: h, flipVertical: v)
        }
    }
}

