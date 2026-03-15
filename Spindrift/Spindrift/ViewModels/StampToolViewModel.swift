import SwiftUI
import PDFKit

extension DocumentViewModel {

    /// Add a stamp from PNG image data at the center of the current page.
    /// Preserves the original aspect ratio of the image.
    func addStamp(imageData: Data) {
        guard let pdf = pdfDocument,
              currentPageIndex < pdf.pageCount,
              let page = pdf.page(at: currentPageIndex),
              let nsImage = NSImage(data: imageData) else { return }

        let base64 = imageData.base64EncodedString()
        let pageBounds = page.bounds(for: .mediaBox)

        // Get original image size and preserve aspect ratio
        let imageSize = nsImage.size
        let maxDimension: CGFloat = 150
        let scale: CGFloat
        if imageSize.width >= imageSize.height {
            scale = maxDimension / imageSize.width
        } else {
            scale = maxDimension / imageSize.height
        }
        let stampWidth = imageSize.width * scale
        let stampHeight = imageSize.height * scale

        let bounds = AnnotationBounds(
            x: (pageBounds.width - stampWidth) / 2,
            y: (pageBounds.height - stampHeight) / 2,
            width: stampWidth,
            height: stampHeight
        )

        let stamp = StampAnnotationModel(
            pageIndex: currentPageIndex,
            bounds: bounds,
            imageData: base64
        )

        let oldSidecar = sidecar
        sidecar.stamps.append(stamp)
        selectedAnnotationID = stamp.id

        registerUndo { vm in
            vm.sidecar = oldSidecar
        }
    }

    /// Move a stamp to new bounds.
    func moveStamp(id: UUID, to newBounds: AnnotationBounds) {
        guard let index = sidecar.stamps.firstIndex(where: { $0.id == id }) else { return }

        let oldBounds = sidecar.stamps[index].bounds
        sidecar.stamps[index].bounds = newBounds

        registerUndo { vm in
            vm.moveStamp(id: id, to: oldBounds)
        }
    }

    /// Delete a stamp.
    func deleteStamp(id: UUID) {
        guard let index = sidecar.stamps.firstIndex(where: { $0.id == id }) else { return }

        let removed = sidecar.stamps.remove(at: index)
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }

        registerUndo { vm in
            vm.sidecar.stamps.insert(removed, at: min(index, vm.sidecar.stamps.count))
            vm.selectedAnnotationID = id
        }
    }
}
