import Vision
import PDFKit
import AppKit
import CoreText

@MainActor
enum OCRService {

    /// Run OCR on a single PDF page and return recognized text lines.
    static func recognizeText(on page: PDFPage, dpi: CGFloat = 300) async throws -> OCRPageResult {
        let pageBounds = page.bounds(for: .mediaBox)
        let cgImage = renderPageToCGImage(page, dpi: dpi)

        guard let cgImage else {
            return OCRPageResult(lines: [])
        }

        // Run Vision OCR off the main actor
        let lines = try await performOCR(cgImage: cgImage, pageBounds: pageBounds)
        return OCRPageResult(lines: lines)
    }

    /// Run OCR on all pages, reporting progress.
    static func recognizeAllPages(
        in document: PDFDocument,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> [String: OCRPageResult] {
        var results: [String: OCRPageResult] = [:]

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let result = try await recognizeText(on: page)
            results[String(i)] = result
            progress(i)
        }

        return results
    }

    /// Render a PDFPage to a CGImage at the given DPI (must be called on main actor).
    private static func renderPageToCGImage(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = Int(pageBounds.width * scale)
        let height = Int(pageBounds.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBounds.origin.x, y: -pageBounds.origin.y)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    // MARK: - Invisible Text Overlay

    /// Create a new PDF page that contains the original page content plus invisible OCR text
    /// embedded in the content stream. The invisible text is selectable and searchable by PDFKit
    /// but produces no visible rendering (uses PDF text rendering mode 3).
    static func overlayInvisibleText(on page: PDFPage, ocrResult: OCRPageResult) -> PDFPage? {
        let mediaBox = page.bounds(for: .mediaBox)
        guard !ocrResult.lines.isEmpty else { return nil }

        // Create an in-memory PDF with one page
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var pageRect = mediaBox
        guard let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else { return nil }

        context.beginPDFPage(nil)

        // 1) Draw the original page content
        context.saveGState()
        // Translate so the page's mediaBox origin aligns with (0,0)
        context.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        // 2) Draw invisible OCR text
        context.saveGState()
        // Translate for mediaBox origin offset
        context.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
        // Set text rendering mode to invisible (mode 3)
        context.setTextDrawingMode(.invisible)

        for line in ocrResult.lines {
            let box = line.boundingBox.cgRect
            guard box.height > 0, box.width > 0 else { continue }

            // Size the font to match the bounding box height
            let fontSize = box.height * 0.85
            guard fontSize > 0.5 else { continue }

            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font
            ]
            let attrString = NSAttributedString(string: line.text, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attrString)

            // Position at the bottom-left of the bounding box
            context.textPosition = CGPoint(x: box.origin.x, y: box.origin.y)

            // Scale horizontally to fit the text within the bounding box width
            let typoBounds = CTLineGetBoundsWithOptions(ctLine, [])
            if typoBounds.width > 0 {
                let scaleX = box.width / typoBounds.width
                context.saveGState()
                context.translateBy(x: box.origin.x, y: box.origin.y)
                context.scaleBy(x: scaleX, y: 1.0)
                context.textPosition = .zero
                CTLineDraw(ctLine, context)
                context.restoreGState()
            } else {
                CTLineDraw(ctLine, context)
            }
        }

        context.restoreGState()
        context.endPDFPage()
        context.closePDF()

        // Create a PDFDocument from the generated data and return the first page
        guard let newDoc = PDFDocument(data: data as Data),
              let newPage = newDoc.page(at: 0) else { return nil }
        return newPage
    }

    /// Apply invisible OCR text overlays to pages in the document that have OCR results.
    /// - Parameters:
    ///   - document: The PDFDocument to modify in place.
    ///   - ocrResults: The OCR results keyed by page index string.
    ///   - originalPages: A dictionary tracking original (un-overlaid) pages. Pages are stored
    ///     here before overlay so re-running OCR uses the clean original.
    static func applyOCROverlays(
        to document: PDFDocument,
        ocrResults: [String: OCRPageResult],
        originalPages: inout [Int: PDFPage]
    ) {
        for (pageIndexStr, ocrResult) in ocrResults {
            guard let pageIndex = Int(pageIndexStr),
                  pageIndex < document.pageCount else { continue }
            guard !ocrResult.lines.isEmpty else { continue }

            // Use the original page if available (avoids stacking overlays)
            let sourcePage: PDFPage
            if let original = originalPages[pageIndex] {
                sourcePage = original
            } else if let current = document.page(at: pageIndex) {
                // First time — save the current page as the original
                originalPages[pageIndex] = current
                sourcePage = current
            } else {
                continue
            }

            guard let overlaidPage = overlayInvisibleText(on: sourcePage, ocrResult: ocrResult) else {
                continue
            }

            document.removePage(at: pageIndex)
            document.insert(overlaidPage, at: pageIndex)
        }
    }

    /// Perform OCR on a CGImage. This is nonisolated so it can run off the main thread.
    private nonisolated static func performOCR(cgImage: CGImage, pageBounds: CGRect) async throws -> [OCRLineResult] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let lines = observations.compactMap { observation -> OCRLineResult? in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }

                    // Convert normalized Vision coordinates to PDF page coordinates
                    let visionBounds = observation.boundingBox
                    let pdfBounds = AnnotationBounds(
                        x: visionBounds.origin.x * pageBounds.width + pageBounds.origin.x,
                        y: visionBounds.origin.y * pageBounds.height + pageBounds.origin.y,
                        width: visionBounds.width * pageBounds.width,
                        height: visionBounds.height * pageBounds.height
                    )

                    return OCRLineResult(
                        text: topCandidate.string,
                        boundingBox: pdfBounds,
                        confidence: topCandidate.confidence
                    )
                }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
