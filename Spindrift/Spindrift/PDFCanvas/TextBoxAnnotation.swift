import PDFKit
import AppKit

/// A PDFAnnotation subclass for editable text boxes.
/// These are transient display objects — the sidecar model is the source of truth.
class TextBoxAnnotation: PDFAnnotation {
    let textBoxID: UUID
    var textColor_: NSColor
    var textFont_: NSFont
    var backgroundColor_: NSColor?
    var outlineColor_: NSColor?
    var outlineStyle_: OutlineStyle
    var isSelected_: Bool = false
    var isEditingInline_: Bool = false
    var rotation_: CGFloat = 0 // degrees

    /// The actual text box rect. The annotation's PDFKit `bounds` may be slightly
    /// larger to prevent selection handles from being clipped.
    var logicalBounds_: CGRect

    init(textBoxID: UUID, bounds: CGRect, text: String, fontName: String, fontSize: CGFloat,
         textColor: NSColor, backgroundColor: NSColor?, outlineColor: NSColor?,
         outlineStyle: OutlineStyle, rotation: CGFloat = 0) {
        self.textBoxID = textBoxID
        self.textColor_ = textColor
        self.textFont_ = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        self.backgroundColor_ = backgroundColor
        self.outlineColor_ = outlineColor
        self.outlineStyle_ = outlineStyle
        self.rotation_ = rotation
        self.logicalBounds_ = bounds
        // Expand PDFKit bounds so selection handles and rotation handle aren't clipped
        // Always use 30pt to accommodate the rotation handle (20pt offset + handle radius)
        let expanded = bounds.insetBy(dx: -30, dy: -30)
        super.init(bounds: expanded, forType: .stamp, withProperties: nil)
        self.contents = text
        self.shouldDisplay = true
        self.shouldPrint = true
        self.color = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func update(text: String, fontName: String, fontSize: CGFloat, textColor: NSColor,
                backgroundColor: NSColor?, outlineColor: NSColor?, outlineStyle: OutlineStyle,
                rotation: CGFloat = 0) {
        self.contents = text
        self.textFont_ = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        self.textColor_ = textColor
        self.backgroundColor_ = backgroundColor
        self.outlineColor_ = outlineColor
        self.outlineStyle_ = outlineStyle
        self.rotation_ = rotation
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let rect = logicalBounds_

        context.saveGState()

        // Apply rotation around center
        if rotation_ != 0 {
            let cx = rect.midX, cy = rect.midY
            context.translateBy(x: cx, y: cy)
            context.rotate(by: rotation_ * .pi / 180)
            context.translateBy(x: -cx, y: -cy)
        }

        // Background
        if let bg = backgroundColor_ {
            context.setFillColor(bg.cgColor)
            context.fill(rect)
        }

        // Outline
        if let oc = outlineColor_, outlineStyle_ != .none {
            context.setStrokeColor(oc.cgColor)
            context.setLineWidth(1.5)

            switch outlineStyle_ {
            case .solid:
                break // no dash pattern needed
            case .dashed:
                context.setLineDash(phase: 0, lengths: [6, 3])
            case .dotted:
                context.setLineDash(phase: 0, lengths: [1.5, 3])
            case .none:
                break
            }

            context.stroke(rect)
        }

        // Selection indicator — circle handles at corners and midpoints
        if isSelected_ {
            let handleRadius: CGFloat = 4
            let handles = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.midY),
            ]
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            for handle in handles {
                let handleRect = CGRect(
                    x: handle.x - handleRadius,
                    y: handle.y - handleRadius,
                    width: handleRadius * 2,
                    height: handleRadius * 2
                )
                context.fillEllipse(in: handleRect)
                context.strokeEllipse(in: handleRect)
            }

            // Rotation handle — green circle 20pt above top-center, connected by dashed line
            let rotateY = rect.maxY + 20
            let rotateCenter = CGPoint(x: rect.midX, y: rotateY)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            context.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.addLine(to: rotateCenter)
            context.strokePath()

            let rotateHandleRect = CGRect(
                x: rotateCenter.x - handleRadius,
                y: rotateCenter.y - handleRadius,
                width: handleRadius * 2,
                height: handleRadius * 2
            )
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor.systemGreen.cgColor)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.fillEllipse(in: rotateHandleRect)
            context.strokeEllipse(in: rotateHandleRect)
        }

        // Draw text inside the rotated context (before restoreGState)
        if !isEditingInline_ {
            let text = (contents ?? "") as NSString
            if !text.isEqual(to: "") || isSelected_ {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: textFont_,
                    .foregroundColor: textColor_,
                    .paragraphStyle: paragraphStyle
                ]
                let textRect = rect.insetBy(dx: 4, dy: 2)

                NSGraphicsContext.saveGraphicsState()
                let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
                NSGraphicsContext.current = nsContext

                context.saveGState()
                context.translateBy(x: textRect.origin.x, y: textRect.origin.y + textRect.height)
                context.scaleBy(x: 1, y: -1)
                let drawRect = CGRect(origin: .zero, size: textRect.size)
                text.draw(in: drawRect, withAttributes: attrs)
                context.restoreGState()

                NSGraphicsContext.restoreGraphicsState()
            }
        }

        context.restoreGState()
    }
}
