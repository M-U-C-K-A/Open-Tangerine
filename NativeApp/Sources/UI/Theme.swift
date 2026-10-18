import AppKit
import SwiftUI

enum Theme {
    static let accentNS = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.0, alpha: 1)
    static let accent = Color(nsColor: accentNS)

    static let ink = Color(nsColor: .labelColor)
    static let inkSecondary = Color(nsColor: .secondaryLabelColor)
    static let cardCorner: CGFloat = 12

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.cardCorner

    func body(content: Content) -> some View {
        content
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
    }
}

extension View {
    func card(cornerRadius: CGFloat = Theme.cardCorner) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
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
