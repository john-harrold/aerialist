import SwiftUI
import PDFKit
import UniformTypeIdentifiers

final class SpindriftDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = DocumentSnapshot

    /// Marker userName on the hidden annotation that stores sidecar JSON.
    static let sidecarMarker = "com.spindrift.sidecar"

    /// Prefix for all Spindrift-managed annotations (comments, stamps, text boxes).
    static let annotationPrefix = "spindrift:"

    var pdfDocument: PDFDocument
    var sidecar: SidecarModel {
        didSet { objectWillChange.send() }
    }

    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    // MARK: - Annotation Tagging

    /// Build a userName tag for a managed annotation: "spindrift:type:UUID"
    static func annotationTag(type: String, id: UUID) -> String {
        "\(annotationPrefix)\(type):\(id.uuidString)"
    }

    /// Parse a userName tag. Returns (type, UUID) or nil if not an Spindrift tag.
    static func parseAnnotationTag(_ userName: String?) -> (type: String, id: UUID)? {
        guard let userName, userName.hasPrefix(annotationPrefix) else { return nil }
        let rest = userName.dropFirst(annotationPrefix.count) // "type:UUID"
        let parts = rest.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let uuid = UUID(uuidString: String(parts[1])) else { return nil }
        return (type: String(parts[0]), id: uuid)
    }

    // MARK: - Init

    /// New empty document
    init() {
        self.pdfDocument = PDFDocument()
        self.sidecar = SidecarModel()
    }

    // MARK: - Reading

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let pdf = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.pdfDocument = pdf

        // Extract sidecar, reconcile with any edits made by external apps, strip managed annotations
        var model = Self.extractSidecar(from: pdf)
        Self.reconcileAndStrip(pdf: pdf, sidecar: &model)
        self.sidecar = model
    }

    // MARK: - Snapshots

    struct DocumentSnapshot: Sendable {
        let pdfData: Data
    }

    func snapshot(contentType: UTType) throws -> DocumentSnapshot {
        // 1. Embed sidecar JSON as hidden annotation
        embedSidecar()

        // 2. Collect all managed custom annotations from pages
        var customAnnotations: [(annotation: PDFAnnotation, pageIndex: Int)] = []
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard Self.parseAnnotationTag(annotation.userName) != nil else { continue }
                customAnnotations.append((annotation, pageIndex))
            }
        }

        // 3. Remove custom annotations from pages
        for (annotation, pageIndex) in customAnnotations {
            pdfDocument.page(at: pageIndex)?.removeAnnotation(annotation)
        }

        // 3b. Remove non-printing overlay annotations (box selection, table selection, etc.)
        var nonPrintingAnnotations: [(annotation: PDFAnnotation, pageIndex: Int)] = []
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            for annotation in page.annotations where !annotation.shouldPrint {
                nonPrintingAnnotations.append((annotation, pageIndex))
            }
        }
        for (annotation, pageIndex) in nonPrintingAnnotations {
            pdfDocument.page(at: pageIndex)?.removeAnnotation(annotation)
        }

        // 4. Create standard PDF annotations from sidecar data
        var standardAnnotations: [(annotation: PDFAnnotation, pageIndex: Int)] = []

        for textBox in sidecar.textBoxes {
            let std = Self.makeStandardFreeText(from: textBox)
            standardAnnotations.append((std, textBox.pageIndex))
        }
        for shape in sidecar.shapes {
            let std = Self.makeStandardShape(from: shape)
            standardAnnotations.append((std, shape.pageIndex))
        }
        for comment in sidecar.comments {
            let std = Self.makeStandardComment(from: comment)
            standardAnnotations.append((std, comment.pageIndex))
        }
        for stamp in sidecar.stamps {
            let std = Self.makeStandardStamp(from: stamp)
            standardAnnotations.append((std, stamp.pageIndex))
        }
        for markup in sidecar.markups {
            if let std = Self.makeStandardMarkup(from: markup) {
                standardAnnotations.append((std, markup.pageIndex))
            }
        }

        // Add standard annotations to pages
        for (annotation, pageIndex) in standardAnnotations {
            pdfDocument.page(at: pageIndex)?.addAnnotation(annotation)
        }

        // 5. Serialize PDF with standard types
        guard let pdfData = pdfDocument.dataRepresentation() else {
            // Restore originals before throwing
            for (annotation, pageIndex) in standardAnnotations {
                pdfDocument.page(at: pageIndex)?.removeAnnotation(annotation)
            }
            for (annotation, pageIndex) in customAnnotations {
                pdfDocument.page(at: pageIndex)?.addAnnotation(annotation)
            }
            for (annotation, pageIndex) in nonPrintingAnnotations {
                pdfDocument.page(at: pageIndex)?.addAnnotation(annotation)
            }
            throw CocoaError(.fileWriteUnknown)
        }

        // 6. Remove standard annotations, restore original custom and non-printing annotations
        for (annotation, pageIndex) in standardAnnotations {
            pdfDocument.page(at: pageIndex)?.removeAnnotation(annotation)
        }
        for (annotation, pageIndex) in customAnnotations {
            pdfDocument.page(at: pageIndex)?.addAnnotation(annotation)
        }
        for (annotation, pageIndex) in nonPrintingAnnotations {
            pdfDocument.page(at: pageIndex)?.addAnnotation(annotation)
        }

        return DocumentSnapshot(pdfData: pdfData)
    }

    // MARK: - Writing

    func fileWrapper(snapshot: DocumentSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: snapshot.pdfData)
    }

    // MARK: - Sidecar Persistence via Hidden Annotation

    /// Extract sidecar JSON from a hidden annotation on page 0.
    private static func extractSidecar(from pdf: PDFDocument) -> SidecarModel {
        guard let page = pdf.page(at: 0) else { return SidecarModel() }

        for annotation in page.annotations {
            if annotation.userName == sidecarMarker,
               let jsonString = annotation.contents,
               let jsonData = jsonString.data(using: .utf8),
               let model = try? SidecarIO.decode(from: jsonData) {
                page.removeAnnotation(annotation)
                return model
            }
        }
        return SidecarModel()
    }

    /// Reconcile external edits (e.g. moved in Preview) and strip all managed annotations from pages.
    /// After this, the PDF pages have no Spindrift-managed annotations — the coordinator recreates them.
    ///
    /// For version-2 sidecars (standard annotation types), reads back property changes from
    /// `.freeText`, `.square`, `.circle`, and `.line` annotations. If a tagged annotation is
    /// missing from all pages, the user deleted it in Preview — remove from sidecar.
    private static func reconcileAndStrip(pdf: PDFDocument, sidecar: inout SidecarModel) {
        // Track which sidecar IDs are found as tagged annotations on pages
        var foundIDs: Set<UUID> = []

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            // Collect annotations to remove (can't mutate while iterating)
            var toRemove: [PDFAnnotation] = []

            for annotation in page.annotations {
                // Remove leftover sidecar carriers
                if annotation.userName == sidecarMarker {
                    toRemove.append(annotation)
                    continue
                }

                // Check if this is a tagged Spindrift annotation (try userName first, then contents as fallback)
                guard let (type, id) = parseAnnotationTag(annotation.userName)
                        ?? parseAnnotationTag(annotation.contents) else { continue }
                foundIDs.insert(id)

                let currentBounds = AnnotationBounds(annotation.bounds)
                let annType = annotation.type ?? ""

                switch type {
                case "comment":
                    if let idx = sidecar.comments.firstIndex(where: { $0.id == id }) {
                        sidecar.comments[idx].bounds = currentBounds
                        sidecar.comments[idx].pageIndex = pageIndex
                        if let text = annotation.contents, !text.isEmpty {
                            sidecar.comments[idx].text = text
                        }
                    }

                case "stamp":
                    if let idx = sidecar.stamps.firstIndex(where: { $0.id == id }) {
                        sidecar.stamps[idx].bounds = currentBounds
                        sidecar.stamps[idx].pageIndex = pageIndex
                    }

                case "textbox":
                    if let idx = sidecar.textBoxes.firstIndex(where: { $0.id == id }) {
                        sidecar.textBoxes[idx].pageIndex = pageIndex

                        if annType == PDFAnnotationSubtype.freeText.rawValue {
                            // Standard .freeText — read back all editable properties
                            sidecar.textBoxes[idx].bounds = currentBounds
                            if let text = annotation.contents {
                                sidecar.textBoxes[idx].text = text
                            }
                            if let font = annotation.font {
                                sidecar.textBoxes[idx].fontName = font.fontName
                                sidecar.textBoxes[idx].fontSize = font.pointSize
                            }
                            if let fc = annotation.fontColor {
                                sidecar.textBoxes[idx].color = fc.hexString
                            }
                            let bg = annotation.color
                            if bg.alphaComponent > 0.01 {
                                sidecar.textBoxes[idx].backgroundColor = bg.hexString
                            } else {
                                sidecar.textBoxes[idx].backgroundColor = nil
                            }
                            if let border = annotation.border {
                                sidecar.textBoxes[idx].outlineStyle = borderStyleToOutlineStyle(border)
                            }
                        } else {
                            // Legacy .stamp type — just read bounds and text
                            sidecar.textBoxes[idx].bounds = currentBounds
                            if let text = annotation.contents {
                                sidecar.textBoxes[idx].text = text
                            }
                        }
                    }

                case "shape":
                    if let idx = sidecar.shapes.firstIndex(where: { $0.id == id }) {
                        sidecar.shapes[idx].pageIndex = pageIndex

                        if annType == PDFAnnotationSubtype.square.rawValue ||
                           annType == PDFAnnotationSubtype.circle.rawValue {
                            // Standard square/circle — read back stroke, fill, border
                            sidecar.shapes[idx].bounds = currentBounds
                            sidecar.shapes[idx].strokeColor = annotation.color.hexString
                            if let fc = annotation.interiorColor, fc.alphaComponent > 0.01 {
                                sidecar.shapes[idx].fillColor = fc.hexString
                            } else {
                                sidecar.shapes[idx].fillColor = nil
                            }
                            if let border = annotation.border {
                                sidecar.shapes[idx].strokeWidth = border.lineWidth
                                sidecar.shapes[idx].strokeStyle = borderStyleToOutlineStyle(border)
                            }
                        } else if annType == PDFAnnotationSubtype.line.rawValue {
                            // Standard line — read back endpoints, stroke, border, arrow
                            let start = annotation.startPoint
                            let end = annotation.endPoint
                            sidecar.shapes[idx].lineStart = QuadPoint(x: start.x, y: start.y)
                            sidecar.shapes[idx].lineEnd = QuadPoint(x: end.x, y: end.y)
                            let minX = min(start.x, end.x)
                            let minY = min(start.y, end.y)
                            let maxX = max(start.x, end.x)
                            let maxY = max(start.y, end.y)
                            sidecar.shapes[idx].bounds = AnnotationBounds(
                                x: minX, y: minY,
                                width: max(maxX - minX, 1), height: max(maxY - minY, 1)
                            )
                            sidecar.shapes[idx].strokeColor = annotation.color.hexString
                            if let border = annotation.border {
                                sidecar.shapes[idx].strokeWidth = border.lineWidth
                                sidecar.shapes[idx].strokeStyle = borderStyleToOutlineStyle(border)
                            }
                            // Detect arrow via endLineStyle
                            if annotation.endLineStyle == .closedArrow ||
                               annotation.endLineStyle == .openArrow {
                                sidecar.shapes[idx].shapeType = .arrow
                            }
                        } else {
                            // Legacy .stamp type — update bounds, translate line endpoints
                            let oldBounds = sidecar.shapes[idx].bounds
                            sidecar.shapes[idx].bounds = currentBounds
                            if let ls = sidecar.shapes[idx].lineStart,
                               let le = sidecar.shapes[idx].lineEnd {
                                let dx = currentBounds.x - oldBounds.x
                                let dy = currentBounds.y - oldBounds.y
                                if dx != 0 || dy != 0 {
                                    sidecar.shapes[idx].lineStart = QuadPoint(x: ls.x + dx, y: ls.y + dy)
                                    sidecar.shapes[idx].lineEnd = QuadPoint(x: le.x + dx, y: le.y + dy)
                                }
                            }
                        }
                    }

                case "markup":
                    // Markups don't change after creation, just ensure they're stripped
                    break

                default:
                    break
                }

                toRemove.append(annotation)
            }

            for annotation in toRemove {
                page.removeAnnotation(annotation)
            }
        }

        // Deletion detection: if version >= 2 and a tagged annotation is missing
        // from all pages, the user deleted it in Preview → remove from sidecar
        if sidecar.version >= 2 {
            sidecar.stamps.removeAll { !foundIDs.contains($0.id) }
            sidecar.textBoxes.removeAll { !foundIDs.contains($0.id) }
            sidecar.comments.removeAll { !foundIDs.contains($0.id) }
            sidecar.shapes.removeAll { !foundIDs.contains($0.id) }
            sidecar.markups.removeAll { !foundIDs.contains($0.id) }
        }
    }

    /// Embed the current sidecar model as a hidden annotation on page 0.
    private func embedSidecar() {
        guard pdfDocument.pageCount > 0,
              let page = pdfDocument.page(at: 0) else { return }

        // Remove any existing sidecar carrier
        for annotation in page.annotations {
            if annotation.userName == Self.sidecarMarker {
                page.removeAnnotation(annotation)
            }
        }

        // Only embed if there's actual data to store
        guard !sidecar.isEmpty else { return }

        guard let jsonData = try? SidecarIO.encode(sidecar),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let annotation = PDFAnnotation(
            bounds: CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = jsonString
        annotation.userName = Self.sidecarMarker
        annotation.color = .clear
        annotation.font = NSFont.systemFont(ofSize: 0.1)
        annotation.isReadOnly = true
        page.addAnnotation(annotation)
    }

    // MARK: - Standard Annotation Factory Methods

    /// Create a standard `.freeText` annotation from a text box model.
    private static func makeStandardFreeText(from model: TextBoxAnnotationModel) -> PDFAnnotation {
        let tag = annotationTag(type: "textbox", id: model.id)
        let annotation = PDFAnnotation(
            bounds: model.bounds.cgRect,
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = model.text
        annotation.font = NSFont(name: model.fontName, size: model.fontSize)
            ?? .systemFont(ofSize: model.fontSize)
        annotation.fontColor = NSColor(hex: model.color) ?? .black

        if let bgHex = model.backgroundColor, let bgColor = NSColor(hex: bgHex) {
            annotation.color = bgColor
        } else {
            annotation.color = .clear
        }

        if model.outlineStyle != .none {
            annotation.border = makeStandardBorder(width: 1.5, style: model.outlineStyle)
        }

        annotation.userName = tag
        return annotation
    }

    /// Dispatch shape model to the appropriate standard annotation type.
    private static func makeStandardShape(from model: ShapeAnnotationModel) -> PDFAnnotation {
        let tag = annotationTag(type: "shape", id: model.id)
        switch model.shapeType {
        case .rectangle:
            return makeStandardSquare(from: model, tag: tag)
        case .ellipse:
            return makeStandardCircle(from: model, tag: tag)
        case .line:
            return makeStandardLine(from: model, tag: tag, isArrow: false)
        case .arrow:
            return makeStandardLine(from: model, tag: tag, isArrow: true)
        }
    }

    /// Create a standard `.square` annotation from a rectangle shape model.
    private static func makeStandardSquare(from model: ShapeAnnotationModel, tag: String) -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: model.bounds.cgRect,
            forType: .square,
            withProperties: nil
        )
        annotation.color = NSColor(hex: model.strokeColor) ?? .black
        if let fillHex = model.fillColor, let fillColor = NSColor(hex: fillHex) {
            annotation.interiorColor = fillColor
        }
        annotation.border = makeStandardBorder(width: model.strokeWidth, style: model.strokeStyle)
        annotation.userName = tag
        return annotation
    }

    /// Create a standard `.circle` annotation from an ellipse shape model.
    private static func makeStandardCircle(from model: ShapeAnnotationModel, tag: String) -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: model.bounds.cgRect,
            forType: .circle,
            withProperties: nil
        )
        annotation.color = NSColor(hex: model.strokeColor) ?? .black
        if let fillHex = model.fillColor, let fillColor = NSColor(hex: fillHex) {
            annotation.interiorColor = fillColor
        }
        annotation.border = makeStandardBorder(width: model.strokeWidth, style: model.strokeStyle)
        annotation.userName = tag
        return annotation
    }

    /// Create a standard `.line` annotation from a line/arrow shape model.
    private static func makeStandardLine(from model: ShapeAnnotationModel, tag: String, isArrow: Bool) -> PDFAnnotation {
        let startPt: CGPoint
        let endPt: CGPoint
        if let ls = model.lineStart, let le = model.lineEnd {
            startPt = CGPoint(x: ls.x, y: ls.y)
            endPt = CGPoint(x: le.x, y: le.y)
        } else {
            startPt = CGPoint(x: model.bounds.x, y: model.bounds.y)
            endPt = CGPoint(x: model.bounds.x + model.bounds.width,
                            y: model.bounds.y + model.bounds.height)
        }

        // Compute bounds from endpoints with stroke padding
        let minX = min(startPt.x, endPt.x)
        let minY = min(startPt.y, endPt.y)
        let maxX = max(startPt.x, endPt.x)
        let maxY = max(startPt.y, endPt.y)
        let padding = model.strokeWidth + 5
        let lineBounds = CGRect(
            x: minX - padding, y: minY - padding,
            width: max(maxX - minX, 1) + padding * 2,
            height: max(maxY - minY, 1) + padding * 2
        )

        let annotation = PDFAnnotation(
            bounds: lineBounds,
            forType: .line,
            withProperties: nil
        )
        annotation.startPoint = startPt
        annotation.endPoint = endPt
        annotation.color = NSColor(hex: model.strokeColor) ?? .black
        annotation.border = makeStandardBorder(width: model.strokeWidth, style: model.strokeStyle)

        if isArrow {
            annotation.endLineStyle = .closedArrow
        }

        annotation.userName = tag
        return annotation
    }

    /// Create a standard `.text` (comment) annotation.
    private static func makeStandardComment(from model: CommentAnnotationModel) -> PDFAnnotation {
        let tag = annotationTag(type: "comment", id: model.id)
        let annotation = PDFAnnotation(
            bounds: model.bounds.cgRect,
            forType: .text,
            withProperties: nil
        )
        annotation.contents = model.text
        annotation.color = .yellow
        annotation.userName = tag
        return annotation
    }

    /// Create a stamp annotation with image drawn via NSImage.draw() for AP stream compatibility.
    private static func makeStandardStamp(from model: StampAnnotationModel) -> PDFAnnotation {
        let tag = annotationTag(type: "stamp", id: model.id)
        guard let imageData = Data(base64Encoded: model.imageData),
              let image = NSImage(data: imageData) else {
            let fallback = PDFAnnotation(bounds: model.bounds.cgRect, forType: .stamp, withProperties: nil)
            fallback.userName = tag
            fallback.contents = tag
            return fallback
        }

        let annotation = SaveStampAnnotation(
            bounds: model.bounds.cgRect,
            image: image,
            opacity: model.opacity,
            rotation: model.rotation
        )
        annotation.userName = tag
        annotation.contents = tag
        return annotation
    }

    /// Create a standard markup annotation (`.highlight`, `.underline`, or `.strikeOut`).
    private static func makeStandardMarkup(from model: MarkupAnnotationModel) -> PDFAnnotation? {
        let bounds = model.boundingRect
        guard !bounds.isEmpty else { return nil }

        let annotation = PDFAnnotation(
            bounds: bounds,
            forType: model.pdfAnnotationSubtype,
            withProperties: nil
        )
        annotation.color = NSColor(hex: model.color) ?? .yellow
        annotation.userName = annotationTag(type: "markup", id: model.id)

        // Set quadrilateral points — flat array of NSValue-wrapped points
        let flatPoints = model.quadrilateralPoints.flatMap { quad -> [NSValue] in
            guard quad.count == 4 else { return [] }
            return quad.map { NSValue(point: NSPoint(x: $0.x, y: $0.y)) }
        }
        annotation.setValue(flatPoints, forAnnotationKey: .quadPoints)

        return annotation
    }

    /// Create a PDFBorder from stroke width and outline style.
    private static func makeStandardBorder(width: CGFloat, style: OutlineStyle) -> PDFBorder {
        let border = PDFBorder()
        border.lineWidth = width
        switch style {
        case .solid, .none:
            border.style = .solid
        case .dashed:
            border.style = .dashed
            border.dashPattern = [6, 3] as [NSNumber]
        case .dotted:
            // PDF has no dotted style; approximate with short dashes
            border.style = .dashed
            border.dashPattern = [1.5, 3.0] as [NSNumber]
        }
        return border
    }

    /// Reverse-map a PDFBorder back to an OutlineStyle.
    private static func borderStyleToOutlineStyle(_ border: PDFBorder) -> OutlineStyle {
        switch border.style {
        case .dashed:
            // Distinguish dotted (short pattern) from dashed
            if let pattern = border.dashPattern as? [NSNumber],
               !pattern.isEmpty,
               pattern[0].doubleValue < 3.0 {
                return .dotted
            }
            return .dashed
        case .solid:
            return .solid
        default:
            return .solid
        }
    }
}

/// Stamp annotation that draws its image via NSImage.draw() so the appearance stream
/// captures the image data properly for Preview and other PDF readers.
private class SaveStampAnnotation: PDFAnnotation {
    let image: NSImage
    let stampOpacity: CGFloat
    let stampRotation: CGFloat

    init(bounds: CGRect, image: NSImage, opacity: CGFloat, rotation: CGFloat) {
        self.image = image
        self.stampOpacity = opacity
        self.stampRotation = rotation
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Use NSImage.draw() via NSGraphicsContext — this gets properly recorded
        // into the PDF appearance stream, unlike CGContext.draw(cgImage:in:)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        if stampRotation != 0 {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX, yBy: bounds.midY)
            transform.rotate(byDegrees: stampRotation)
            transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
            transform.concat()
        }

        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: stampOpacity)

        NSGraphicsContext.restoreGraphicsState()
    }
}

