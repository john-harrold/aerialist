import PDFKit
import AppKit

/// A PDFAnnotation subclass that renders shapes (line, arrow, rectangle, ellipse).
/// These are transient display objects — the sidecar model is the source of truth.
///
/// Rotation is handled by expanding the annotation's PDFKit `bounds` to contain
/// the fully rotated shape, then drawing the shape at its logical rect within
/// that expanded area. This prevents PDFKit from clipping the rotated content.
class ShapeAnnotation: PDFAnnotation {
    let shapeID: UUID
    var shapeType: ShapeType
    var strokeColor_: NSColor
    var fillColor_: NSColor?
    var strokeWidth_: CGFloat
    var strokeStyle_: OutlineStyle
    var rotation_: CGFloat  // degrees
    var isSelected_: Bool = false

    /// The actual shape rect (what the user drew). The annotation's PDFKit `bounds`
    /// may be larger to accommodate rotation without clipping.
    var logicalBounds_: CGRect

    /// Distance from the top-center of the shape to the rotation handle, in points.
    static let rotationHandleOffset: CGFloat = 20

    /// For line/arrow shapes — free endpoints in page coordinates.
    var lineStart_: CGPoint?
    var lineEnd_: CGPoint?

    init(shapeID: UUID, bounds: CGRect, shapeType: ShapeType,
         strokeColor: NSColor, fillColor: NSColor?,
         strokeWidth: CGFloat, strokeStyle: OutlineStyle,
         rotation: CGFloat,
         lineStart: CGPoint? = nil, lineEnd: CGPoint? = nil) {
        self.shapeID = shapeID
        self.shapeType = shapeType
        self.strokeColor_ = strokeColor
        self.fillColor_ = fillColor
        self.strokeWidth_ = strokeWidth
        self.strokeStyle_ = strokeStyle
        self.rotation_ = rotation
        self.lineStart_ = lineStart
        self.lineEnd_ = lineEnd
        self.logicalBounds_ = bounds
        let expanded = Self.expandedBounds(for: bounds, rotation: rotation, strokeWidth: strokeWidth)
        super.init(bounds: expanded, forType: .stamp, withProperties: nil)
        self.shouldDisplay = true
        self.shouldPrint = true
        self.color = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func update(shapeType: ShapeType, strokeColor: NSColor, fillColor: NSColor?,
                strokeWidth: CGFloat, strokeStyle: OutlineStyle, rotation: CGFloat,
                lineStart: CGPoint? = nil, lineEnd: CGPoint? = nil) {
        self.shapeType = shapeType
        self.strokeColor_ = strokeColor
        self.fillColor_ = fillColor
        self.strokeWidth_ = strokeWidth
        self.strokeStyle_ = strokeStyle
        self.rotation_ = rotation
        self.lineStart_ = lineStart
        self.lineEnd_ = lineEnd
    }

    /// Update the logical bounds and recompute the expanded PDFKit bounds for rotation.
    func setLogicalBounds(_ rect: CGRect) {
        logicalBounds_ = rect
        bounds = Self.expandedBounds(for: rect, rotation: rotation_, strokeWidth: strokeWidth_)
    }

    /// Update both line endpoints and recompute logical bounds from their bounding rect.
    func setLineEndpoints(_ start: CGPoint, _ end: CGPoint) {
        lineStart_ = start
        lineEnd_ = end
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        logicalBounds_ = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        bounds = Self.expandedBounds(for: logicalBounds_, rotation: rotation_, strokeWidth: strokeWidth_)
    }

    /// Recompute PDFKit bounds from current logical bounds and rotation.
    func recomputeBounds() {
        bounds = Self.expandedBounds(for: logicalBounds_, rotation: rotation_, strokeWidth: strokeWidth_)
    }

    /// The position of the rotation handle in page coordinates (above top-center).
    /// Only meaningful for rectangle/ellipse shapes.
    var rotationHandleCenter: CGPoint {
        let cx = logicalBounds_.midX
        let cy = logicalBounds_.midY
        let topCenterY = logicalBounds_.maxY + Self.rotationHandleOffset

        if rotation_ == 0 {
            return CGPoint(x: cx, y: topCenterY)
        }

        let rad = rotation_ * .pi / 180
        let dy = topCenterY - cy
        let rotatedX = -dy * sin(rad) + cx
        let rotatedY = dy * cos(rad) + cy
        return CGPoint(x: rotatedX, y: rotatedY)
    }

    /// Compute the PDFKit annotation bounds needed to contain a shape rect at a given rotation.
    /// Uses enough margin to accommodate selection handles and the rotation handle.
    static func expandedBounds(for rect: CGRect, rotation: CGFloat, strokeWidth: CGFloat) -> CGRect {
        let margin = max(strokeWidth, max(6, rotationHandleOffset + 6))
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

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        let shapeRect = logicalBounds_
        let isLine = (shapeType == .line || shapeType == .arrow)

        // Apply rotation around logical bounds center (not used for free-endpoint lines)
        if rotation_ != 0 && !isLine {
            let cx = shapeRect.midX
            let cy = shapeRect.midY
            context.translateBy(x: cx, y: cy)
            context.rotate(by: rotation_ * .pi / 180)
            context.translateBy(x: -cx, y: -cy)
        }

        // Inset for stroke so it doesn't extend beyond logical bounds
        let halfStroke = strokeWidth_ / 2
        let drawRect = shapeRect.insetBy(dx: halfStroke, dy: halfStroke)

        // Set stroke properties
        if strokeStyle_ != .none {
            context.setStrokeColor(strokeColor_.cgColor)
            context.setLineWidth(strokeWidth_)

            switch strokeStyle_ {
            case .solid:
                context.setLineDash(phase: 0, lengths: [])
            case .dashed:
                context.setLineDash(phase: 0, lengths: [6, 3])
            case .dotted:
                context.setLineDash(phase: 0, lengths: [1.5, 3])
            case .none:
                break
            }
        }

        switch shapeType {
        case .rectangle:
            if let fc = fillColor_ {
                context.setFillColor(fc.cgColor)
                context.fill(drawRect)
            }
            if strokeStyle_ != .none {
                context.stroke(drawRect)
            }

        case .ellipse:
            if let fc = fillColor_ {
                context.setFillColor(fc.cgColor)
                context.fillEllipse(in: drawRect)
            }
            if strokeStyle_ != .none {
                context.strokeEllipse(in: drawRect)
            }

        case .line:
            if strokeStyle_ != .none {
                let start = lineStart_ ?? CGPoint(x: drawRect.minX, y: drawRect.minY)
                let end = lineEnd_ ?? CGPoint(x: drawRect.maxX, y: drawRect.maxY)
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
            }

        case .arrow:
            if strokeStyle_ != .none {
                let start = lineStart_ ?? CGPoint(x: drawRect.minX, y: drawRect.minY)
                let end = lineEnd_ ?? CGPoint(x: drawRect.maxX, y: drawRect.maxY)

                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()

                drawArrowhead(in: context, from: start, to: end)
            }
        }

        // Selection indicator
        if isSelected_ {
            let handleRadius: CGFloat = 4
            let handles: [CGPoint]

            if isLine, let ls = lineStart_, let le = lineEnd_ {
                // Line/arrow: only 2 endpoint handles
                handles = [ls, le]
            } else {
                // Rectangle/ellipse: 8 handles (corners + midpoints)
                handles = [
                    CGPoint(x: shapeRect.minX, y: shapeRect.minY),
                    CGPoint(x: shapeRect.maxX, y: shapeRect.minY),
                    CGPoint(x: shapeRect.minX, y: shapeRect.maxY),
                    CGPoint(x: shapeRect.maxX, y: shapeRect.maxY),
                    CGPoint(x: shapeRect.midX, y: shapeRect.minY),
                    CGPoint(x: shapeRect.midX, y: shapeRect.maxY),
                    CGPoint(x: shapeRect.minX, y: shapeRect.midY),
                    CGPoint(x: shapeRect.maxX, y: shapeRect.midY),
                ]
            }

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

            // Rotation handle for rectangle/ellipse (not lines/arrows)
            if !isLine {
                let topCenter = CGPoint(x: shapeRect.midX, y: shapeRect.maxY)
                let rotHandlePos = CGPoint(x: shapeRect.midX, y: shapeRect.maxY + Self.rotationHandleOffset)

                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(1.0)
                context.setLineDash(phase: 0, lengths: [2, 2])
                context.move(to: topCenter)
                context.addLine(to: rotHandlePos)
                context.strokePath()

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
        }

        context.restoreGState()
    }

    private func drawArrowhead(in context: CGContext, from start: CGPoint, to end: CGPoint) {
        let arrowLength: CGFloat = max(10, strokeWidth_ * 4)
        let arrowAngle: CGFloat = .pi / 6

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)

        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        context.setFillColor(strokeColor_.cgColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }
}
