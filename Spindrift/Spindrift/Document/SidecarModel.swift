import Foundation
import CoreGraphics

// MARK: - Root Sidecar

struct SidecarModel: Codable, Equatable, Sendable {
    var version: Int = 2
    var sourceFileHash: String = ""
    var stamps: [StampAnnotationModel] = []
    var textBoxes: [TextBoxAnnotationModel] = []
    var comments: [CommentAnnotationModel] = []
    var markups: [MarkupAnnotationModel] = []
    var shapes: [ShapeAnnotationModel] = []
    var drawOrder: [UUID] = []  // z-order for stamps, textBoxes, shapes (front = last)
    var ocrResults: [String: OCRPageResult] = [:]
    var formFieldOverrides: [String: String] = [:]

    var isEmpty: Bool {
        stamps.isEmpty && textBoxes.isEmpty && comments.isEmpty &&
        markups.isEmpty && shapes.isEmpty && ocrResults.isEmpty && formFieldOverrides.isEmpty
    }
}

// MARK: - Bounds

struct AnnotationBounds: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
}

// MARK: - Stamp

struct StampAnnotationModel: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: AnnotationBounds
    var imageData: String // base64-encoded PNG
    var opacity: CGFloat
    var rotation: CGFloat // degrees

    init(id: UUID = UUID(), pageIndex: Int, bounds: AnnotationBounds, imageData: String,
         opacity: CGFloat = 1.0, rotation: CGFloat = 0) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.imageData = imageData
        self.opacity = opacity
        self.rotation = rotation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        bounds = try container.decode(AnnotationBounds.self, forKey: .bounds)
        imageData = try container.decode(String.self, forKey: .imageData)
        opacity = try container.decode(CGFloat.self, forKey: .opacity)
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }
}

// MARK: - Text Box

enum OutlineStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case none = "None"
    case solid = "Solid"
    case dashed = "Dashed"
    case dotted = "Dotted"

    var id: String { rawValue }
}

struct TextBoxAnnotationModel: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: AnnotationBounds
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var color: String // hex color for text
    var backgroundColor: String? // hex color, nil = transparent
    var outlineColor: String? // hex color, nil = no outline
    var outlineStyle: OutlineStyle
    var rotation: CGFloat // degrees

    init(id: UUID = UUID(), pageIndex: Int, bounds: AnnotationBounds, text: String = "Text",
         fontName: String = "Helvetica", fontSize: CGFloat = 14, color: String = "#000000",
         backgroundColor: String? = nil, outlineColor: String? = nil,
         outlineStyle: OutlineStyle = .none, rotation: CGFloat = 0) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.backgroundColor = backgroundColor
        self.outlineColor = outlineColor
        self.outlineStyle = outlineStyle
        self.rotation = rotation
    }

    // Backward-compatible decoding — rotation defaults to 0 if missing
    enum CodingKeys: String, CodingKey {
        case id, pageIndex, bounds, text, fontName, fontSize, color
        case backgroundColor, outlineColor, outlineStyle, rotation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pageIndex = try c.decode(Int.self, forKey: .pageIndex)
        bounds = try c.decode(AnnotationBounds.self, forKey: .bounds)
        text = try c.decode(String.self, forKey: .text)
        fontName = try c.decode(String.self, forKey: .fontName)
        fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        color = try c.decode(String.self, forKey: .color)
        backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
        outlineColor = try c.decodeIfPresent(String.self, forKey: .outlineColor)
        outlineStyle = try c.decode(OutlineStyle.self, forKey: .outlineStyle)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }
}

// MARK: - Comment

struct CommentAnnotationModel: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: AnnotationBounds
    var text: String
    var author: String
    var date: Date

    init(id: UUID = UUID(), pageIndex: Int, bounds: AnnotationBounds, text: String = "",
         author: String = NSFullUserName(), date: Date = Date()) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.text = text
        self.author = author
        self.date = date
    }
}

// MARK: - Markup (Highlight, Underline, Strikethrough)

enum MarkupType: String, Codable, Sendable {
    case highlight
    case underline
    case strikeOut
}

struct QuadPoint: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
}

struct MarkupAnnotationModel: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pageIndex: Int
    var type: MarkupType
    var quadrilateralPoints: [[QuadPoint]] // array of quads, each quad = 4 points
    var color: String // hex color

    init(id: UUID = UUID(), pageIndex: Int, type: MarkupType,
         quadrilateralPoints: [[QuadPoint]], color: String = "#FFFF00") {
        self.id = id
        self.pageIndex = pageIndex
        self.type = type
        self.quadrilateralPoints = quadrilateralPoints
        self.color = color
    }
}

// MARK: - Shape

enum ShapeType: String, Codable, Sendable, CaseIterable, Identifiable {
    case line = "Line"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        }
    }

    var tooltip: String {
        switch self {
        case .line: return "Draw a straight line"
        case .arrow: return "Draw an arrow"
        case .rectangle: return "Draw a rectangle"
        case .ellipse: return "Draw an ellipse"
        }
    }
}

struct ShapeAnnotationModel: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: AnnotationBounds
    var shapeType: ShapeType
    var strokeColor: String        // hex
    var fillColor: String?         // hex, nil = no fill
    var strokeWidth: CGFloat       // default 2.0
    var strokeStyle: OutlineStyle   // reuse existing enum
    var rotation: CGFloat          // degrees, default 0
    var lineStart: QuadPoint?      // for line/arrow only — start endpoint in page coords
    var lineEnd: QuadPoint?        // for line/arrow only — end endpoint in page coords

    init(id: UUID = UUID(), pageIndex: Int, bounds: AnnotationBounds,
         shapeType: ShapeType = .rectangle, strokeColor: String = "#000000",
         fillColor: String? = nil, strokeWidth: CGFloat = 2.0,
         strokeStyle: OutlineStyle = .solid, rotation: CGFloat = 0,
         lineStart: QuadPoint? = nil, lineEnd: QuadPoint? = nil) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.shapeType = shapeType
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.strokeStyle = strokeStyle
        self.rotation = rotation
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}

// MARK: - OCR

struct OCRLineResult: Codable, Equatable, Sendable {
    var text: String
    var boundingBox: AnnotationBounds
    var confidence: Float
}

struct OCRPageResult: Codable, Equatable, Sendable {
    var lines: [OCRLineResult]
}
