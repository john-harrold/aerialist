import SwiftUI
import PDFKit

extension DocumentViewModel {

    /// Add a text box at the center of the current page.
    func addTextBox() {
        guard let pdf = pdfDocument,
              currentPageIndex < pdf.pageCount,
              let page = pdf.page(at: currentPageIndex) else { return }

        let pageBounds = page.bounds(for: .mediaBox)
        let bounds = AnnotationBounds(
            x: (pageBounds.width - 200) / 2,
            y: (pageBounds.height - 40) / 2,
            width: 200,
            height: 40
        )

        let textBox = TextBoxAnnotationModel(
            pageIndex: currentPageIndex,
            bounds: bounds
        )

        let oldSidecar = sidecar
        sidecar.textBoxes.append(textBox)
        selectedAnnotationID = textBox.id

        registerUndo { vm in
            vm.document?.sidecar = oldSidecar
        }
    }

    /// Add a comment at the specified position on the current page.
    func addComment(at position: CGPoint? = nil) {
        guard let pdf = pdfDocument,
              currentPageIndex < pdf.pageCount,
              let page = pdf.page(at: currentPageIndex) else { return }

        let pageBounds = page.bounds(for: .mediaBox)
        let origin = position ?? CGPoint(
            x: pageBounds.width / 2 - 12,
            y: pageBounds.height / 2 - 12
        )

        let bounds = AnnotationBounds(
            x: origin.x, y: origin.y,
            width: 24, height: 24
        )

        let comment = CommentAnnotationModel(
            pageIndex: currentPageIndex,
            bounds: bounds
        )

        let oldSidecar = sidecar
        sidecar.comments.append(comment)
        selectedAnnotationID = comment.id

        registerUndo { vm in
            vm.document?.sidecar = oldSidecar
        }
    }

    /// Add a markup annotation for the given text selection.
    func addMarkup(type: MarkupType, quadPoints: [[QuadPoint]], color: String = "#FFFF00") {
        let markup = MarkupAnnotationModel(
            pageIndex: currentPageIndex,
            type: type,
            quadrilateralPoints: quadPoints,
            color: color
        )

        let oldSidecar = sidecar
        sidecar.markups.append(markup)

        registerUndo { vm in
            vm.document?.sidecar = oldSidecar
        }
    }
}
