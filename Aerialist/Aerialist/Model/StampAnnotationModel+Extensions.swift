import AppKit

extension StampAnnotationModel {

    /// Decode the base64 image data into an NSImage.
    var image: NSImage? {
        guard let data = Data(base64Encoded: imageData) else { return nil }
        return NSImage(data: data)
    }
}
