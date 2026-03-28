import PDFKit
import AppKit

/// Handles hit-testing and interaction for custom annotations on the PDF canvas.
enum InteractionHandler {

    enum HitResult {
        case none
        case stamp(id: UUID, action: StampAction)
        case textBox(id: UUID, action: StampAction)
        case comment(id: UUID)
        case shape(id: UUID, action: StampAction)
    }

    enum StampAction {
        case drag
        case resizeTopLeft
        case resizeTopRight
        case resizeBottomLeft
        case resizeBottomRight
        case resizeTop
        case resizeBottom
        case resizeLeft
        case resizeRight
        case dragLineStart
        case dragLineEnd
        case rotate
    }

    /// The margin around corners/midpoints that counts as a resize handle, in PDF points.
    private static let resizeMargin: CGFloat = 12.0

    /// Hit-test a point (in PDF page coordinates) against all sidecar annotations on the given page.
    static func hitTest(
        point: CGPoint,
        sidecar: SidecarModel,
        pageIndex: Int
    ) -> HitResult {
        // Test comments first (small targets, on top)
        for comment in sidecar.comments.reversed() where comment.pageIndex == pageIndex {
            // Use a slightly expanded hit area for the small comment icon
            let hitBounds = comment.bounds.cgRect.insetBy(dx: -4, dy: -4)
            if hitBounds.contains(point) {
                return .comment(id: comment.id)
            }
        }

        // Test text boxes (with corner + midpoint handles + rotation handle)
        for textBox in sidecar.textBoxes.reversed() where textBox.pageIndex == pageIndex {
            let bounds = textBox.bounds.cgRect

            // Check rotation handle first (above top-center, may be outside bounds)
            let rotHandleCenter = rotationHandlePositionForTextBox(bounds: bounds, rotation: textBox.rotation)
            let distToRot = hypot(point.x - rotHandleCenter.x, point.y - rotHandleCenter.y)
            if distToRot < resizeMargin {
                return .textBox(id: textBox.id, action: .rotate)
            }

            let hitBounds = bounds.insetBy(dx: -resizeMargin, dy: -resizeMargin)
            guard hitBounds.contains(point) else { continue }
            let action = resizeActionForShape(point: point, bounds: bounds)
            return .textBox(id: textBox.id, action: action)
        }

        // Test shapes (with midpoint handles, or endpoint handles for lines)
        for shape in sidecar.shapes.reversed() where shape.pageIndex == pageIndex {
            let isLine = (shape.shapeType == .line || shape.shapeType == .arrow)

            if isLine, let ls = shape.lineStart, let le = shape.lineEnd {
                let start = CGPoint(x: ls.x, y: ls.y)
                let end = CGPoint(x: le.x, y: le.y)
                if let action = hitTestLine(point: point, start: start, end: end) {
                    return .shape(id: shape.id, action: action)
                }
            } else {
                let bounds = shape.bounds.cgRect

                // Check rotation handle first (above top-center, may be outside bounds)
                let rotHandleCenter = rotationHandlePositionForShape(bounds: bounds, rotation: shape.rotation)
                let distToRot = hypot(point.x - rotHandleCenter.x, point.y - rotHandleCenter.y)
                if distToRot < resizeMargin {
                    return .shape(id: shape.id, action: .rotate)
                }

                let hitBounds = bounds.insetBy(dx: -resizeMargin, dy: -resizeMargin)
                guard hitBounds.contains(point) else { continue }
                let action = resizeActionForShape(point: point, bounds: bounds)
                return .shape(id: shape.id, action: action)
            }
        }

        // Test stamps (topmost first, with rotation handle + 8 resize handles)
        for stamp in sidecar.stamps.reversed() where stamp.pageIndex == pageIndex {
            let bounds = stamp.bounds.cgRect

            // Check rotation handle first (above top-center, may be outside bounds)
            let rotHandleCenter = rotationHandlePosition(for: stamp)
            let distToRot = hypot(point.x - rotHandleCenter.x, point.y - rotHandleCenter.y)
            if distToRot < resizeMargin {
                return .stamp(id: stamp.id, action: .rotate)
            }

            let hitBounds = bounds.insetBy(dx: -resizeMargin, dy: -resizeMargin)
            guard hitBounds.contains(point) else { continue }
            let action = resizeActionForShape(point: point, bounds: bounds)
            return .stamp(id: stamp.id, action: action)
        }

        return .none
    }

    /// Compute the rotation handle position for a stamp in page coordinates.
    private static func rotationHandlePosition(for stamp: StampAnnotationModel) -> CGPoint {
        let bounds = stamp.bounds.cgRect
        let cx = bounds.midX
        let cy = bounds.midY
        let topCenterY = bounds.maxY + StampAnnotation.rotationHandleOffset

        if stamp.rotation == 0 {
            return CGPoint(x: cx, y: topCenterY)
        }

        let rad = stamp.rotation * .pi / 180
        let dy = topCenterY - cy
        let rotatedX = -dy * sin(rad) + cx
        let rotatedY = dy * cos(rad) + cy
        return CGPoint(x: rotatedX, y: rotatedY)
    }

    /// Compute the rotation handle position for a text box in page coordinates.
    private static func rotationHandlePositionForTextBox(bounds: CGRect, rotation: CGFloat) -> CGPoint {
        let cx = bounds.midX
        let cy = bounds.midY
        let topCenterY = bounds.maxY + 20 // matches TextBoxAnnotation's handle offset
        let dy = topCenterY - cy
        let rad = rotation * .pi / 180
        let rotatedX = -dy * sin(rad) + cx
        let rotatedY = dy * cos(rad) + cy
        return CGPoint(x: rotatedX, y: rotatedY)
    }

    /// Compute the rotation handle position for a rectangle/ellipse shape in page coordinates.
    private static func rotationHandlePositionForShape(bounds: CGRect, rotation: CGFloat) -> CGPoint {
        let cx = bounds.midX
        let cy = bounds.midY
        let topCenterY = bounds.maxY + ShapeAnnotation.rotationHandleOffset

        if rotation == 0 {
            return CGPoint(x: cx, y: topCenterY)
        }

        let rad = rotation * .pi / 180
        let dy = topCenterY - cy
        let rotatedX = -dy * sin(rad) + cx
        let rotatedY = dy * cos(rad) + cy
        return CGPoint(x: rotatedX, y: rotatedY)
    }

    /// Hit-test for line/arrow shapes: check endpoint proximity, then line-segment proximity.
    private static func hitTestLine(point: CGPoint, start: CGPoint, end: CGPoint) -> StampAction? {
        let m = resizeMargin

        // Check endpoints first
        let dStart = hypot(point.x - start.x, point.y - start.y)
        let dEnd = hypot(point.x - end.x, point.y - end.y)

        if dStart < m { return .dragLineStart }
        if dEnd < m { return .dragLineEnd }

        // Check proximity to the line segment for body-drag
        let lineLen = hypot(end.x - start.x, end.y - start.y)
        guard lineLen > 0.1 else { return nil }

        // Project point onto the line, compute perpendicular distance
        let dx = end.x - start.x
        let dy = end.y - start.y
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (lineLen * lineLen)

        // t must be within [0,1] (on the segment), with a small extension for ease of clicking
        guard t >= -0.05 && t <= 1.05 else { return nil }

        let projX = start.x + t * dx
        let projY = start.y + t * dy
        let dist = hypot(point.x - projX, point.y - projY)

        if dist < m { return .drag }
        return nil
    }

    /// Hit-test for a rect's resize handles (public for table box resize).
    static func resizeActionForRect(point: CGPoint, bounds: CGRect) -> StampAction {
        return resizeActionForShape(point: point, bounds: bounds)
    }

    /// Hit-test for shapes (corners + midpoint handles).
    private static func resizeActionForShape(point: CGPoint, bounds: CGRect) -> StampAction {
        let m = resizeMargin
        let nearLeft = abs(point.x - bounds.minX) < m
        let nearRight = abs(point.x - bounds.maxX) < m
        let nearBottom = abs(point.y - bounds.minY) < m
        let nearTop = abs(point.y - bounds.maxY) < m

        // Corners first (priority)
        if nearLeft && nearBottom { return .resizeBottomLeft }
        if nearRight && nearBottom { return .resizeBottomRight }
        if nearLeft && nearTop { return .resizeTopLeft }
        if nearRight && nearTop { return .resizeTopRight }

        // Midpoints
        let nearMidX = abs(point.x - bounds.midX) < m
        let nearMidY = abs(point.y - bounds.midY) < m

        if nearTop && nearMidX { return .resizeTop }
        if nearBottom && nearMidX { return .resizeBottom }
        if nearLeft && nearMidY { return .resizeLeft }
        if nearRight && nearMidY { return .resizeRight }

        return .drag
    }
}
