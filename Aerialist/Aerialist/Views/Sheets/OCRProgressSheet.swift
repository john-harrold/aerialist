import SwiftUI

struct OCRProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    let totalPages: Int
    @Binding var completedPages: Int
    @Binding var isComplete: Bool
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Running OCR")
                .font(.title2)
                .fontWeight(.semibold)

            ProgressView(value: Double(completedPages), total: Double(totalPages)) {
                if isComplete {
                    Text("Processed \(totalPages) pages")
                } else {
                    Text("Processing page \(completedPages + 1) of \(totalPages)")
                }
            }
            .progressViewStyle(.linear)

            if isComplete {
                Text("OCR complete!")
                    .foregroundStyle(.green)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") {
                    onCancel()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 150)
    }
}
