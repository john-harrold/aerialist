import PDFKit
import AppKit

/// Custom PDFAnnotation that manually draws strikethrough lines through text.
/// Used because PDFKit's built-in .strikeOut doesn't render reliably.
class StrikeOutAnnotation: PDFAnnotation {
    let markupID: UUID
    private let quads: [[QuadPoint]]
    private let strikeColor: NSColor

    init(markupID: UUID, bounds: CGRect, quads: [[QuadPoint]], color: NSColor) {
        self.markupID = markupID
        self.quads = quads
        self.strikeColor = color
        super.init(bounds: bounds, forType: .ink, withProperties: nil)
        self.color = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(strikeColor.cgColor)
        context.setLineWidth(1.5)

        for quad in quads {
            guard quad.count == 4 else { continue }
            // Quad points: bottomLeft, bottomRight, topRight, topLeft
            let minY = min(quad[0].y, quad[1].y)
            let maxY = max(quad[2].y, quad[3].y)
            let midY = (minY + maxY) / 2.0
            let leftX = min(quad[0].x, quad[3].x)
            let rightX = max(quad[1].x, quad[2].x)

            context.move(to: CGPoint(x: leftX, y: midY))
            context.addLine(to: CGPoint(x: rightX, y: midY))
            context.strokePath()
        }

        context.restoreGState()
    }
}
