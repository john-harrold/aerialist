import SwiftUI
import PDFKit

struct FormFieldInspector: View {
    @Bindable var viewModel: DocumentViewModel

    var body: some View {
        Form {
            Section("Form Fields") {
                if let fields = formFields, !fields.isEmpty {
                    ForEach(fields, id: \.fieldName) { annotation in
                        if let name = annotation.fieldName {
                            LabeledContent(name) {
                                TextField("Value", text: fieldBinding(for: name))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                } else {
                    Text("No form fields found")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 280)
    }

    private var formFields: [PDFAnnotation]? {
        guard let pdf = viewModel.pdfDocument else { return nil }
        var fields: [PDFAnnotation] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            for annotation in page.annotations where annotation.type == "Widget" {
                fields.append(annotation)
            }
        }
        return fields
    }

    private func fieldBinding(for name: String) -> Binding<String> {
        Binding(
            get: { viewModel.sidecar.formFieldOverrides[name] ?? "" },
            set: { viewModel.sidecar.formFieldOverrides[name] = $0 }
        )
    }
}
