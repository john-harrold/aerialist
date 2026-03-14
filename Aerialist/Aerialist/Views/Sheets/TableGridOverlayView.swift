import SwiftUI
import PDFKit

/// Shows a rendered image of a PDF table region with draggable grid lines.
/// Users can drag lines to adjust column/row boundaries and right-click to add/delete lines.
/// Supports undo/redo, line selection, and Delete key to remove selected lines.
struct TableGridOverlayView: View {
    let pdfDocument: PDFDocument?
    let table: TableExtractionService.ExtractedTable

    @Binding var colPositions: [CGFloat]
    @Binding var rowPositions: [CGFloat]

    @State private var renderedImage: NSImage?
    @State private var imageSize: CGSize = .zero
    @State private var selectedLine: SelectedLine?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var containerSize: CGSize = .zero
    /// Snapshot of positions captured at drag start, for undo registration.
    @State private var dragStartCols: [CGFloat]?
    @State private var dragStartRows: [CGFloat]?

    @Environment(\.undoManager) private var undoManager
    @FocusState private var isFocused: Bool

    enum SelectedLine: Equatable {
        case col(Int)
        case row(Int)
    }

    /// Width of the invisible hit area around each grid line (in points).
    private let lineHitWidth: CGFloat = 12

    /// DPI for rendering the PDF region.
    private let renderDPI: CGFloat = 150.0

    private var scale: CGFloat { renderDPI / 72.0 }

    /// Dummy target for UndoManager registration.
    nonisolated(unsafe) private static let undoTarget = NSObject()

    var body: some View {
        VStack(spacing: 0) {
            zoomToolbar
            GeometryReader { outer in
                ScrollView([.horizontal, .vertical]) {
                    gridContent(containerSize: outer.size)
                }
                .onChange(of: outer.size) { _, newSize in
                    containerSize = newSize
                }
                .onAppear { containerSize = outer.size }
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.delete) {
            guard selectedLine != nil else { return .ignored }
            deleteSelectedLine()
            return .handled
        }
        .onKeyPress("+") { adjustZoom(by: 0.25); return .handled }
        .onKeyPress("=") { adjustZoom(by: 0.25); return .handled }
        .onKeyPress("-") { adjustZoom(by: -0.25); return .handled }
        .onAppear {
            renderPDFRegion()
            isFocused = true
        }
        .onChange(of: table.bbox) { _, _ in renderPDFRegion() }
        .onChange(of: table.pageIndex) { _, _ in renderPDFRegion() }
    }

    private var zoomToolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: { adjustZoom(by: -0.25) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomLevel <= 0.25)

            Text("\(Int(zoomLevel * 100))%")
                .monospacedDigit()
                .frame(width: 50)

            Button(action: { adjustZoom(by: 0.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomLevel >= 4.0)

            Button("Fit") {
                zoomLevel = 1.0
            }
            .disabled(zoomLevel == 1.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func adjustZoom(by delta: CGFloat) {
        let newZoom = zoomLevel + delta
        zoomLevel = min(max(newZoom, 0.25), 4.0)
    }

    private func gridContent(containerSize: CGSize) -> some View {
        let baseFit = fitScale(imageSize: imageSize, viewSize: containerSize)
        let displayW = imageSize.width * baseFit * zoomLevel
        let displayH = imageSize.height * baseFit * zoomLevel
        return ZStack(alignment: .topLeading) {
            if let image = renderedImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: displayW, height: displayH)
                    .onTapGesture {
                        selectedLine = nil
                    }

                gridLinesOverlay(displayWidth: displayW, displayHeight: displayH)
                    .frame(width: displayW, height: displayH)
                    .contextMenu {
                        contextMenuItems()
                    }
            } else {
                Text("Rendering...")
                    .foregroundStyle(.secondary)
                    .frame(width: containerSize.width, height: containerSize.height)
            }
        }
        .frame(width: max(displayW, containerSize.width),
               height: max(displayH, containerSize.height))
    }

    // MARK: - Grid Lines Overlay

    private func gridLinesOverlay(displayWidth: CGFloat, displayHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(colPositions.enumerated()), id: \.offset) { i, xPos in
                columnLineView(index: i, xPos: xPos, displayWidth: displayWidth, displayHeight: displayHeight)
            }
            ForEach(Array(rowPositions.enumerated()), id: \.offset) { i, yPos in
                rowLineView(index: i, yPos: yPos, displayWidth: displayWidth, displayHeight: displayHeight)
            }
        }
    }

    private func columnLineView(index i: Int, xPos: CGFloat, displayWidth: CGFloat, displayHeight: CGFloat) -> some View {
        let displayX: CGFloat = pdfXToDisplay(xPos, displayWidth: displayWidth)
        let isSelected: Bool = selectedLine == .col(i)
        let lineW: CGFloat = isSelected ? 4 : 2
        let hitW: CGFloat = lineHitWidth
        return Color.clear
            .frame(width: hitW, height: displayHeight)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.red : Color.red.opacity(0.7))
                    .frame(width: lineW)
                    .overlay(
                        isSelected
                            ? Rectangle().stroke(Color.white, lineWidth: 1)
                            : nil
                    )
                    .shadow(color: isSelected ? Color.red.opacity(0.6) : .clear, radius: 3)
            )
            .offset(x: displayX - hitW / 2)
            .onTapGesture {
                selectedLine = .col(i)
                isFocused = true
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartCols == nil {
                            dragStartCols = Array(colPositions)
                            dragStartRows = Array(rowPositions)
                            selectedLine = .col(i)
                            isFocused = true
                        }
                        guard let startCols = dragStartCols else { return }
                        let startDisplayX = pdfXToDisplay(startCols[i], displayWidth: displayWidth)
                        let newDisplayX = startDisplayX + value.translation.width
                        let newX = displayXToPdfX(newDisplayX, displayWidth: displayWidth)
                        colPositions[i] = clamp(newX, min: table.bbox.minX, max: table.bbox.maxX)
                    }
                    .onEnded { _ in
                        let movedValue = colPositions[i]
                        colPositions.sort()
                        if let newIdx = colPositions.firstIndex(of: movedValue) {
                            selectedLine = .col(newIdx)
                        }
                        registerDragUndo(actionName: "Move Column Line")
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }

    private func rowLineView(index i: Int, yPos: CGFloat, displayWidth: CGFloat, displayHeight: CGFloat) -> some View {
        let displayY: CGFloat = pdfYToDisplay(yPos, displayHeight: displayHeight)
        let isSelected: Bool = selectedLine == .row(i)
        let lineH: CGFloat = isSelected ? 4 : 2
        let hitW: CGFloat = lineHitWidth
        return Color.clear
            .frame(width: displayWidth, height: hitW)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.blue.opacity(0.7))
                    .frame(height: lineH)
                    .overlay(
                        isSelected
                            ? Rectangle().stroke(Color.white, lineWidth: 1)
                            : nil
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.6) : .clear, radius: 3)
            )
            .offset(y: displayY - hitW / 2)
            .onTapGesture {
                selectedLine = .row(i)
                isFocused = true
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartRows == nil {
                            dragStartCols = Array(colPositions)
                            dragStartRows = Array(rowPositions)
                            selectedLine = .row(i)
                            isFocused = true
                        }
                        guard let startRows = dragStartRows else { return }
                        let startDisplayY = pdfYToDisplay(startRows[i], displayHeight: displayHeight)
                        let newDisplayY = startDisplayY + value.translation.height
                        let newY = displayYToPdfY(newDisplayY, displayHeight: displayHeight)
                        rowPositions[i] = clamp(newY, min: table.bbox.minY, max: table.bbox.maxY)
                    }
                    .onEnded { _ in
                        let movedValue = rowPositions[i]
                        rowPositions.sort()
                        if let newIdx = rowPositions.firstIndex(of: movedValue) {
                            selectedLine = .row(newIdx)
                        }
                        registerDragUndo(actionName: "Move Row Line")
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems() -> some View {
        Button("Add Vertical Line") {
            let oldCols = Array(colPositions)
            let midX = (table.bbox.minX + table.bbox.maxX) / 2
            colPositions.append(midX)
            colPositions.sort()
            if let newIdx = colPositions.firstIndex(of: midX) {
                selectedLine = .col(newIdx)
            }
            registerUndo(oldCols: oldCols, oldRows: rowPositions, actionName: "Add Vertical Line")
        }

        Button("Add Horizontal Line") {
            let oldRows = Array(rowPositions)
            let midY = (table.bbox.minY + table.bbox.maxY) / 2
            rowPositions.append(midY)
            rowPositions.sort()
            if let newIdx = rowPositions.firstIndex(of: midY) {
                selectedLine = .row(newIdx)
            }
            registerUndo(oldCols: colPositions, oldRows: oldRows, actionName: "Add Horizontal Line")
        }

        if selectedLine != nil {
            Divider()
            Button("Delete Selected Line") {
                deleteSelectedLine()
            }
        }
    }

    // MARK: - Selection & Deletion

    private func deleteSelectedLine() {
        guard let sel = selectedLine else { return }
        let oldCols = Array(colPositions)
        let oldRows = Array(rowPositions)

        switch sel {
        case .col(let i) where i < colPositions.count:
            colPositions.remove(at: i)
            selectedLine = nil
            registerUndo(oldCols: oldCols, oldRows: oldRows, actionName: "Delete Column Line")
        case .row(let i) where i < rowPositions.count:
            rowPositions.remove(at: i)
            selectedLine = nil
            registerUndo(oldCols: oldCols, oldRows: oldRows, actionName: "Delete Row Line")
        default:
            break
        }
    }

    // MARK: - Undo

    private func registerDragUndo(actionName: String) {
        guard let oldCols = dragStartCols, let oldRows = dragStartRows else { return }
        registerUndo(oldCols: oldCols, oldRows: oldRows, actionName: actionName)
        dragStartCols = nil
        dragStartRows = nil
    }

    private func registerUndo(oldCols: [CGFloat], oldRows: [CGFloat], actionName: String) {
        guard let um = undoManager else { return }
        let newCols = Array(colPositions)
        let newRows = Array(rowPositions)
        guard oldCols != newCols || oldRows != newRows else { return }

        let colBinding = _colPositions
        let rowBinding = _rowPositions
        nonisolated(unsafe) let mgr = um

        mgr.registerUndo(withTarget: Self.undoTarget) { _ in
            let redoCols = colBinding.wrappedValue
            let redoRows = rowBinding.wrappedValue
            colBinding.wrappedValue = oldCols
            rowBinding.wrappedValue = oldRows

            mgr.registerUndo(withTarget: Self.undoTarget) { _ in
                colBinding.wrappedValue = redoCols
                rowBinding.wrappedValue = redoRows
            }
            mgr.setActionName(actionName)
        }
        mgr.setActionName(actionName)
    }

    // MARK: - Coordinate Conversion

    private func pdfXToDisplay(_ pdfX: CGFloat, displayWidth: CGFloat) -> CGFloat {
        guard table.bbox.width > 0 else { return 0 }
        return (pdfX - table.bbox.minX) / table.bbox.width * displayWidth
    }

    private func displayXToPdfX(_ displayX: CGFloat, displayWidth: CGFloat) -> CGFloat {
        guard displayWidth > 0 else { return table.bbox.minX }
        return table.bbox.minX + displayX / displayWidth * table.bbox.width
    }

    private func pdfYToDisplay(_ pdfY: CGFloat, displayHeight: CGFloat) -> CGFloat {
        guard table.bbox.height > 0 else { return 0 }
        return (table.bbox.maxY - pdfY) / table.bbox.height * displayHeight
    }

    private func displayYToPdfY(_ displayY: CGFloat, displayHeight: CGFloat) -> CGFloat {
        guard displayHeight > 0 else { return table.bbox.maxY }
        return table.bbox.maxY - displayY / displayHeight * table.bbox.height
    }

    private func fitScale(imageSize: CGSize, viewSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return 1.0 }
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        return min(scaleX, scaleY)
    }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }

    // MARK: - PDF Rendering

    private func renderPDFRegion() {
        guard let doc = pdfDocument,
              table.pageIndex < doc.pageCount,
              let page = doc.page(at: table.pageIndex) else { return }

        let bbox = table.bbox
        guard bbox.width > 0, bbox.height > 0 else { return }

        let pixelWidth = Int(bbox.width * scale)
        let pixelHeight = Int(bbox.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bbox.minX, y: -bbox.minY)
        page.draw(with: .mediaBox, to: context)

        if let cgImage = context.makeImage() {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: pixelWidth, height: pixelHeight))
            self.renderedImage = nsImage
            self.imageSize = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        }
    }
}
