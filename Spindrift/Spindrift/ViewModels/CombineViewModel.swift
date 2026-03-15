import SwiftUI
import PDFKit

extension DocumentViewModel {

    /// Save a combined PDF to a new file via Save As dialog, then open it.
    func applyCombinedDocument(_ combinedPDF: PDFDocument) {
        guard let pdfData = combinedPDF.dataRepresentation() else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Combined.pdf"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try pdfData.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                // Surface error to user via alert
                Task { @MainActor in
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }
}
