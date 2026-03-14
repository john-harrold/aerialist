import SwiftUI
import PDFKit

struct ThumbnailSidebar: View {
    @Bindable var viewModel: DocumentViewModel
    @State private var lastClickedIndex: Int?

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let pdf = viewModel.pdfDocument {
                        ForEach(0..<pdf.pageCount, id: \.self) { index in
                            ThumbnailItem(
                                pdf: pdf,
                                pageIndex: index,
                                isCurrent: index == viewModel.currentPageIndex,
                                isSelected: viewModel.selectedPageIndices.contains(index)
                            )
                            .id(index)
                            .onTapGesture {
                                handleTap(index: index, pageCount: pdf.pageCount)
                            }
                            .contextMenu {
                                contextMenuContent(for: index, pdf: pdf)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                withAnimation {
                    scrollProxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func handleTap(index: Int, pageCount: Int) {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            // Cmd-click: toggle this page in selection
            if viewModel.selectedPageIndices.contains(index) {
                viewModel.selectedPageIndices.remove(index)
            } else {
                viewModel.selectedPageIndices.insert(index)
            }
        } else if modifiers.contains(.shift), let anchor = lastClickedIndex {
            // Shift-click: range select from last clicked to this index
            let range = min(anchor, index)...max(anchor, index)
            viewModel.selectedPageIndices = Set(range)
        } else {
            // Plain click: navigate and clear multi-select
            viewModel.selectedPageIndices = []
            viewModel.goToPage(index)
        }

        lastClickedIndex = index
    }

    @ViewBuilder
    private func contextMenuContent(for index: Int, pdf: PDFDocument) -> some View {
        let indicesToDelete = viewModel.selectedPageIndices.isEmpty
            ? [index]
            : (viewModel.selectedPageIndices.contains(index)
                ? Array(viewModel.selectedPageIndices)
                : [index])
        let count = indicesToDelete.count

        Button(count == 1 ? "Delete Page" : "Delete \(count) Pages", role: .destructive) {
            viewModel.confirmDeletePages(Set(indicesToDelete))
        }
        .disabled(count >= pdf.pageCount)
    }
}

private struct ThumbnailItem: View {
    let pdf: PDFDocument
    let pageIndex: Int
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let page = pdf.page(at: pageIndex) {
                Image(nsImage: page.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 160)
                    .background(Color.white)
                    .border(borderColor, width: (isCurrent || isSelected) ? 2 : 1)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay {
                        if isSelected {
                            Color.accentColor.opacity(0.15)
                        }
                    }
            }
            Text("\(pageIndex + 1)")
                .font(.caption)
                .foregroundStyle((isCurrent || isSelected) ? .primary : .secondary)
        }
    }

    private var borderColor: Color {
        if isCurrent { return .accentColor }
        if isSelected { return .accentColor.opacity(0.7) }
        return .gray.opacity(0.3)
    }
}
