import PDFKit
import AppKit

@MainActor
enum ImageToPDFService {

    /// Convert an image file at the given URL into a single PDFPage.
    static func createPDFPage(from imageURL: URL) -> PDFPage? {
        guard let image = NSImage(contentsOf: imageURL) else { return nil }
        return createPDFPage(from: image)
    }

    /// Convert an NSImage into a single PDFPage.
    static func createPDFPage(from image: NSImage) -> PDFPage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Scale to fit letter size (612 x 792 points) while maintaining aspect ratio
        let maxWidth: CGFloat = 612
        let maxHeight: CGFloat = 792
        let scale = min(maxWidth / width, maxHeight / height, 1.0)
        let scaledWidth = width * scale
        let scaledHeight = height * scale

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)
        context.draw(cgImage, in: mediaBox)
        context.endPDFPage()
        context.closePDF()

        guard let pdfDoc = PDFDocument(data: data as Data),
              let page = pdfDoc.page(at: 0) else { return nil }

        return page
    }
}
