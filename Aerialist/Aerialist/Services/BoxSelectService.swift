import PDFKit
import AppKit

@MainActor
enum BoxSelectService {

    /// Render a rectangular region of a PDF page as vector PDF data.
    /// Preserves full quality of the original document (text, lines, etc.).
    static func renderRegionToPDFData(page: PDFPage, rect: CGRect) -> Data? {
        // Temporarily remove non-printing annotations
        let nonPrintingAnnotations = page.annotations.filter { !$0.shouldPrint }
        for annotation in nonPrintingAnnotations {
            page.removeAnnotation(annotation)
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            for annotation in nonPrintingAnnotations { page.addAnnotation(annotation) }
            return nil
        }

        var mediaBox = CGRect(origin: .zero, size: rect.size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            for annotation in nonPrintingAnnotations { page.addAnnotation(annotation) }
            return nil
        }

        context.beginPDFPage(nil)
        // Translate so the selected rect's origin maps to (0,0)
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        page.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()

        // Re-add non-printing annotations
        for annotation in nonPrintingAnnotations {
            page.addAnnotation(annotation)
        }

        return data as Data
    }

    /// Render a rectangular region of a PDF page to an NSImage.
    /// Temporarily removes non-printing annotations (like the box selection overlay)
    /// so they don't appear in the captured image.
    static func renderRegionToImage(page: PDFPage, rect: CGRect, dpi: CGFloat = 288) -> NSImage? {
        let scale = dpi / 72.0
        let width = Int(rect.width * scale)
        let height = Int(rect.height * scale)

        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
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

        // Temporarily remove non-printing annotations so overlays don't appear in the capture
        let nonPrintingAnnotations = page.annotations.filter { !$0.shouldPrint }
        for annotation in nonPrintingAnnotations {
            page.removeAnnotation(annotation)
        }

        // White background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and translate so the rect's origin maps to (0,0)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)

        page.draw(with: .mediaBox, to: context)

        // Re-add non-printing annotations
        for annotation in nonPrintingAnnotations {
            page.addAnnotation(annotation)
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
