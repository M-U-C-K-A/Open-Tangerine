import PDFKit
import SwiftUI

/// Add a password to PDFs, or remove one you know.
@MainActor
struct PDFPasswordToolView: View {
    let session: ToolSession
    @State private var password = ""
    @State private var confirmation = ""
    @State private var ownerPassword = ""

    private var protecting: Bool { session.tool == .protectPDF }

    private var locked: [URL] {
        session.files.filter { PDFDocument(url: $0)?.isLocked == true }
    }

    private var ready: Bool {
        protecting ? !password.isEmpty && password == confirmation : !password.isEmpty || locked.isEmpty
    }

    var body: some View {
        FormShell(session: session, saveTitle: protecting ? "Protect" : "Remove password", saveEnabled: ready, onSave: save) {
            if protecting {
                FormRow(title: "Password") {
                    SecureField("Needed to open", text: $password).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                FormRow(title: "Again") {
                    SecureField("Same password", text: $confirmation).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                if !confirmation.isEmpty, password != confirmation {
                    Text("The two passwords differ.").font(.callout).foregroundStyle(.red)
                }
                FormRow(title: "Owner password") {
                    SecureField("Optional", text: $ownerPassword).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                FormHint("The owner password guards printing and editing rights. Left empty, it is the same as the password. Keep the password somewhere safe: without it the copy can't be opened.")
            } else {
                if locked.isEmpty {
                    FormHint("\(session.files.count == 1 ? "This PDF has" : "These PDFs have") no password to open. The copy drops any owner restrictions.")
                } else {
                    FormRow(title: "Password") {
                        SecureField("The one that opens it", text: $password).textFieldStyle(.roundedBorder).frame(width: 220)
                    }
                    FormHint("Only for PDFs you're allowed to open. The copy opens without a password; the original keeps its.")
                }
            }
            FormHint("A copy is saved next to each original, named “\(session.baseName) \(protecting ? "protected" : "unlocked").pdf”.")
        }
    }

    private func save() {
        let password = password, owner = ownerPassword, protecting = protecting
        ToolWindowManager.shared.close(session)
        for source in session.files {
            let destination = ConversionMatrix.uniqueURL(directory: AppSettings.shared.outputLocation.directory(for: source), baseName: ConversionMatrix.strippedBaseName(source.lastPathComponent), suffix: protecting ? "protected" : "unlocked", ext: "pdf")
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { _ in
                if protecting {
                    try PDFOps.protect(source, password: password, ownerPassword: owner, to: destination)
                } else {
                    try PDFOps.unlock(source, password: password, to: destination)
                }
                return [destination]
            }
        }
    }
}
