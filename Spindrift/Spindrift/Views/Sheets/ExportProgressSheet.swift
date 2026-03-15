import SwiftUI

/// Reusable progress sheet for long-running export operations.
struct ExportProgressSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let totalPages: Int
    @Binding var completedPages: Int
    @Binding var isComplete: Bool
    var completionMessage: String = "Export complete!"
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
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
                Text(completionMessage)
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
