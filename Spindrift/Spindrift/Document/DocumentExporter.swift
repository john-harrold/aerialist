import Foundation
import PDFKit
import AppKit

/// Flattens all sidecar annotations into a standard PDF file.
@MainActor
enum DocumentExporter {

    static func exportFlattenedPDF(from document: SpindriftDocument) -> Data? {
        guard let pdfData = document.pdfDocument.dataRepresentation(),
              let pdfDoc = PDFDocument(data: pdfData) else {
            return nil
        }

        let sidecar = document.sidecar

        // Render stamps onto pages
        for stamp in sidecar.stamps {
            guard stamp.pageIndex < pdfDoc.pageCount,
                  let page = pdfDoc.page(at: stamp.pageIndex),
                  let imageData = Data(base64Encoded: stamp.imageData),
                  let image = NSImage(data: imageData) else { continue }

            let annotation = PDFAnnotation(bounds: stamp.bounds.cgRect, forType: .stamp, withProperties: nil)
            annotation.shouldDisplay = true

            let stampAnnotation = ImageStampAnnotation(
                bounds: stamp.bounds.cgRect,
                image: image,
                opacity: stamp.opacity
            )
            page.addAnnotation(stampAnnotation)
        }

        // Render text boxes
        for textBox in sidecar.textBoxes {
            guard textBox.pageIndex < pdfDoc.pageCount,
                  let page = pdfDoc.page(at: textBox.pageIndex) else { continue }

            let annotation = PDFAnnotation(bounds: textBox.bounds.cgRect, forType: .freeText, withProperties: nil)
            annotation.contents = textBox.text
            annotation.font = NSFont(name: textBox.fontName, size: textBox.fontSize) ?? .systemFont(ofSize: textBox.fontSize)
            annotation.fontColor = NSColor(hex: textBox.color) ?? .black
            annotation.color = .clear
            page.addAnnotation(annotation)
        }

        // Render comments
        for comment in sidecar.comments {
            guard comment.pageIndex < pdfDoc.pageCount,
                  let page = pdfDoc.page(at: comment.pageIndex) else { continue }

            let annotation = PDFAnnotation(bounds: comment.bounds.cgRect, forType: .text, withProperties: nil)
            annotation.contents = comment.text
            annotation.userName = comment.author
            page.addAnnotation(annotation)
        }

        // Render markups
        for markup in sidecar.markups {
            guard markup.pageIndex < pdfDoc.pageCount,
                  let page = pdfDoc.page(at: markup.pageIndex) else { continue }

            let annotationType: PDFAnnotationSubtype
            switch markup.type {
            case .highlight: annotationType = .highlight
            case .underline: annotationType = .underline
            case .strikeOut: annotationType = .strikeOut
            }

            // Calculate bounding rect from all quad points
            let allPoints = markup.quadrilateralPoints.flatMap { $0 }
            guard !allPoints.isEmpty else { continue }
            let xs = allPoints.map(\.x)
            let ys = allPoints.map(\.y)
            let bounds = CGRect(
                x: xs.min()!, y: ys.min()!,
                width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
            )

            let annotation = PDFAnnotation(bounds: bounds, forType: annotationType, withProperties: nil)
            annotation.color = NSColor(hex: markup.color) ?? .yellow

            // Set quadrilateral points
            let quadPoints = markup.quadrilateralPoints.map { quad in
                quad.map { NSValue(point: NSPoint(x: $0.x, y: $0.y)) }
            }
            annotation.setValue(quadPoints, forAnnotationKey: .quadPoints)

            page.addAnnotation(annotation)
        }

        // Render shapes
        for shape in sidecar.shapes {
            guard shape.pageIndex < pdfDoc.pageCount,
                  let page = pdfDoc.page(at: shape.pageIndex) else { continue }

            let strokeColor = NSColor(hex: shape.strokeColor) ?? .black
            let fillColor = shape.fillColor.flatMap { NSColor(hex: $0) }

            let lineStart = shape.lineStart.map { CGPoint(x: $0.x, y: $0.y) }
            let lineEnd = shape.lineEnd.map { CGPoint(x: $0.x, y: $0.y) }

            let annotation = ShapeAnnotation(
                shapeID: shape.id,
                bounds: shape.bounds.cgRect,
                shapeType: shape.shapeType,
                strokeColor: strokeColor,
                fillColor: fillColor,
                strokeWidth: shape.strokeWidth,
                strokeStyle: shape.strokeStyle,
                rotation: shape.rotation,
                lineStart: lineStart,
                lineEnd: lineEnd
            )
            page.addAnnotation(annotation)
        }

        // Render OCR invisible text
        for (pageIndexStr, ocrResult) in sidecar.ocrResults {
            guard let pageIndex = Int(pageIndexStr),
                  pageIndex < pdfDoc.pageCount,
                  let page = pdfDoc.page(at: pageIndex) else { continue }

            for line in ocrResult.lines {
                let annotation = PDFAnnotation(bounds: line.boundingBox.cgRect, forType: .freeText, withProperties: nil)
                annotation.contents = line.text
                annotation.font = NSFont.systemFont(ofSize: max(line.boundingBox.height * 0.8, 1))
                annotation.fontColor = .clear
                annotation.color = .clear
                page.addAnnotation(annotation)
            }
        }

        return pdfDoc.dataRepresentation()
    }
}

// MARK: - Helper: Image Stamp Annotation for Export

private class ImageStampAnnotation: PDFAnnotation {
    let image: NSImage
    let stampOpacity: CGFloat

    init(bounds: CGRect, image: NSImage, opacity: CGFloat) {
        self.image = image
        self.stampOpacity = opacity
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.setAlpha(stampOpacity)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: bounds)
        }
        context.restoreGState()
    }
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        if hexString.count == 8, let value = UInt64(hexString, radix: 16) {
            let r = CGFloat((value >> 24) & 0xFF) / 255.0
            let g = CGFloat((value >> 16) & 0xFF) / 255.0
            let b = CGFloat((value >> 8) & 0xFF) / 255.0
            let a = CGFloat(value & 0xFF) / 255.0
            self.init(srgbRed: r, green: g, blue: b, alpha: a)
        } else if hexString.count == 6, let value = UInt64(hexString, radix: 16) {
            let r = CGFloat((value >> 16) & 0xFF) / 255.0
            let g = CGFloat((value >> 8) & 0xFF) / 255.0
            let b = CGFloat(value & 0xFF) / 255.0
            self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
        } else {
            return nil
        }
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = Int(c.alphaComponent * 255)
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
