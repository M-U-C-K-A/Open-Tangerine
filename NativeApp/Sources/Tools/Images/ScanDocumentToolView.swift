import AppKit
import SwiftUI

/// Scan to PDF: each photo of a page is found and straightened (move its corners if need
/// be), its lighting evened out, and all of them saved as one searchable PDF.
@MainActor
struct ScanDocumentToolView: View {
    let session: ToolSession
    @State private var index = 0
    @State private var images: [URL: CGImage] = [:]
    @State private var quads: [URL: DocumentScan.Quad] = [:]
    @State private var showResult = false
    @StateObject private var result = LatestRenderer<CGImage>()
    @AppStorage("scan.look") private var look: DocumentScan.Look = .gray
    @AppStorage("scan.pageSize") private var pageSize: DocumentScan.PageSize = .a4
    @AppStorage("scan.searchable") private var searchable = true

    private var url: URL { session.files[min(index, session.files.count - 1)] }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save PDF" : "Save \(session.files.count)-page PDF", saveEnabled: images.count == session.files.count, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if showResult, let page = result.output {
                    Image(nsImage: ImageOps.nsImage(page)).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(20)
                } else if let image = images[url] {
                    ZoomableView {
                        QuadEditor(image: ImageOps.nsImage(image), quad: Binding(get: { quads[url] ?? .whole }, set: { quads[url] = $0 }))
                            .padding(20)
                    }
                } else {
                    LoadingOrError(error: nil)
                }
                VStack {
                    Spacer()
                    Picker("", selection: $showResult) {
                        Text("Photo").tag(false)
                        Text("Scan").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .environment(\.colorScheme, .dark)
                }
                .padding(12)
            }
        } sidebar: {
            if session.files.count > 1 {
                SidebarSection(title: "Page \(index + 1) of \(session.files.count)") {
                    HStack {
                        Button { index = max(0, index - 1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                        Button { index = min(session.files.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }.disabled(index == session.files.count - 1)
                        Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Text("Pages follow the order of the files.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            SidebarSection(title: "Page edges") {
                HStack {
                    Button("Find again") { detect(url, force: true) }
                    Button("Whole photo") { quads[url] = .whole }
                }
                .controlSize(.small)
                Text("Drag the corners onto the page's corners. The page is straightened to a rectangle.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Look") {
                Picker("", selection: $look) {
                    ForEach(DocumentScan.Look.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text("Shadows and uneven light are evened out, the paper made white.").font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "PDF") {
                Picker("Page size", selection: $pageSize) {
                    ForEach(DocumentScan.PageSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Searchable text", isOn: $searchable)
                Text(searchable ? "The words are read on this Mac and laid invisibly over each page, so you can search, select and copy them." : "Pages are pictures only.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { await load() }
        .onChange(of: index) { render() }
        .onChange(of: quads) { render() }
        .onChange(of: look) { render() }
        .onChange(of: showResult) { render() }
    }

    private func load() async {
        for url in session.files {
            let loaded = await Task.detached(priority: .userInitiated) { () -> (CGImage, DocumentScan.Quad?)? in
                guard let image = try? ImageIOBridge.load(url) else { return nil }
                return (image, DocumentScan.detect(ImageIOBridge.resized(image, longEdge: 1600)))
            }.value
            guard let loaded else { continue }
            images[url] = loaded.0
            quads[url] = loaded.1 ?? .whole
        }
        render()
    }

    private func detect(_ url: URL, force: Bool) {
        guard let image = images[url] else { return }
        Task {
            let quad = await Task.detached(priority: .userInitiated) { DocumentScan.detect(ImageIOBridge.resized(image, longEdge: 1600)) }.value
            quads[url] = quad ?? .whole
        }
    }

    private func render() {
        guard showResult, let image = images[url] else { return }
        let quad = quads[url] ?? .whole, look = look
        result.submit {
            DocumentScan.flatten(ImageIOBridge.resized(image, longEdge: 2000), quad: quad, look: look)
        }
    }

    private func save() {
        let pages = session.files.compactMap { url in images[url].map { ($0, quads[url] ?? .whole) } }
        let look = look, pageSize = pageSize, searchable = searchable
        let destination = session.outputURL(suffix: "scan", ext: "pdf")
        session.run(title: session.tool.progressTitle, detail: "\(pages.count) page\(pages.count == 1 ? "" : "s")") { progress in
            var flat: [CGImage] = []
            for (index, (image, quad)) in pages.enumerated() {
                guard let page = DocumentScan.flatten(image, quad: quad, look: look) else { throw OpenTangerineError.encodeFailed("page \(index + 1)") }
                flat.append(page)
                progress(0.4 * Double(index + 1) / Double(pages.count))
            }
            try DocumentScan.makePDF(flat, size: pageSize, searchable: searchable, to: destination) { progress(0.4 + 0.6 * $0) }
            return [destination]
        }
    }
}

/// The photo with four corner handles joined by lines: drag each onto the page's corner.
struct QuadEditor: View {
    let image: NSImage
    @Binding var quad: DocumentScan.Quad
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { proxy in
            let fit = FitGeometry(container: proxy.size, image: image.size)
            let rect = fit.displayRect
            let points = quad.corners.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addLines(points)
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Path { path in
                    path.addLines(points)
                    path.closeSubpath()
                }
                .stroke(Theme.accent, lineWidth: 2)
                .allowsHitTesting(false)
                ForEach(0..<4, id: \.self) { corner in
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 3))
                        .frame(width: dragging == corner ? 22 : 18, height: dragging == corner ? 22 : 18)
                        .shadow(radius: 2)
                        .position(points[corner])
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragging = corner
                                    var corners = quad.corners
                                    corners[corner] = CGPoint(x: min(1, max(0, (value.location.x - rect.minX) / rect.width)), y: min(1, max(0, (value.location.y - rect.minY) / rect.height)))
                                    quad.corners = corners
                                }
                                .onEnded { _ in dragging = nil }
                        )
                }
            }
        }
    }
}

/// Make searchable: a copy of each PDF whose scanned pages can be searched and copied.
@MainActor
struct SearchablePDFToolView: View {
    let session: ToolSession
    @State private var scanned: [URL: Int] = [:]

    var body: some View {
        FormShell(session: session, saveTitle: session.files.count == 1 ? "Make searchable" : "Make \(session.files.count) PDFs searchable", onSave: save) {
            ForEach(session.files, id: \.self) { url in
                FormRow(title: url.lastPathComponent) {
                    Text(scanned[url].map { $0 == 0 ? "Already searchable" : "\($0) scanned page\($0 == 1 ? "" : "s") to read" } ?? "Looking…")
                        .foregroundStyle(.secondary)
                }
            }
            FormHint("The words on scanned pages are read on this Mac and laid invisibly over them: the pages look exactly the same, and Preview, Spotlight and other apps can now search, select and copy their text. Pages that already have text are kept as they are.")
            FormHint("A copy is saved next to each original, named “\(session.baseName) searchable.pdf”.")
        }
        .task {
            for url in session.files {
                scanned[url] = await Task.detached {
                    guard let document = PDFDocument(url: url) else { return 0 }
                    return (0..<document.pageCount).filter { (document.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                }.value
            }
        }
    }

    private func save() {
        ToolWindowManager.shared.close(session)
        for source in session.files {
            let destination = ConversionMatrix.uniqueURL(directory: AppSettings.shared.outputLocation.directory(for: source), baseName: ConversionMatrix.strippedBaseName(source.lastPathComponent), suffix: "searchable", ext: "pdf")
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                try await Task.detached(priority: .userInitiated) { try SearchablePDF.make(source, to: destination, progress: progress) }.value
                return [destination]
            }
        }
    }
}

import PDFKit
