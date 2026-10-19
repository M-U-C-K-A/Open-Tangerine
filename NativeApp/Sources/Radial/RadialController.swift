import AppKit

final class RadialPanel: NSPanel {
    let radialView = RadialView(frame: .zero)

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        radialView.frame = contentView?.bounds ?? .zero
        radialView.autoresizingMask = [.width, .height]
        contentView = radialView
    }

    override var canBecomeKey: Bool { true }
}

final class RadialController: DragMonitorDelegate {
    private var panel: RadialPanel?
    private var urls: [URL] = []
    private var formats: [FileFormat] = []
    private var mode: RadialMode = .convert
    /// The wheel the held modifiers last asked for. A scroll can move on from it;
    /// only a change of modifiers moves the wheel back.
    private var modifierMode: RadialMode = .convert
    private var visible = false
    private var pickerMode = false
    /// The wheel was opened by holding Shift alone, and Shift is still down.
    private var holdingShift = false
    /// The app in front before a Shift-alone wheel took focus; it gets focus back.
    private var returnFocusTo: NSRunningApplication?
    private var outsideClickMonitor: Any?

    weak var dragMonitor: DragMonitor?

    func dragMonitor(_ monitor: DragMonitor, didBeginModifiedDrag urls: [URL], at point: NSPoint, advanced: Bool) {
        dragMonitor = monitor
        pickerMode = false
        holdingShift = false
        let wanted = RadialMode.forModifiers(command: false, option: advanced, control: NSEvent.modifierFlags.contains(.control))
        modifierMode = wanted
        present(urls: urls, at: point, mode: wanted)
    }

    func dragMonitor(_ monitor: DragMonitor, didChangeModifiers shift: Bool, option: Bool, at point: NSPoint) {
        guard !pickerMode else { return }
        if !shift { return }
        let wanted = RadialMode.forModifiers(command: false, option: option, control: NSEvent.modifierFlags.contains(.control))
        if !visible {
            modifierMode = wanted
            present(urls: urls, at: point, mode: wanted)
            return
        }
        guard wanted != modifierMode else { return }
        modifierMode = wanted
        setMode(wanted)
    }

    /// Shift held alone over Finder: open the wheel for Finder's selection.
    func dragMonitor(_ monitor: DragMonitor, didHoldShiftAt point: NSPoint) {
        dragMonitor = monitor
        guard !visible else { return }
        let front = NSWorkspace.shared.frontmostApplication
        Task { @MainActor [weak self] in
            switch await FinderSelection.current() {
            case .success(let urls):
                guard let self, !self.visible, !urls.isEmpty else {
                    DiagnosticLog.log("shift hold: nothing selected in Finder")
                    return
                }
                DiagnosticLog.log("shift hold: wheel for \(urls.count) Finder file(s)")
                self.presentPicker(for: urls)
                self.holdingShift = NSEvent.modifierFlags.contains(.shift)
                self.returnFocusTo = front
            case .failure(.notAuthorized):
                FinderSelection.explainPermission()
            case .failure(.failed(let message)):
                DiagnosticLog.log("shift hold: Finder selection failed: \(message)")
            }
        }
    }

    /// Letting go of Shift over a choice picks it; anywhere else the wheel stays open to click.
    func dragMonitorDidReleaseShift(_ monitor: DragMonitor) {
        guard holdingShift else { return }
        holdingShift = false
        if visible, let item = panel?.radialView.highlightedItem { select(item) }
    }

    func dragMonitor(_ monitor: DragMonitor, didUpdateDraggedURLs urls: [URL]) {
        adopt(urls)
    }

    func dragMonitorDidEndDrag(_ monitor: DragMonitor) {
        guard !pickerMode else { return }
        keepOpenAfterDrop()
    }

    func presentPicker(for urls: [URL], advanced: Bool = false, actions: Bool = false) {
        let wanted: RadialMode = actions ? .actions : advanced ? .tools : .convert
        modifierMode = wanted
        pickerMode = true
        let point = NSEvent.mouseLocation
        present(urls: urls, at: point, mode: wanted)
        panel?.radialView.interactive = true
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(panel?.radialView)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitor()
    }

    private func present(urls: [URL], at point: NSPoint, mode: RadialMode) {
        self.urls = urls
        // Folders, archives and unknown files can only take file actions: start there.
        let detected = urls.compactMap(FileFormat.detect)
        let convertible = detected.count == urls.count && !urls.contains(where: FileAction.isDirectory)
            && (!ConversionMatrix.targets(for: detected).isEmpty || !ToolID.available(for: urls).isEmpty)
        self.mode = convertible || urls.isEmpty ? mode : .actions
        formats = urls.compactMap(FileFormat.detect)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let panel = self.panel ?? RadialPanel(screen: screen)
        panel.setFrame(screen.frame, display: false)
        self.panel = panel

        let view = panel.radialView
        view.interactive = pickerMode
        view.mode = self.mode
        let clamped = clampedCenter(point, in: screen.frame, radius: view.discRadius + 48)
        view.center = NSPoint(x: clamped.x - screen.frame.minX, y: clamped.y - screen.frame.minY)
        view.onSelect = { [weak self] item in self?.select(item) }
        view.onCancel = { [weak self] in self?.hide() }
        view.onDragEntered = { [weak self] info in self?.adoptDraggedFiles(from: info) }
        view.onDragSessionEnded = { [weak self] in self?.dragSessionEnded() }
        view.onDropMissed = { [weak self] in self?.keepOpenAfterDrop() }
        view.onModeStep = { [weak self] step in
            guard let self else { return }
            self.setMode(self.mode.stepped(step))
        }
        view.clearHighlight()
        reloadItems()
        view.animatePresentation()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            panel.animator().alphaValue = 1
        }
        visible = true
        Task { @MainActor in JobRunner.shared.beginWatching() }
    }

    private func clampedCenter(_ point: NSPoint, in frame: NSRect, radius: CGFloat) -> NSPoint {
        NSPoint(
            x: min(max(point.x, frame.minX + radius), frame.maxX - radius),
            y: min(max(point.y, frame.minY + radius), frame.maxY - radius)
        )
    }

    private func adoptDraggedFiles(from info: NSDraggingInfo) {
        guard !pickerMode else { return }
        let dragged = DragMonitor.fileURLs(on: info.draggingPasteboard)
        DragDebug.log("drag entered wheel; pasteboard urls=\(dragged.map(\.lastPathComponent)) known=\(urls.map(\.lastPathComponent))")
        adopt(dragged)
    }

    private func adopt(_ dragged: [URL]) {
        guard !pickerMode, visible, !dragged.isEmpty, dragged != urls else { return }
        urls = dragged
        formats = dragged.compactMap(FileFormat.detect)
        reloadItems()
    }

    private func dragSessionEnded() {
        guard !pickerMode, visible else { return }
        DragDebug.log("drag session ended while wheel visible; keeping it open")
        keepOpenAfterDrop()
    }

    /// Letting go anywhere but on a choice (the hub, a gap, beside the wheel) keeps the
    /// wheel open: click a choice, scroll to another wheel, or click beside it to close.
    /// The short delay lets a drop on a choice, dispatched asynchronously, win.
    private func keepOpenAfterDrop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.visible, !self.pickerMode, let panel = self.panel else { return }
            DragDebug.log("drop missed every choice; wheel stays open")
            self.pickerMode = true
            self.holdingShift = false
            self.dragMonitor?.markHandled()
            self.returnFocusTo = NSWorkspace.shared.frontmostApplication
            let view = panel.radialView
            view.interactive = true
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
            self.installOutsideClickMonitor()
            view.updateHighlight(forWindowPoint: panel.mouseLocationOutsideOfEventStream)
        }
    }

    /// Shows another of the three wheels for the same files.
    private func setMode(_ newMode: RadialMode) {
        guard visible, newMode != mode else { return }
        mode = newMode
        panel?.radialView.clearHighlight()
        reloadItems()
        panel?.radialView.animatePresentation()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func reloadItems() {
        guard let view = panel?.radialView else { return }
        view.mode = mode
        let count = urls.count
        if count == 0 {
            view.items = []
            view.subtitle = "Move the files over the wheel"
            switch mode {
            case .convert: view.emptyMessage = "Drop here to convert"
            case .tools: view.emptyMessage = "Drop here for tools"
            case .actions: view.emptyMessage = "Drop here for file actions"
            }
            return
        }
        view.subtitle = count == 1 ? urls[0].lastPathComponent : "\(count) files"
        if mode == .actions {
            view.items = FileAction.available(for: urls).map(RadialItem.init(fileAction:))
            view.emptyMessage = "No file actions"
            return
        }
        if formats.count != urls.count {
            view.items = []
            view.emptyMessage = urls.contains(where: FileAction.isDirectory) ? "Folders: scroll to File actions" : "Some files can't be converted: scroll to File actions"
            return
        }
        if mode == .tools {
            view.items = ToolID.available(for: urls).map(RadialItem.init(tool:))
            view.emptyMessage = "No tools for this selection"
        } else {
            // A PDF that asks for a password can't be read until it is removed.
            view.items = ToolID.containsLockedPDF(urls) ? [] : ConversionMatrix.targets(for: formats).map(RadialItem.init(format:))
            if ToolID.containsLockedPDF(urls) {
                view.emptyMessage = "Password-protected: scroll to Tools to remove it"
                return
            }
            view.emptyMessage = count > 1 ? "No shared conversion for these files" : "No conversions available"
        }
    }

    private func select(_ item: RadialItem) {
        let selectedURLs = urls
        DiagnosticLog.log("radial select \(item.detail) for \(selectedURLs.map(\.lastPathComponent))")
        // A tool opens its own window and the checksum shows an alert: those keep focus here.
        switch item.action {
        case .tool, .fileAction(.hash): hide(returningFocus: false)
        default: hide()
        }
        dragMonitor?.markHandled()
        DiagnosticLog.log("radial hidden, dispatching action")
        Task { @MainActor in
            switch item.action {
            case .fileAction(let action):
                action.run(selectedURLs)
            case .convert(let target):
                JobRunner.shared.convert(selectedURLs, to: target)
            case .tool(let tool):
                DiagnosticLog.log("open tool \(tool.rawValue)")
                ToolWindowManager.shared.open(tool, files: selectedURLs)
            }
        }
    }

    func highlight(_ index: Int) {
        panel?.radialView.highlight(index)
    }

    func hide(returningFocus: Bool = true) {
        let previous = returnFocusTo
        returnFocusTo = nil
        holdingShift = false
        visible = false
        Task { @MainActor in JobRunner.shared.endWatching() }
        pickerMode = false
        panel?.radialView.clearHighlight()
        panel?.radialView.interactive = false
        panel?.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if returningFocus, let previous, previous != NSRunningApplication.current {
            previous.activate()
        }
    }

    private func installOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }
}

