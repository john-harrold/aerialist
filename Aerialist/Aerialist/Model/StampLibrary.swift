import Foundation
import AppKit
import PDFKit
import ImageIO

struct SavedStamp: Codable, Identifiable {
    var id: UUID
    var name: String
    var filename: String
    var dateAdded: Date
}

@MainActor
@Observable
final class StampLibrary {
    private(set) var stamps: [SavedStamp] = []

    init() {
        load()
    }

    static var stampsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.aerialist.app/stamps", isDirectory: true)
    }

    static var indexURL: URL {
        stampsDirectory.appendingPathComponent("stamps.json")
    }

    func load() {
        let fm = FileManager.default
        let indexURL = Self.indexURL

        guard fm.fileExists(atPath: indexURL.path) else {
            stamps = []
            return
        }

        do {
            let data = try Data(contentsOf: indexURL)
            stamps = try JSONDecoder().decode([SavedStamp].self, from: data)
        } catch {
            stamps = []
        }
    }

    @discardableResult
    func addStamp(from url: URL) -> SavedStamp? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()

        let pngData: Data?
        if ext == "pdf" {
            pngData = Self.renderPDFToPNG(data: data)
        } else {
            // Load image via ImageIO to preserve alpha channel (avoids TIFF roundtrip)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            pngData = Self.pngData(from: cgImage)
        }

        guard let finalData = pngData else { return nil }
        return addStamp(imageData: finalData, name: name)
    }

    @discardableResult
    func addStamp(imageData: Data, name: String) -> SavedStamp {
        let fm = FileManager.default
        let dir = Self.stampsDirectory

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let id = UUID()
        let filename = "\(id.uuidString).png"
        let fileURL = dir.appendingPathComponent(filename)

        try? imageData.write(to: fileURL)

        let saved = SavedStamp(
            id: id,
            name: name,
            filename: filename,
            dateAdded: Date()
        )
        stamps.append(saved)
        save()
        return saved
    }

    func deleteStamp(id: UUID) {
        guard let index = stamps.firstIndex(where: { $0.id == id }) else { return }
        let stamp = stamps[index]
        let fileURL = Self.stampsDirectory.appendingPathComponent(stamp.filename)
        try? FileManager.default.removeItem(at: fileURL)
        stamps.remove(at: index)
        save()
    }

    func imageData(for stamp: SavedStamp) -> Data? {
        let fileURL = Self.stampsDirectory.appendingPathComponent(stamp.filename)
        return try? Data(contentsOf: fileURL)
    }

    func thumbnail(for stamp: SavedStamp) -> NSImage? {
        guard let data = imageData(for: stamp) else { return nil }
        return NSImage(data: data)
    }

    private func save() {
        let fm = FileManager.default
        let dir = Self.stampsDirectory

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        do {
            let data = try JSONEncoder().encode(stamps)
            try data.write(to: Self.indexURL)
        } catch {
            // Silently fail — stamp library is not critical
        }
    }

    // MARK: - PDF to PNG

    private static func renderPDFToPNG(data: Data) -> Data? {
        guard let pdfDoc = PDFDocument(data: data),
              let page = pdfDoc.page(at: 0) else { return nil }

        let mediaBox = page.bounds(for: .mediaBox)
        // Render at 2x for good quality thumbnails/stamps
        let scale: CGFloat = 2.0
        let width = Int(mediaBox.width * scale)
        let height = Int(mediaBox.height * scale)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)

        // Transparent background — no fill, preserving PDF transparency
        context.clear(CGRect(origin: .zero, size: mediaBox.size))

        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return nil }
        return pngData(from: cgImage)
    }

    /// Write a CGImage to PNG data using ImageIO (preserves alpha channel without TIFF roundtrip).
    private static func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
