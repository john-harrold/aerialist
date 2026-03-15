import SwiftUI

struct CommentsPanel: View {
    @Bindable var viewModel: DocumentViewModel
    var selectedCommentID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.sidecar.comments.isEmpty {
                emptyState
            } else {
                commentsList
            }
        }
        .frame(width: 260)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Comments")
                .font(.headline)
            Spacer()
            Text("\(viewModel.sidecar.comments.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No comments yet")
                .foregroundStyle(.secondary)
            Text("Click on the page to add a comment")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Comments List

    private var commentsList: some View {
        ScrollViewReader { proxy in
            List(sortedComments) { comment in
                commentRow(comment)
                    .id(comment.id)
                    .listRowBackground(
                        comment.id == selectedCommentID
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
            }
            .listStyle(.plain)
            .onAppear {
                if let id = selectedCommentID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: selectedCommentID) { _, newID in
                if let newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    private var sortedComments: [CommentAnnotationModel] {
        viewModel.sidecar.comments.sorted { a, b in
            if a.pageIndex != b.pageIndex { return a.pageIndex < b.pageIndex }
            return a.date < b.date
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: CommentAnnotationModel) -> some View {
        Button {
            viewModel.goToPage(comment.pageIndex)
            viewModel.selectedAnnotationID = comment.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Page \(comment.pageIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if comment.id == selectedCommentID {
                    editableText(comment)
                } else {
                    Text(comment.text.isEmpty ? "Empty comment" : comment.text)
                        .font(.body)
                        .lineLimit(3)
                        .foregroundStyle(comment.text.isEmpty ? .secondary : .primary)
                }

                Text(comment.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Comment", role: .destructive) {
                var updated = viewModel.sidecar
                updated.comments.removeAll { $0.id == comment.id }
                viewModel.sidecar = updated
                if viewModel.selectedAnnotationID == comment.id {
                    viewModel.selectedAnnotationID = nil
                }
            }
        }
    }

    // MARK: - Editable Text for Selected Comment

    private func editableText(_ comment: CommentAnnotationModel) -> some View {
        TextField("Add comment text...", text: textBinding(for: comment.id), axis: .vertical)
            .lineLimit(2...6)
            .textFieldStyle(.plain)
            .font(.body)
    }

    private func textBinding(for commentID: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.sidecar.comments.first { $0.id == commentID }?.text ?? ""
            },
            set: { newValue in
                if let index = viewModel.sidecar.comments.firstIndex(where: { $0.id == commentID }) {
                    viewModel.sidecar.comments[index].text = newValue
                }
            }
        )
    }
}
