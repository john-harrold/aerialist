import Foundation
import PDFKit

/// Coordinates export operations for documents.
@MainActor
enum ExportService {

    /// Export a document as a flattened PDF to the specified URL.
    static func exportAsPDF(document: SpindriftDocument, to url: URL) throws {
        guard let data = DocumentExporter.exportFlattenedPDF(from: document) else {
            throw ExportError.exportFailed
        }
        try data.write(to: url)
    }

    enum ExportError: LocalizedError {
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .exportFailed:
                return "Failed to export the document as PDF."
            }
        }
    }
}
