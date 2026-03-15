import PDFKit

extension MarkupAnnotationModel {

    var pdfAnnotationSubtype: PDFAnnotationSubtype {
        switch type {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        }
    }

    var boundingRect: CGRect {
        let allPoints = quadrilateralPoints.flatMap { $0 }
        guard !allPoints.isEmpty else { return .zero }
        let xs = allPoints.map(\.x)
        let ys = allPoints.map(\.y)
        return CGRect(
            x: xs.min()!, y: ys.min()!,
            width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
        )
    }
}
