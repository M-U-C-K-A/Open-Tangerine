import AppKit

/// Finder's Services menu (right-click a file → Services, or Quick Actions): opens the
/// wheel on the selected files, for people who would rather not drag.
final class FinderServices: NSObject {
    private let radial: RadialController

    init(radial: RadialController) {
        self.radial = radial
    }

    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(pasteboard, error: error) { self.radial.presentPicker(for: $0) }
    }

    @objc func openTools(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(pasteboard, error: error) { self.radial.presentPicker(for: $0, advanced: true) }
    }

    @objc func fileActions(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(pasteboard, error: error) { self.radial.presentPicker(for: $0, actions: true) }
    }

    private func open(_ pasteboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString>, present: @escaping ([URL]) -> Void) {
        let urls = DragMonitor.fileURLs(on: pasteboard)
        guard !urls.isEmpty else {
            error.pointee = "No files to open." as NSString
            return
        }
        DispatchQueue.main.async { present(urls) }
    }
}
