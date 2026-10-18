import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let dragMonitor = DragMonitor()
    private let radial = RadialController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.start()
        NSApp.setActivationPolicy(.accessory)
        AppSettings.shared.applyAppearance()
        installStatusItem()
        if ScreenshotDriver.isEnabled {
            ScreenshotDriver.run(radial: radial)
            return
        }
        dragMonitor.delegate = radial
        dragMonitor.start()
        // Login-item launches stay quietly in the menu bar; show onboarding once.
        if !UserDefaults.standard.bool(forKey: "hasOpenedSettings") {
            UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
            openSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        radial.presentPicker(for: urls)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 32)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Open Tangerine")?
                .withSymbolConfiguration(.init(pointSize: 21, weight: .semibold))
            symbol?.size = NSSize(width: 22, height: 22)
            symbol?.isTemplate = true
            button.image = symbol
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Open Tangerine: hold Shift while dragging a file"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Convert Files…", action: #selector(convertFiles), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Open Tool for Files…", action: #selector(openTool), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "File Actions…", action: #selector(fileActions), keyEquivalent: "a").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "About Open Tangerine", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Logs", action: #selector(showLogs), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Open Tangerine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func convertFiles() {
        pickFiles { [weak self] urls in self?.radial.presentPicker(for: urls, advanced: false) }
    }

    @objc private func fileActions() {
        pickFiles { [weak self] urls in self?.radial.presentPicker(for: urls, actions: true) }
    }

    @objc private func openTool() {
        pickFiles { [weak self] urls in self?.radial.presentPicker(for: urls, advanced: true) }
    }

    private func pickFiles(_ completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            completion(panel.urls)
        }
    }

    @MainActor
    static func makeSettingsWindow() -> NSWindow {
        let model = SettingsTabModel()
        let view = SettingsView(model: model).environmentObject(AppSettings.shared)
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        let window = SettingsWindow(contentViewController: controller)
        window.title = "Open Tangerine Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsView.width, height: SettingsView.height))
        window.center()
        return window
    }

    @MainActor
    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = Self.makeSettingsWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showLogs() {
        DiagnosticLog.flush()
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.logFile])
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Open Tangerine",
            .applicationVersion: "0.1.1",
            .credits: NSAttributedString(string: "Syntax Error Private Limited • GPL-3.0-only\nBased on Satsuma by plyght (MIT). Independent of Tangerine."),
        ])
    }
}

