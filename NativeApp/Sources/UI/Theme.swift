import AppKit
import SwiftUI

/// Colors and shapes, as set in Settings → Appearance. Read from the stored settings, so any
/// thread can ask; views that should follow changes live observe `AppSettings.shared`.
enum Theme {
    static var accentNS: NSColor {
        (AccentChoice(rawValue: UserDefaults.standard.string(forKey: "accentChoice") ?? "") ?? .orange).nsColor
    }
    static var accent: Color { Color(nsColor: accentNS) }

    static let ink = Color(nsColor: .labelColor)
    static let inkSecondary = Color(nsColor: .secondaryLabelColor)
    static var cardCorner: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "cornerRadius") as? Double ?? 12) }
    static var controlCorner: CGFloat { max(3, cardCorner * 0.6) }
    static var liquidGlass: Bool { UserDefaults.standard.object(forKey: "liquidGlass") as? Bool ?? false }
    static var glassOpacity: Double { UserDefaults.standard.object(forKey: "glassOpacity") as? Double ?? 0.55 }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat?
    @ObservedObject private var settings = AppSettings.shared

    init(cornerRadius: CGFloat? = nil) {
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? CGFloat(settings.cornerRadius), style: .continuous)
        if settings.liquidGlass {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.quaternary.opacity(0.5), in: shape)
                .overlay { shape.strokeBorder(.separator, lineWidth: 1) }
        }
    }
}

extension View {
    func card(cornerRadius: CGFloat? = nil) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

/// Behind a window's content: its usual color, or with Liquid Glass the desktop blurred
/// through, under as much of that color as the opacity setting asks.
struct WindowBackdrop: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if settings.liquidGlass {
            ZStack {
                BehindWindowBlur()
                Color(nsColor: .windowBackgroundColor).opacity(settings.glassOpacity)
            }
            .ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        }
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}


/// A brief, state-driven illustration: no permanent animation timer.
struct FileOrbitGraphic: View {
    let tab: SettingsTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var angle: Double { Double(SettingsTab.allCases.firstIndex(of: tab) ?? 0) * 90 }
    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.07)).frame(width: 132, height: 132)
            Circle().strokeBorder(Theme.accent.opacity(0.17), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                .frame(width: 124, height: 124)
                .rotationEffect(.degrees(reduceMotion ? 0 : angle))
            ForEach(0..<3) { index in
                let radians = Double(index) * .pi * 2 / 3 - .pi / 2
                Image(systemName: ["photo", "waveform", "doc.text"][index])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 29, height: 29)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accent.opacity(0.16)))
                    .offset(x: cos(radians) * 61, y: sin(radians) * 61)
            }
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.accent.gradient)
                .frame(width: 70, height: 78)
                .rotationEffect(.degrees(reduceMotion ? 0 : appeared ? -7 : -15))
                .shadow(color: Theme.accent.opacity(0.23), radius: 12, x: 0, y: 8)
            Image(systemName: tab == .general ? "arrow.triangle.2.circlepath" : tab.symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace.offUp))
        }
        .scaleEffect(reduceMotion ? 1 : appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.6, dampingFraction: 0.7), value: appeared)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: tab)
        .onAppear { appeared = true }
    }
}

struct SettingsPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(hovering ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 13))
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}
