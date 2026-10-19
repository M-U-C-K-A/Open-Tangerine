import AppKit
import SwiftUI

/// README screenshots. Renders real app windows offscreen (alpha 0, never ordered
/// key, the app never activates) and writes framed 2x PNGs with cacheDisplay, so
/// no Screen Recording permission is needed and nothing appears on screen.
///
/// Built and run by scripts/readme/build.sh --screens, against the app sources
/// minus App.swift. Liquid Glass (the wheel) and AVPlayer content do not render
/// this way, which is why the wheel and the notch are drawn as SVG instead.
@main
struct ReadmeShotsMain {
    static func main() {
        let app = ShotsApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = ShotsDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// Controls draw their active look when the app and the window say they are active.
final class ShotsApplication: NSApplication {
    override var isActive: Bool { true }
}

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

final class ShotsDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await Shots.run(into: URL(fileURLWithPath: CommandLine.arguments[1]))
                exit(0)
            } catch {
                fputs("failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}

@MainActor
enum Shots {
    static func run(into out: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let samples = out.appendingPathComponent("samples")
        try fm.createDirectory(at: samples, withIntermediateDirectories: true)
        let photo = samples.appendingPathComponent("photo.png")
        let photo2 = samples.appendingPathComponent("beach.jpg")
        let pdf = samples.appendingPathComponent("report.pdf")
        let pdf2 = samples.appendingPathComponent("appendix.pdf")
        let audio = samples.appendingPathComponent("voice.wav")
        let video = samples.appendingPathComponent("clip.mp4")
        try ImageIOBridge.write(SampleMedia.image(width: 1600, height: 1000, hue: 0.08), to: photo, format: .png)
        try ImageIOBridge.write(SampleMedia.image(width: 1200, height: 1200, hue: 0.55), to: photo2, format: .jpg)
        try PDFRenderer.writeImagesPDF([photo, photo2, photo], pageSize: CGSize(width: 612, height: 792), to: pdf) { _ in }
        try PDFRenderer.writeImagesPDF([photo2, photo], pageSize: CGSize(width: 612, height: 792), to: pdf2) { _ in }
        try SampleMedia.writeTone(to: audio, seconds: 6)
        try await SampleMedia.writeVideo(to: video, seconds: 4, hue: 0.08)

        // A clear subject for Remove background: a tangerine and its leaf on sky and grass.
        let scene = CGContext(data: nil, width: 1600, height: 1100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        scene.setFillColor(CGColor(red: 0.55, green: 0.72, blue: 0.85, alpha: 1)); scene.fill(CGRect(x: 0, y: 0, width: 1600, height: 1100))
        scene.setFillColor(CGColor(red: 0.45, green: 0.62, blue: 0.35, alpha: 1)); scene.fill(CGRect(x: 0, y: 0, width: 1600, height: 380))
        scene.setFillColor(CGColor(red: 0.95, green: 0.45, blue: 0.08, alpha: 1)); scene.fillEllipse(in: CGRect(x: 560, y: 260, width: 480, height: 460))
        scene.setFillColor(CGColor(red: 0.3, green: 0.55, blue: 0.2, alpha: 1)); scene.fillEllipse(in: CGRect(x: 800, y: 680, width: 150, height: 70))
        let fruit = samples.appendingPathComponent("tangerine.png")
        try ImageIOBridge.write(scene.makeImage()!, to: fruit, format: .png)

        // Resize & compress shows its enlarging preview: twice the size, rebuilt.
        UserDefaults.standard.set("percent", forKey: "resize.mode")
        UserDefaults.standard.set(200, forKey: "resize.percent")
        UserDefaults.standard.set("enhance", forKey: "resize.method")

        let tools: [(ToolID, [URL])] = [
            (.removeBackground, [fruit]),
            (.resizeImage, [photo]),
            (.watermarkImage, [photo]),
            (.cropImage, [photo]),
            (.editImage, [photo]),
            (.compress, [pdf, video]),
            (.createCollage, [photo, photo2, photo]),
            (.normalizeAudio, [audio]),
            (.organizePDF, [pdf]),
            (.mergePDF, [pdf, pdf2]),
        ]
        let only = ProcessInfo.processInfo.environment["ONLY"]
        for (theme, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            NSApp.appearance = appearance
            for (tool, files) in tools where only == nil || only == tool.rawValue {
                let session = ToolSession(tool: tool, files: files)
                let root = ToolRootView(session: session).environmentObject(AppSettings.shared)
                let window = KeyWindow(contentViewController: NSHostingController(rootView: root))
                window.title = tool.title
                window.subtitle = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                window.toolbarStyle = .unified
                window.isReleasedWhenClosed = false
                window.appearance = appearance
                window.setContentSize(ToolWindowManager.preferredSize(for: tool))
                try await capture(window, to: out.appendingPathComponent("tool-\(tool.rawValue)-\(theme).png"))
            }
            if only == nil || only == "settings" {
                for tab in [SettingsTab.general, .conversion] {
                    let model = SettingsTabModel()
                    model.tab = tab
                    let view = SettingsView(model: model).environmentObject(AppSettings.shared)
                    let controller = NSHostingController(rootView: view)
                    controller.sizingOptions = []
                    let window = KeyWindow(contentViewController: controller)
                    window.styleMask = [.titled, .closable, .miniaturizable]
                    window.titleVisibility = .hidden
                    window.isReleasedWhenClosed = false
                    window.appearance = appearance
                    window.setContentSize(NSSize(width: SettingsView.width, height: SettingsView.height))
                    try await capture(window, to: out.appendingPathComponent("settings-\(tab.rawValue)-\(theme).png"))
                }
            }
        }
        try? fm.removeItem(at: samples)
    }

    /// Renders the window offscreen at 2x, then frames it: rounded corners, a hairline edge, a soft shadow.
    static func capture(_ window: NSWindow, to url: URL, framed: Bool = true) async throws {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.center()
        window.orderFront(nil)
        try await Task.sleep(nanoseconds: 3_500_000_000)
        let view = window.contentView!.superview ?? window.contentView!
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        window.orderOut(nil)
        window.close()
        let image = rep.cgImage!
        let dark = window.appearance?.name == .darkAqua
        let pad: CGFloat = framed ? 40 * scale : 0
        let w = CGFloat(image.width) + pad * 2
        let h = CGFloat(image.height) + pad * 2
        let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: pad, y: pad + (framed ? 8 * scale : 0), width: CGFloat(image.width), height: CGFloat(image.height))
        if framed {
            let radius: CGFloat = 16 * scale
            let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 30 * scale, color: NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22).cgColor)
            ctx.addPath(shape)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.draw(image, in: rect)
            ctx.restoreGState()
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5 * scale, dy: 0.5 * scale), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setStrokeColor((dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.14)).cgColor)
            ctx.setLineWidth(1 * scale)
            ctx.strokePath()
        } else {
            ctx.draw(image, in: rect)
        }
        let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try out.representation(using: .png, properties: [:])!.write(to: url)
        print("wrote \(url.lastPathComponent) \(out.pixelsWide)x\(out.pixelsHigh)")
    }
}
