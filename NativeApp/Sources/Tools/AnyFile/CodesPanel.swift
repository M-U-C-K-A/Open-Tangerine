import AppKit
import SwiftUI

/// A small window with the QR codes and barcodes found: the picture with each code
/// outlined (hover one to see what it holds, click to open its link), and a list.
@MainActor
enum CodesPanel {
    private static var window: NSWindow?

    static func show(for urls: [URL]) {
        window?.close()
        let controller = NSHostingController(rootView: CodesView(urls: urls))
        let panel = NSWindow(contentViewController: controller)
        panel.title = "Codes"
        panel.subtitle = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        panel.styleMask = [.titled, .closable, .resizable]
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 560, height: 560))
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct CodesView: View {
    let urls: [URL]
    @State private var codes: [BarcodeReader.Code] = []
    @State private var picture: NSImage?
    @State private var hovered: UUID?
    @State private var loading = true
    @State private var error: String?
    @State private var copied: UUID?

    private var firstFile: String { urls.first?.lastPathComponent ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            if let picture {
                GeometryReader { proxy in
                    let size = Self.fit(picture.size, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: picture).resizable().frame(width: size.width, height: size.height)
                        ForEach(codes.filter { $0.file == firstFile }) { code in
                            let rect = CGRect(x: code.box.minX * size.width, y: code.box.minY * size.height, width: code.box.width * size.width, height: code.box.height * size.height)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.accent.opacity(hovered == code.id ? 0.25 : 0.08))
                                .strokeBorder(Theme.accent, lineWidth: hovered == code.id ? 3 : 2)
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                                .onHover { hovered = $0 ? code.id : nil }
                                .onTapGesture { open(code) }
                                .help(code.payload)
                                .overlay(alignment: .topLeading) {
                                    if hovered == code.id {
                                        Text(code.payload)
                                            .font(.caption).lineLimit(2)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                            .offset(x: rect.minX, y: rect.maxY + 6)
                                            .frame(maxWidth: 360, alignment: .leading)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
                .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
            }
            List(codes) { code in
                HStack(spacing: 10) {
                    Image(systemName: code.kind == "QR code" ? "qrcode" : "barcode").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code.payload).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                        Text("\(code.kind) · \(code.file)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if code.link != nil {
                        Button("Open") { open(code) }
                    }
                    Button(copied == code.id ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.payload, forType: .string)
                        copied = code.id
                    }
                }
                .padding(.vertical, 2)
                .listRowBackground(hovered == code.id ? Theme.accent.opacity(0.12) : Color.clear)
                .onHover { hovered = $0 ? code.id : nil }
                .help(code.payload)
            }
            .overlay {
                if loading {
                    ProgressView("Reading codes…")
                } else if let error {
                    Text(error).foregroundStyle(.secondary).padding()
                } else if codes.isEmpty {
                    Text("No QR code or barcode found.").foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 150)
        }
        .tint(Theme.accent)
        .task { await load() }
    }

    private func open(_ code: BarcodeReader.Code) {
        guard let link = code.link else { return }
        NSWorkspace.shared.open(link)
    }

    private func load() async {
        let urls = urls
        do {
            let found = try await Task.detached(priority: .userInitiated) { try BarcodeReader.codes(in: urls) }.value
            codes = found
            if let first = urls.first, FileFormat.detect(first)?.category == .image, let image = try? ImageIOBridge.load(first) {
                picture = ImageOps.nsImage(image)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    static func fit(_ size: CGSize, in container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(container.width / size.width, container.height / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
