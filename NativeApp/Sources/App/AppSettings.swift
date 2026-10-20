import AppKit
import Foundation
import Combine
import ServiceManagement

enum CompressionPreset: String, CaseIterable, Identifiable {
    case balanced
    case strong

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var imageQuality: Double { self == .balanced ? 0.72 : 0.5 }
    var videoScale: Double { self == .balanced ? 1.0 : 0.75 }
    var videoBitrateFactor: Double { self == .balanced ? 0.6 : 0.35 }
    var audioBitrate: Int { self == .balanced ? 128_000 : 64_000 }
}

enum OutputLocation: String, CaseIterable, Identifiable {
    case besideOriginal
    case downloads
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .besideOriginal: return "Next to the original"
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        }
    }

    func directory(for source: URL) -> URL {
        switch self {
        case .besideOriginal: return source.deletingLastPathComponent()
        case .downloads: return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .desktop: return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum ProgressStyle: String, CaseIterable, Identifiable {
    case card
    case pill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: return "Card"
        case .pill: return "Notch pill"
        }
    }
}

enum NotchSurface: String, CaseIterable, Identifiable {
    case black, glass
    var id: String { rawValue }
    var title: String { self == .black ? "Pure black" : "Glass" }
}

/// The color used for highlights, buttons and the wheel.
enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, red, pink, purple, indigo, blue, cyan, teal, green, yellow, graphite

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .orange: return NSColor(srgbRed: 1.0, green: 0.36, blue: 0.0, alpha: 1)
        case .red: return NSColor(srgbRed: 0.93, green: 0.2, blue: 0.24, alpha: 1)
        case .pink: return NSColor(srgbRed: 0.96, green: 0.26, blue: 0.55, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.62, green: 0.3, blue: 0.92, alpha: 1)
        case .indigo: return NSColor(srgbRed: 0.36, green: 0.36, blue: 0.94, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        case .cyan: return NSColor(srgbRed: 0.0, green: 0.7, blue: 0.86, alpha: 1)
        case .teal: return NSColor(srgbRed: 0.0, green: 0.62, blue: 0.58, alpha: 1)
        case .green: return NSColor(srgbRed: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.95, green: 0.68, blue: 0.0, alpha: 1)
        case .graphite: return NSColor(srgbRed: 0.45, green: 0.47, blue: 0.5, alpha: 1)
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var accentChoice: AccentChoice {
        didSet { defaults.set(accentChoice.rawValue, forKey: "accentChoice") }
    }

    /// Rounding of cards and panels, in points.
    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: "cornerRadius") }
    }

    /// Tool windows see through to the desktop, blurred, with cards of Liquid Glass.
    @Published var liquidGlass: Bool {
        didSet { defaults.set(liquidGlass, forKey: "liquidGlass") }
    }

    /// How much of the window's own color covers the glass: 0 shows the desktop, 1 hides it.
    @Published var glassOpacity: Double {
        didSet { defaults.set(glassOpacity, forKey: "glassOpacity") }
    }

    private let defaults = UserDefaults.standard

    /// Apps whose drags never open the wheel, by bundle identifier, with their names.
    @Published var excludedApplications: [String: String] {
        didSet { defaults.set(excludedApplications, forKey: "excludedApplications") }
    }

    @Published var compressionPreset: CompressionPreset {
        didSet { defaults.set(compressionPreset.rawValue, forKey: "compressionPreset") }
    }

    @Published var outputLocation: OutputLocation {
        didSet { defaults.set(outputLocation.rawValue, forKey: "outputLocation") }
    }

    @Published var revealInFinder: Bool {
        didSet { defaults.set(revealInFinder, forKey: "revealInFinder") }
    }

    /// Folders whose new files are converted on arrival.
    @Published var watchRules: [WatchRule] {
        didSet { defaults.set(try? JSONEncoder().encode(watchRules), forKey: "watchRules") }
    }

    /// Hold Shift alone over Finder to open the wheel for the selected files, no drag needed.
    @Published var shiftOpensWheel: Bool {
        didSet { defaults.set(shiftOpensWheel, forKey: "shiftOpensWheel") }
    }

    @Published var notchSurface: NotchSurface {
        didSet { defaults.set(notchSurface.rawValue, forKey: "notchSurface") }
    }

    @Published var progressStyle: ProgressStyle {
        didSet { defaults.set(progressStyle.rawValue, forKey: "progressStyle") }
    }

    @Published var ffmpegPath: String {
        didSet { defaults.set(ffmpegPath, forKey: "ffmpegPath") }
    }

    @Published var launchAtLogin: Bool {
        didSet { if !refreshingLoginStatus { applyLaunchAtLogin() } }
    }

    @Published var loginMessage: String?
    private var refreshingLoginStatus = false

    @Published var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: "jpegQuality") }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    private init() {
        excludedApplications = defaults.dictionary(forKey: "excludedApplications") as? [String: String] ?? [:]
        accentChoice = AccentChoice(rawValue: defaults.string(forKey: "accentChoice") ?? "") ?? .orange
        cornerRadius = defaults.object(forKey: "cornerRadius") as? Double ?? 12
        liquidGlass = defaults.object(forKey: "liquidGlass") as? Bool ?? false
        glassOpacity = defaults.object(forKey: "glassOpacity") as? Double ?? 0.55
        compressionPreset = CompressionPreset(rawValue: defaults.string(forKey: "compressionPreset") ?? "") ?? .balanced
        outputLocation = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "") ?? .besideOriginal
        revealInFinder = defaults.object(forKey: "revealInFinder") as? Bool ?? true
        shiftOpensWheel = defaults.object(forKey: "shiftOpensWheel") as? Bool ?? true
        watchRules = (defaults.data(forKey: "watchRules")).flatMap { try? JSONDecoder().decode([WatchRule].self, from: $0) } ?? []
        notchSurface = NotchSurface(rawValue: defaults.string(forKey: "notchSurface") ?? "") ?? .black
        progressStyle = ProgressStyle(rawValue: defaults.string(forKey: "progressStyle") ?? "") ?? .pill
        // One-time migration requested for existing trial installs; future user choices persist.
        if !defaults.bool(forKey: "notchDefaultV012") {
            progressStyle = .pill
            defaults.set("pill", forKey: "progressStyle")
            defaults.set(true, forKey: "notchDefaultV012")
        }
        ffmpegPath = defaults.string(forKey: "ffmpegPath") ?? ""
        jpegQuality = defaults.object(forKey: "jpegQuality") as? Double ?? 0.9
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }

    func applyAppearance() {
        NSApp.appearance = appearanceMode.appearance
    }

    func refreshLoginStatus(preserveError: Bool = false) {
        refreshingLoginStatus = true
        defer { refreshingLoginStatus = false }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        if !preserveError {
            loginMessage = status == .requiresApproval
                ? "Allow Open Tangerine in System Settings → General → Login Items."
                : nil
        }
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginStatus()
        } catch {
            loginMessage = "Could not update automatic startup: \(error.localizedDescription)"
            refreshLoginStatus(preserveError: true)
        }
    }
}

