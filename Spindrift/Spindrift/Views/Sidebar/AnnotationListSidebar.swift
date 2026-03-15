import SwiftUI

struct AnnotationListSidebar: View {
    @Bindable var viewModel: DocumentViewModel

    var body: some View {
        List {
            if !viewModel.sidecar.comments.isEmpty {
                Section("Comments") {
                    ForEach(viewModel.sidecar.comments) { comment in
                        Button {
                            viewModel.goToPage(comment.pageIndex)
                            viewModel.selectedAnnotationID = comment.id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.text.isEmpty ? "Empty comment" : comment.text)
                                    .lineLimit(2)
                                Text("Page \(comment.pageIndex + 1) - \(comment.author)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !viewModel.sidecar.textBoxes.isEmpty {
                Section("Text Boxes") {
                    ForEach(viewModel.sidecar.textBoxes) { textBox in
                        Button {
                            viewModel.goToPage(textBox.pageIndex)
                            viewModel.selectedAnnotationID = textBox.id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(textBox.text.isEmpty ? "Empty text box" : textBox.text)
                                    .lineLimit(2)
                                Text("Page \(textBox.pageIndex + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !viewModel.sidecar.stamps.isEmpty {
                Section("Stamps") {
                    ForEach(viewModel.sidecar.stamps) { stamp in
                        Button {
                            viewModel.goToPage(stamp.pageIndex)
                            viewModel.selectedAnnotationID = stamp.id
                        } label: {
                            Text("Stamp on page \(stamp.pageIndex + 1)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.sidecar.comments.isEmpty &&
                viewModel.sidecar.textBoxes.isEmpty &&
                viewModel.sidecar.stamps.isEmpty {
                Text("No annotations")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}
