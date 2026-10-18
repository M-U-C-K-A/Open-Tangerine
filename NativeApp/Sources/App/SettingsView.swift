import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case conversion
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .conversion: return "Formats"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .conversion: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsTabModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var model: SettingsTabModel
    @State private var ffmpegHealth: FFmpeg.Health = .missing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selection

    static let width: CGFloat = 820
    static let height: CGFloat = 620

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.accent.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open").font(.system(size: 15, weight: .medium))
                        Text("Tangerine").font(.system(size: 18, weight: .bold))
                    }
                }
                .padding(.top, 20)
                VStack(spacing: 6) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.85)) {
                                model.tab = tab
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.symbol).font(.system(size: 16, weight: .medium)).frame(width: 22)
                                Text(tab.title).font(.system(size: 14, weight: model.tab == tab ? .semibold : .medium))
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .foregroundStyle(model.tab == tab ? Color.white : Color.primary)
                            .background {
                                if model.tab == tab {
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(Theme.accent.gradient)
                                        .matchedGeometryEffect(id: "sidebar", in: selection)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(SettingsPressStyle())
                        .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label("On your Mac", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Your files. Your workflow.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("OPEN SOURCE  /  0.1.1")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)
            }
            .padding(20).frame(width: 205)
            .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MAKE ROOM FOR FLOW")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2).foregroundStyle(Theme.accent)
                        Text(model.tab.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(tabDescription)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    FileOrbitGraphic(tab: model.tab)
                        .frame(width: 155, height: 145)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 30).padding(.top, 12).padding(.bottom, 4)
                ZStack {
                    Form {
                        switch model.tab {
                        case .general: general
                        case .appearance: appearance
                        case .conversion: conversion
                        case .about: about
                        }
                    }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .id(model.tab)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 9)))
                }
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28), value: model.tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(colors: [Theme.accent.opacity(0.06), Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor)], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refreshLoginStatus() }
        .task(id: settings.ffmpegPath) { ffmpegHealth = await FFmpeg.checkHealth() }
    }

    private var tabDescription: String {
        switch model.tab {
        case .general: return "A few thoughtful defaults. A smoother day."
        case .appearance: return "Make your workspace feel like yours."
        case .conversion: return "Find the balance between detail and size."
        case .about: return "Small utility. Open possibilities."
        }
    }

    @ViewBuilder private var general: some View {
        Section("Output") {
            Picker("Save converted files", selection: $settings.outputLocation) {
                ForEach(OutputLocation.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Reveal results in Finder", isOn: $settings.revealInFinder)
        }
        Section("General") {
            Toggle("Start automatically at login", isOn: $settings.launchAtLogin)
            Text("Keep Open Tangerine ready in the menu bar after you restart and sign in. Move the app to Applications before enabling.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = settings.loginMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
                Button("Open Login Items…") { settings.openLoginSettings() }
            }
        }
        Section {
            LabeledContent("Conversion wheel") {
                Label("Shift", systemImage: "shift").labelStyle(.titleAndIcon)
            }
            LabeledContent("Tools wheel") {
                Label("Command (or Option + Shift)", systemImage: "option").labelStyle(.titleAndIcon)
            }
            LabeledContent("File actions", value: "Control")
        } header: {
            Text("Drag Modifiers")
        } footer: {
            Text("Hold the modifier while dragging files in Finder.")
        }
    }

    @ViewBuilder private var appearance: some View {
        Section("Theme") {
            Picker("Theme", selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        Section {
            Picker("Progress", selection: $settings.progressStyle) {
                ForEach(ProgressStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Progress")
        } footer: {
            Text(settings.progressStyle == .card
                 ? "A floating card in the top right corner with the file name and percentage."
                 : "A tiny progress bar in a pill below the notch.")
        }
    }

    @ViewBuilder private var conversion: some View {
        Section("Images") {
            HStack {
                Text("JPEG / HEIC / WebP quality")
                Slider(value: $settings.jpegQuality, in: 0.3...1.0)
                Text("\(Int(settings.jpegQuality * 100))%").contentTransition(.numericText()).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
        Section {
            Picker("Preset", selection: $settings.compressionPreset) {
                ForEach(CompressionPreset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Resize long edge to")
                TextField("Off", value: $settings.compressionResizeLongEdge, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("px (0 = keep size)").foregroundStyle(.secondary)
            }
        } header: {
            Text("Compression")
        } footer: {
            Text(settings.compressionPreset == .balanced
                 ? "Balanced keeps detail while trimming size noticeably."
                 : "Strong prioritizes the smallest file, with visible quality loss.")
        }
        Section {
            HStack {
                TextField("Auto-detect (Homebrew, MacPorts, /usr/local/bin)", text: $settings.ffmpegPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseFFmpeg() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: ffmpegHealthSymbol)
                    .foregroundStyle(ffmpegHealthColor)
                Text(ffmpegHealthText)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } header: {
            Text("FFmpeg (optional)")
        } footer: {
            Text("Open Tangerine uses Apple frameworks for most work. FFmpeg fills the gaps: MP3, FLAC, OGG, Opus, WMA, MKV, WebM, AVI, WMV, GIF and AVIF/WebP encoding on older systems.")
        }
    }

    @ViewBuilder private var about: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Tangerine").font(.title2.weight(.semibold))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        Section {
            LabeledContent("Defined conversion routes", value: "\(ConversionMatrix.totalConversions)")
            LabeledContent("Tools", value: "\(ToolID.total)")
        } footer: {
            Text("Early trial • GPL-3.0-only. By Syntax Error Private Limited. Based on Satsuma by plyght (MIT). Optional FFmpeg enables additional codecs. Not every route has been verified.")
        }
    }

    private var ffmpegHealthSymbol: String {
        switch ffmpegHealth {
        case .ready: return "checkmark.circle.fill"
        case .broken: return "xmark.octagon.fill"
        case .missing: return "exclamationmark.triangle.fill"
        }
    }

    private var ffmpegHealthColor: Color {
        switch ffmpegHealth {
        case .ready: return .green
        case .broken: return .red
        case .missing: return .orange
        }
    }

    private var ffmpegHealthText: String {
        switch ffmpegHealth {
        case let .ready(path, version): return "Using ffmpeg \(version) at \(path)"
        case let .broken(path, reason): return "ffmpeg at \(path) cannot run: \(reason)"
        case .missing: return "FFmpeg not found. Install with `brew install ffmpeg` or pick the binary."
        }
    }

    private func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            settings.ffmpegPath = url.path
        }
    }
}

struct SettingsTabBar: View {
    @ObservedObject var model: SettingsTabModel
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        model.tab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 13, weight: model.tab == tab ? .semibold : .regular))
                            .foregroundStyle(model.tab == tab ? Color.white : Color.primary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if model.tab == tab {
                            Color.clear
                                .glassEffect(.regular.tint(Theme.accent).interactive(), in: Capsule())
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                }
            }
            .padding(3)
            .glassEffect(.regular, in: Capsule())
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.tab)
    }
}

final class SettingsWindow: NSWindow {
    var toolbarDelegate: SettingsToolbarDelegate?
}

@MainActor
final class SettingsToolbarDelegate: NSObject, NSToolbarDelegate {
    static let tabsItem = NSToolbarItem.Identifier("opentangerine.settings.tabs")
    let model: SettingsTabModel

    init(model: SettingsTabModel) {
        self.model = model
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.tabsItem, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.tabsItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let hosting = NSHostingView(rootView: SettingsTabBar(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        item.view = hosting
        item.isBordered = false
        return item
    }
}

