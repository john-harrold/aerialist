import PDFKit
import AppKit

@MainActor
enum FileCombinerService {

    /// Combine multiple files (PDFs and images) into a single PDFDocument with bookmarks.
    static func combine(files: [URL]) -> PDFDocument? {
        let combined = PDFDocument()
        let outline = PDFOutline()

        for fileURL in files {
            let startPage = combined.pageCount

            if fileURL.pathExtension.lowercased() == "pdf" {
                guard let pdf = PDFDocument(url: fileURL) else { continue }
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i) {
                        combined.insert(page, at: combined.pageCount)
                    }
                }
            } else {
                // Image file
                if let page = ImageToPDFService.createPDFPage(from: fileURL) {
                    combined.insert(page, at: combined.pageCount)
                }
            }

            // Create bookmark for this source file
            if combined.pageCount > startPage,
               let bookmarkPage = combined.page(at: startPage) {
                let bookmark = PDFOutline()
                bookmark.label = fileURL.deletingPathExtension().lastPathComponent
                bookmark.destination = PDFDestination(page: bookmarkPage, at: .zero)
                outline.insertChild(bookmark, at: outline.numberOfChildren)
            }
        }

        combined.outlineRoot = outline
        return combined.pageCount > 0 ? combined : nil
    }
}
