import PDFKit
import AppKit

@MainActor
enum BoxSelectService {

    /// Render a rectangular region of a PDF page as vector PDF data.
    /// The rect is in page coordinates as returned by PDFView.convert(_:to:page).
    static func renderRegionToPDFData(page: PDFPage, rect: CGRect) -> Data? {
        let nonPrintingAnnotations = page.annotations.filter { !$0.shouldPrint }
        for annotation in nonPrintingAnnotations {
            page.removeAnnotation(annotation)
        }

        // Use a temporary crop to extract just the selected region
        let originalCropBox = page.bounds(for: .cropBox)
        page.setBounds(rect, for: .cropBox)

        let tempDoc = PDFDocument()
        if let pageCopy = page.copy() as? PDFPage {
            tempDoc.insert(pageCopy, at: 0)
        }
        let data = tempDoc.dataRepresentation()

        // Restore original crop box
        page.setBounds(originalCropBox, for: .cropBox)

        for annotation in nonPrintingAnnotations {
            page.addAnnotation(annotation)
        }

        return data
    }

    /// Render a rectangular region of a PDF page to an NSImage.
    /// The rect is in page coordinates.
    static func renderRegionToImage(page: PDFPage, rect: CGRect, dpi: CGFloat = 288) -> NSImage? {
        let nonPrintingAnnotations = page.annotations.filter { !$0.shouldPrint }
        for annotation in nonPrintingAnnotations {
            page.removeAnnotation(annotation)
        }

        // Temporarily crop the page to the selection rect
        let originalCropBox = page.bounds(for: .cropBox)
        page.setBounds(rect, for: .cropBox)

        // Use PDFKit's thumbnail which handles rotation correctly
        let scale = dpi / 72.0
        let thumbSize = CGSize(width: rect.width * scale, height: rect.height * scale)
        let image = page.thumbnail(of: thumbSize, for: .cropBox)

        // Restore
        page.setBounds(originalCropBox, for: .cropBox)

        for annotation in nonPrintingAnnotations {
            page.addAnnotation(annotation)
        }

        return image
    }
}
