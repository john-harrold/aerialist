import SwiftUI
import PDFKit

extension DocumentViewModel {

    /// Run OCR on the current page.
    func ocrCurrentPage() async throws {
        guard let pdf = pdfDocument,
              currentPageIndex < pdf.pageCount,
              let page = pdf.page(at: currentPageIndex) else { return }

        let result = try await OCRService.recognizeText(on: page)
        sidecar.ocrResults[String(currentPageIndex)] = result
    }

    /// Run OCR on all pages with cancellation support.
    func ocrAllPages(progress: @escaping @Sendable (Int) -> Void) async throws {
        guard let pdf = pdfDocument else { return }

        for i in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: i) else { continue }
            let result = try await OCRService.recognizeText(on: page)
            sidecar.ocrResults[String(i)] = result
            progress(i)
        }
    }
}
