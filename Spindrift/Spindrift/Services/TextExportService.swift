import Foundation
import PDFKit

/// Extracts text from PDF documents and saves as plain text files.
@MainActor
enum TextExportService {

    enum TextExportError: LocalizedError {
        case noDocument
        case failedToOpenPDF(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDocument:
                return "No PDF document to export."
            case .failedToOpenPDF(let path):
                return "Failed to open PDF: \(path)"
            case .writeFailed(let reason):
                return "Text export failed: \(reason)"
            }
        }
    }

    /// Export text from a PDFDocument to a file.
    /// - Parameters:
    ///   - document: The PDF document to extract text from.
    ///   - url: The destination file URL.
    ///   - pages: Optional array of 0-indexed page indices. If nil, all pages are exported.
    static func export(document: PDFDocument, to url: URL, pages: [Int]? = nil) throws {
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw TextExportError.noDocument
        }

        let indices = pages ?? Array(0..<pageCount)
        let text = extractText(from: document, pages: indices)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw TextExportError.writeFailed(error.localizedDescription)
        }
    }

    /// Export text from a PDF file path to a text file.
    /// - Parameters:
    ///   - inputPath: Path to the input PDF.
    ///   - outputPath: Path for the output text file.
    ///   - pages: Optional array of 0-indexed page indices. If nil, all pages are exported.
    static func export(inputPath: String, to outputPath: String, pages: [Int]? = nil) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        guard let document = PDFDocument(url: inputURL) else {
            throw TextExportError.failedToOpenPDF(inputPath)
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try export(document: document, to: outputURL, pages: pages)
    }

    /// Extract text from specified pages of a PDF document.
    private static func extractText(from document: PDFDocument, pages: [Int]) -> String {
        var parts: [String] = []

        for index in pages {
            guard index >= 0, index < document.pageCount,
                  let page = document.page(at: index) else {
                continue
            }

            let pageText = page.string ?? ""
            parts.append("--- Page \(index + 1) ---\n\(pageText)")
        }

        return parts.joined(separator: "\n\n")
    }
}
