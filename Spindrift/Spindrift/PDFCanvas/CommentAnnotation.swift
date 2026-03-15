import PDFKit
import AppKit

/// Custom PDFAnnotation subclass for comments that supports visual highlighting when selected.
class CommentAnnotation: PDFAnnotation {
    let commentID: UUID
    var isSelected: Bool = false

    init(commentID: UUID, bounds: CGRect) {
        self.commentID = commentID
        super.init(bounds: bounds, forType: .text, withProperties: nil)
        self.color = .yellow
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Draw the standard comment icon first
        super.draw(with: box, in: context)

        // Draw highlight ring around the icon when selected
        if isSelected {
            context.saveGState()
            let highlightRect = bounds.insetBy(dx: -3, dy: -3)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2.5)
            context.strokeEllipse(in: highlightRect)

            // Subtle blue fill for extra visibility
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
            context.fillEllipse(in: highlightRect)
            context.restoreGState()
        }
    }
}
