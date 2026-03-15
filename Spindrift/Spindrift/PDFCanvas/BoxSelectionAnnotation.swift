import PDFKit
import AppKit

/// A PDFAnnotation subclass that draws a dashed orange rectangle for box selection.
/// Always shows 8 resize handles (4 corners + 4 midpoints).
class BoxSelectionAnnotation: PDFAnnotation {

    init(bounds: CGRect) {
        super.init(bounds: bounds, forType: .square, withProperties: nil)
        self.color = NSColor.systemOrange.withAlphaComponent(0.08)
        self.shouldDisplay = true
        self.shouldPrint = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let handleRadius: CGFloat = 4.0

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let rect = bounds.insetBy(dx: 1, dy: 1)

        // Light orange fill
        context.setFillColor(NSColor.systemOrange.withAlphaComponent(0.08).cgColor)
        context.fill(rect)

        // Dashed orange border
        context.setStrokeColor(NSColor.systemOrange.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(rect)

        // 8 resize handles (4 corners + 4 midpoints)
        let r = Self.handleRadius
        let handlePoints = [
            CGPoint(x: rect.minX, y: rect.minY),  // bottom-left
            CGPoint(x: rect.maxX, y: rect.minY),  // bottom-right
            CGPoint(x: rect.minX, y: rect.maxY),  // top-left
            CGPoint(x: rect.maxX, y: rect.maxY),  // top-right
            CGPoint(x: rect.midX, y: rect.minY),  // bottom-mid
            CGPoint(x: rect.midX, y: rect.maxY),  // top-mid
            CGPoint(x: rect.minX, y: rect.midY),  // left-mid
            CGPoint(x: rect.maxX, y: rect.midY),  // right-mid
        ]

        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemOrange.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [])

        for pt in handlePoints {
            let handleRect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            context.fillEllipse(in: handleRect)
            context.strokeEllipse(in: handleRect)
        }
    }
}
