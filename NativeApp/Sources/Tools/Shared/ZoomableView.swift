import AppKit
import SwiftUI

/// Where a zoomable view is: how far in, and where it has been moved to.
@MainActor
final class ZoomModel: ObservableObject {
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var offset: CGSize = .zero
    var size: CGSize = .zero
    /// The pointer over the view, in its own coordinates; nil when it is elsewhere.
    var pointer: CGPoint?

    static let range: ClosedRange<CGFloat> = 1...16

    /// Zooms keeping the content point under `anchor` where it is.
    func set(_ value: CGFloat, around anchor: CGPoint? = nil) {
        let old = zoom
        let new = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        guard abs(new - old) > 0.0001 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let point = anchor ?? center
        // A content point p shows at center + offset + (p - center) × zoom.
        let dx = point.x - center.x - offset.width, dy = point.y - center.y - offset.height
        offset = CGSize(width: point.x - center.x - dx * new / old, height: point.y - center.y - dy * new / old)
        zoom = new
        clamp()
    }

    func pan(by delta: CGSize) {
        offset.width += delta.width
        offset.height += delta.height
        clamp()
    }

    /// The content always covers the view: it can't be dragged out of sight.
    func clamp() {
        guard zoom > 1.0001 else { offset = .zero; return }
        let mx = (zoom - 1) * size.width / 2, my = (zoom - 1) * size.height / 2
        offset = CGSize(width: min(mx, max(-mx, offset.width)), height: min(my, max(-my, offset.height)))
    }
}

/// Zoom and move around in any picture editor: ⌃ with the scroll wheel, or a pinch, zooms where
/// the pointer is; scrolling moves around once zoomed in; ⌘+, ⌘− and ⌘0 (fit) from the keyboard.
/// The content keeps its gestures, which see its own, unzoomed coordinates.
struct ZoomableView<Content: View>: View {
    var showsControls = true
    @ViewBuilder var content: () -> Content
    @StateObject private var model = ZoomModel()
    @State private var monitor: Any?
    @State private var pinchStart: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            content()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(model.zoom)
                .offset(model.offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let point) = phase { model.pointer = point } else { model.pointer = nil }
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in model.set(pinchStart * value.magnification, around: value.startLocation) }
                        .onEnded { _ in pinchStart = model.zoom }
                )
                .onAppear {
                    model.size = proxy.size
                    install()
                }
                .onChange(of: proxy.size) {
                    model.size = proxy.size
                    model.clamp()
                }
                .onDisappear(perform: remove)
        }
        .overlay(alignment: .topTrailing) {
            if showsControls { controls.padding(12) }
        }
    }

    /// Zoom out, fit, zoom in.
    private var controls: some View {
        HStack(spacing: 2) {
            Button { model.set(model.zoom / 1.5); pinchStart = model.zoom } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model.zoom <= ZoomModel.range.lowerBound)
                .help("Zoom out (⌘−)")
            Button { model.set(1); pinchStart = 1 } label: {
                Text(model.zoom <= 1.001 ? "Fit" : "\(Int((model.zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Fit the picture in the window (⌘0)")
            Button { model.set(model.zoom * 1.5); pinchStart = model.zoom } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(model.zoom >= ZoomModel.range.upperBound)
                .help("Zoom in (⌘+), or ⌃ and the scroll wheel")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func install() {
        guard monitor == nil else { return }
        let model = model
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let pointer = model.pointer else { return event }
            let precise = event.hasPreciseScrollingDeltas
            if event.modifierFlags.contains(.control) {
                var delta = Double(precise ? event.scrollingDeltaY : event.scrollingDeltaY * 10)
                if event.isDirectionInvertedFromDevice { delta = -delta }
                model.set(model.zoom * CGFloat(exp(delta * 0.01)), around: pointer)
                return nil
            }
            guard model.zoom > 1.0001 else { return event }
            let scale: CGFloat = precise ? 1 : 10
            model.pan(by: CGSize(width: event.scrollingDeltaX * scale, height: event.scrollingDeltaY * scale))
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
