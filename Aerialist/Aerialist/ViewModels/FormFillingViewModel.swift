import SwiftUI
import PDFKit

extension DocumentViewModel {

    /// Apply form field overrides from sidecar to the live PDF.
    func applyFormFieldOverrides() {
        guard let pdf = pdfDocument else { return }

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            for annotation in page.annotations where annotation.type == "Widget" {
                if let name = annotation.fieldName,
                   let value = sidecar.formFieldOverrides[name] {
                    annotation.widgetStringValue = value
                }
            }
        }
    }

    /// Save current form field values to sidecar.
    func captureFormFieldValues() {
        guard let pdf = pdfDocument else { return }

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            for annotation in page.annotations where annotation.type == "Widget" {
                if let name = annotation.fieldName,
                   let value = annotation.widgetStringValue, !value.isEmpty {
                    sidecar.formFieldOverrides[name] = value
                }
            }
        }
    }
}
