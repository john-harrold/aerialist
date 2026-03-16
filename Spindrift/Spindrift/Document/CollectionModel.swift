import Foundation

struct CollectionModel: Codable, Equatable, Sendable {
    var version: Int = 1
    var entries: [CollectionEntry] = []

    var isEmpty: Bool { entries.isEmpty }
}

struct CollectionEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var fileData: Data
    var originalFileName: String
    var tocTitle: String
    var fileType: String

    init(id: UUID = UUID(), url: URL, tocTitle: String? = nil) throws {
        self.id = id
        self.fileData = try Data(contentsOf: url)
        self.originalFileName = url.lastPathComponent
        self.tocTitle = tocTitle ?? url.deletingPathExtension().lastPathComponent
        self.fileType = url.pathExtension.lowercased()
    }

    var iconName: String {
        switch fileType {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "tiff", "bmp", "gif": return "photo"
        case "docx", "doc": return "doc.text"
        default: return "doc"
        }
    }

    var fileName: String {
        originalFileName
    }
}
