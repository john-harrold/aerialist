import SwiftUI

struct CommentInspector: View {
    @Bindable var viewModel: DocumentViewModel
    let commentID: UUID

    private var comment: CommentAnnotationModel? {
        viewModel.sidecar.comments.first { $0.id == commentID }
    }

    var body: some View {
        if let comment = comment {
            Form {
                Section("Comment") {
                    TextField("Text", text: textBinding, axis: .vertical)
                        .lineLimit(3...8)

                    LabeledContent("Author") {
                        Text(comment.author)
                    }

                    LabeledContent("Date") {
                        Text(comment.date, style: .date)
                    }

                    LabeledContent("Page") {
                        Text("\(comment.pageIndex + 1)")
                    }
                }

                Section {
                    Button("Delete Comment", role: .destructive) {
                        var updated = viewModel.sidecar
                        updated.comments.removeAll { $0.id == commentID }
                        viewModel.sidecar = updated
                        viewModel.selectedAnnotationID = nil
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 250)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { comment?.text ?? "" },
            set: { newValue in
                if let index = viewModel.sidecar.comments.firstIndex(where: { $0.id == commentID }) {
                    viewModel.sidecar.comments[index].text = newValue
                }
            }
        )
    }
}
