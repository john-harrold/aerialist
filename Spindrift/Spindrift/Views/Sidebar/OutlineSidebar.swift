import SwiftUI
import PDFKit

struct OutlineSidebar: View {
    let pdfDocument: PDFDocument
    @Bindable var viewModel: DocumentViewModel

    var body: some View {
        List {
            if let root = pdfDocument.outlineRoot {
                OutlineChildren(parent: root, viewModel: viewModel)
            } else {
                Text("No bookmarks")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct OutlineChildren: View {
    let parent: PDFOutline
    @Bindable var viewModel: DocumentViewModel

    var body: some View {
        ForEach(0..<parent.numberOfChildren, id: \.self) { index in
            if let child = parent.child(at: index) {
                OutlineRow(outline: child, viewModel: viewModel)
            }
        }
    }
}

private struct OutlineRow: View {
    let outline: PDFOutline
    @Bindable var viewModel: DocumentViewModel

    var body: some View {
        if outline.numberOfChildren > 0 {
            DisclosureGroup {
                OutlineChildren(parent: outline, viewModel: viewModel)
            } label: {
                outlineLabel
            }
        } else {
            outlineLabel
        }
    }

    private var outlineLabel: some View {
        Button {
            navigateToOutline()
        } label: {
            Text(outline.label ?? "Untitled")
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func navigateToOutline() {
        guard let destination = outline.destination,
              let page = destination.page,
              let document = viewModel.pdfDocument else { return }
        let index = document.index(for: page)
        viewModel.goToPage(index)
    }
}
