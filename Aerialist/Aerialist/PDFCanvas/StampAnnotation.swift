import PDFKit
import AppKit

/// A PDFAnnotation subclass that renders a stamp image with rotation support.
/// These are transient display objects — the sidecar model is the source of truth.
///
/// Like ShapeAnnotation, rotation is handled by expanding the annotation's PDFKit
/// `bounds` to contain the fully rotated stamp, then drawing at the logical rect.
class StampAnnotation: PDFAnnotation {
    let stampID: UUID
    let image: NSImage
    var stampOpacity: CGFloat
    var rotation_: CGFloat  // degrees
    var isSelected_: Bool = false

    /// The actual stamp rect. PDFKit `bounds` may be larger to accommodate rotation.
    var logicalBounds_: CGRect

    /// Distance from the top-center of the stamp to the rotation handle, in points.
    static let rotationHandleOffset: CGFloat = 20

    init(stampID: UUID, bounds: CGRect, image: NSImage, opacity: CGFloat = 1.0, rotation: CGFloat = 0) {
        self.stampID = stampID
        self.image = image
        self.stampOpacity = opacity
        self.rotation_ = rotation
        self.logicalBounds_ = bounds
        let expanded = Self.expandedBounds(for: bounds, rotation: rotation)
        super.init(bounds: expanded, forType: .stamp, withProperties: nil)
        self.shouldDisplay = true
        self.shouldPrint = true
        self.color = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func setLogicalBounds(_ rect: CGRect) {
        logicalBounds_ = rect
        bounds = Self.expandedBounds(for: rect, rotation: rotation_)
    }

    func recomputeBounds() {
        bounds = Self.expandedBounds(for: logicalBounds_, rotation: rotation_)
    }

    /// Compute expanded PDFKit bounds to contain the rotated stamp plus handles.
    static func expandedBounds(for rect: CGRect, rotation: CGFloat) -> CGRect {
        let margin: CGFloat = max(6, rotationHandleOffset + 6)
        guard rotation != 0 else {
            return rect.insetBy(dx: -margin, dy: -margin)
        }

        let rad = rotation * .pi / 180
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        let w = rect.width + margin * 2
        let h = rect.height + margin * 2
        let expandedW = w * cosA + h * sinA
        let expandedH = w * sinA + h * cosA
        let cx = rect.midX
        let cy = rect.midY
        return CGRect(x: cx - expandedW / 2, y: cy - expandedH / 2,
                      width: expandedW, height: expandedH)
    }

    /// The position of the rotation handle in page coordinates (above top-center).
    var rotationHandleCenter: CGPoint {
        let cx = logicalBounds_.midX
        let cy = logicalBounds_.midY
        let topCenterY = logicalBounds_.maxY + Self.rotationHandleOffset

        if rotation_ == 0 {
            return CGPoint(x: cx, y: topCenterY)
        }

        let rad = rotation_ * .pi / 180
        let dx = cx - cx  // 0
        let dy = topCenterY - cy
        let rotatedX = dx * cos(rad) - dy * sin(rad) + cx
        let rotatedY = dx * sin(rad) + dy * cos(rad) + cy
        return CGPoint(x: rotatedX, y: rotatedY)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        let shapeRect = logicalBounds_

        // Apply rotation around logical bounds center
        if rotation_ != 0 {
            let cx = shapeRect.midX
            let cy = shapeRect.midY
            context.translateBy(x: cx, y: cy)
            context.rotate(by: rotation_ * .pi / 180)
            context.translateBy(x: -cx, y: -cy)
        }

        // Draw the stamp image
        context.setAlpha(stampOpacity)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: shapeRect)
        }
        context.setAlpha(1.0)

        // Selection handles
        if isSelected_ {
            let handleRadius: CGFloat = 4

            // 8 handles: corners + midpoints
            let handles: [CGPoint] = [
                CGPoint(x: shapeRect.minX, y: shapeRect.minY),
                CGPoint(x: shapeRect.maxX, y: shapeRect.minY),
                CGPoint(x: shapeRect.minX, y: shapeRect.maxY),
                CGPoint(x: shapeRect.maxX, y: shapeRect.maxY),
                CGPoint(x: shapeRect.midX, y: shapeRect.minY),
                CGPoint(x: shapeRect.midX, y: shapeRect.maxY),
                CGPoint(x: shapeRect.minX, y: shapeRect.midY),
                CGPoint(x: shapeRect.maxX, y: shapeRect.midY),
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

            // Rotation handle: line from top-center to handle circle
            let topCenter = CGPoint(x: shapeRect.midX, y: shapeRect.maxY)
            let rotHandlePos = CGPoint(x: shapeRect.midX, y: shapeRect.maxY + Self.rotationHandleOffset)

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [2, 2])
            context.move(to: topCenter)
            context.addLine(to: rotHandlePos)
            context.strokePath()

            // Rotation handle circle (slightly larger, green)
            let rotRadius: CGFloat = 5
            let rotRect = CGRect(
                x: rotHandlePos.x - rotRadius,
                y: rotHandlePos.y - rotRadius,
                width: rotRadius * 2,
                height: rotRadius * 2
            )
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor.systemGreen.cgColor)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.fillEllipse(in: rotRect)
            context.strokeEllipse(in: rotRect)
        }

        context.restoreGState()
    }
}
