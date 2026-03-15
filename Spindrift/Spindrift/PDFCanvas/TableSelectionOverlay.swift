import PDFKit
import AppKit

/// A PDFAnnotation subclass that draws a dashed blue rectangle for table selection.
/// Used for both user-drawn selection rectangles and auto-detected table regions.
class TableSelectionAnnotation: PDFAnnotation {

    var isAutoDetected: Bool = false
    var isSelected: Bool = false

    init(bounds: CGRect, isAutoDetected: Bool = false, isSelected: Bool = false) {
        self.isAutoDetected = isAutoDetected
        self.isSelected = isSelected
        super.init(bounds: bounds, forType: .square, withProperties: nil)
        self.color = NSColor.systemBlue.withAlphaComponent(0.15)
        self.shouldDisplay = true
        self.shouldPrint = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Radius of resize handle circles in PDF points.
    private static let handleRadius: CGFloat = 4.0

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let rect = bounds.insetBy(dx: 1, dy: 1)

        // Light blue fill
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(isAutoDetected ? 0.08 : 0.12).cgColor)
        context.fill(rect)

        if isSelected {
            // Solid thicker border for selected state
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(2.5)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(rect)

            // Draw 8 resize handles (4 corners + 4 midpoints)
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
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [])

            for pt in handlePoints {
                let handleRect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                context.fillEllipse(in: handleRect)
                context.strokeEllipse(in: handleRect)
            }
        } else {
            // Dashed blue border
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(isAutoDetected ? 1.5 : 2.0)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(rect)
        }
    }
}
