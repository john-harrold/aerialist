import SwiftUI
import PDFKit

extension View {
    @ViewBuilder
    func activeButtonStyle(_ isActive: Bool) -> some View {
        if isActive {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

struct ContentView: View {
    @ObservedObject var document: SpindriftDocument
    @State private var viewModel = DocumentViewModel()
    @State private var showThumbnailSidebar = true
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            if showThumbnailSidebar {
                ThumbnailSidebar(viewModel: viewModel)
                    .frame(minWidth: 120, idealWidth: 160, maxWidth: 250)
            }
        } detail: {
            VStack(spacing: 0) {
                if viewModel.toolMode == .select && !viewModel.showOCRToolbar && !viewModel.showTableToolbar {
                    selectModeToolbar
                }
                if viewModel.toolMode.isStamp {
                    stampToolbar
                }
                if viewModel.toolMode.isMarkup {
                    markupToolbar
                }
                if viewModel.toolMode.isDraw {
                    drawToolbar
                }
                if viewModel.showOCRToolbar {
                    ocrToolbar
                }
                if viewModel.showTableToolbar {
                    tableToolbar
                }
                PDFCanvasView(
                    pdfDocument: document.pdfDocument,
                    viewModel: viewModel
                )
                .overlay(alignment: .topLeading) {
                    toolModeHint
                }
            }
        }
        .inspector(isPresented: showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 220, ideal: 260, max: 300)
        }
        .toolbar(id: "main") {
            MainToolbar(viewModel: viewModel)
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            viewModel.document = document
            viewModel.sidecar = document.sidecar
            viewModel.undoManager = undoManager
        }
        .onChange(of: undoManager) { _, newValue in
            viewModel.undoManager = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAsPDF)) { _ in
            exportAsPDF()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ocrCurrentPage)) { _ in
            viewModel.startOCRCurrentPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ocrAllPages)) { _ in
            viewModel.startOCRAllPages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .combineFiles)) { _ in
            viewModel.showCombineSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAsWord)) { _ in
            exportAsWord()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAsText)) { _ in
            exportAsText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tableSelect)) { _ in
            viewModel.showTableToolbar = true
            viewModel.showOCRToolbar = false
            viewModel.toolMode = .tableSelect
        }
        .sheet(isPresented: $viewModel.showStampPicker) {
            StampPickerSheet { imageData in
                viewModel.addStamp(imageData: imageData)
                viewModel.toolMode = .select
            }
        }
        .sheet(isPresented: $viewModel.showCombineSheet) {
            CombineFilesSheet { combinedPDF in
                viewModel.applyCombinedDocument(combinedPDF)
            }
        }
        .confirmationDialog(
            deletePageDialogTitle,
            isPresented: $viewModel.showDeletePageConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.executePendingPageDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletePageIndices = []
            }
        }
        .sheet(isPresented: $viewModel.showOCRProgress) {
            OCRProgressSheet(
                totalPages: viewModel.pageCount,
                completedPages: $viewModel.ocrCompletedPages,
                isComplete: $viewModel.ocrIsComplete,
                onCancel: { viewModel.cancelOCR() }
            )
        }
        .alert(
            "OCR Error",
            isPresented: Binding(
                get: { viewModel.ocrError != nil },
                set: { if !$0 { viewModel.ocrError = nil } }
            )
        ) {
            Button("OK") { viewModel.ocrError = nil }
        } message: {
            Text(viewModel.ocrError ?? "")
        }
        .sheet(isPresented: $viewModel.showWordExportProgress) {
            ExportProgressSheet(
                title: "Exporting as Word",
                totalPages: viewModel.pageCount,
                completedPages: $viewModel.wordExportCompletedPages,
                isComplete: $viewModel.wordExportIsComplete,
                completionMessage: "Word export complete!",
                onCancel: { viewModel.cancelWordExport() }
            )
        }
        .alert(
            "Word Export Error",
            isPresented: Binding(
                get: { viewModel.wordExportError != nil },
                set: { if !$0 { viewModel.wordExportError = nil } }
            )
        ) {
            Button("OK") { viewModel.wordExportError = nil }
        } message: {
            Text(viewModel.wordExportError ?? "")
        }
        .sheet(isPresented: $viewModel.showTablePreview) {
            TablePreviewSheet(
                tables: viewModel.extractedTables,
                initialPageIndex: viewModel.currentPageIndex,
                pdfDocument: viewModel.pdfDocument,
                onExportCSV: { table in exportTableAsCSV(table) },
                onExportAllExcel: { exportTablesAsExcel(viewModel.extractedTables) },
                onReExtractWithGrid: { index, cols, rows in
                    viewModel.reExtractWithGrid(tableIndex: index, colPositions: cols, rowPositions: rows)
                }
            )
        }
        .alert(
            "Table Export Error",
            isPresented: Binding(
                get: { viewModel.tableExportError != nil },
                set: { if !$0 { viewModel.tableExportError = nil } }
            )
        ) {
            Button("OK") { viewModel.tableExportError = nil }
        } message: {
            Text(viewModel.tableExportError ?? "")
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        if document.pdfDocument.pageCount == 0 {
            return "Spindrift"
        }
        return "Page \(viewModel.currentPageIndex + 1) of \(document.pdfDocument.pageCount)"
    }

    // MARK: - Tool Mode Hint

    @ViewBuilder
    private var toolModeHint: some View {
        if let hint = toolHintText {
            Text(hint)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
        }
    }

    private var toolHintText: String? {
        nil
    }

    // MARK: - Select Mode Toolbar

    private var selectModeToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(SelectMode.allCases) { mode in
                    Button {
                        viewModel.selectMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                    }
                    .activeButtonStyle(viewModel.selectMode == mode)
                }
            }

            if viewModel.hasBoxSelection {
                Divider()
                    .frame(height: 20)

                Button {
                    viewModel.copyBoxSelectionToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy selected region as image (Cmd+C)")

                Button {
                    viewModel.cropCurrentPageToBoxSelection()
                } label: {
                    Label("Crop Page", systemImage: "crop")
                }
                .buttonStyle(.bordered)
                .help("Crop current page to selection")

                Button {
                    viewModel.cropAllPagesToBoxSelection()
                } label: {
                    Label("Crop All", systemImage: "rectangle.stack")
                }
                .buttonStyle(.bordered)
                .help("Crop all pages to selection")

                Button {
                    viewModel.clearBoxSelection()
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .help("Clear selection (Escape)")
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Stamp Toolbar

    private var stampToolbar: some View {
        StampToolbar(
            stampLibrary: viewModel.stampLibrary,
            selectedStampID: $viewModel.selectedStampLibraryID
        ) { imageData in
            viewModel.pendingStampData = imageData
        }
    }

    // MARK: - Markup Toolbar

    private var markupToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(ToolMode.markupCases, id: \.id) { mode in
                    Button {
                        viewModel.toolMode = mode
                    } label: {
                        Image(systemName: mode.systemImage)
                            .frame(width: 24, height: 20)
                    }
                    .activeButtonStyle(viewModel.toolMode == mode)
                    .help(mode.markupTooltip)
                }
            }

            if viewModel.toolMode == .highlight {
                Divider()
                    .frame(height: 20)

                HStack(spacing: 6) {
                    ForEach(HighlightColor.all) { color in
                        Button {
                            viewModel.highlightColor = color
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if viewModel.highlightColor.name == color.name {
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(color.name)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - OCR Toolbar

    private var ocrToolbar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.startOCRCurrentPage()
            } label: {
                Label("Current Page", systemImage: "doc.text.viewfinder")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.startOCRAllPages()
            } label: {
                Label("All Pages", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Table Toolbar

    private var tableToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(DocumentViewModel.TableMode.allCases) { mode in
                    Button {
                        viewModel.tableMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                    }
                    .activeButtonStyle(viewModel.tableMode == mode)
                }
            }

            if viewModel.tableMode == .autodetect {
                tableDetectionMethodPicker

                Button {
                    viewModel.startTableAutoDetect()
                } label: {
                    Label("Detect Tables", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isDetectingTables)
            }

            Button {
                viewModel.previewTables()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isDetectingTables || viewModel.extractedTables.isEmpty)

            Button {
                viewModel.clearTableSelection()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .buttonStyle(.bordered)

            if viewModel.isDetectingTables {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.tableMode == .autodetect ? "Detecting tables..." : "Extracting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var tableDetectionMethodPicker: some View {
        Menu {
            ForEach(DocumentViewModel.TableDetectionMethod.allCases, id: \.self) { method in
                Button {
                    viewModel.tableDetectionMethod = method
                } label: {
                    if method == viewModel.tableDetectionMethod {
                        Label(method.rawValue, systemImage: "checkmark")
                    } else {
                        Text(method.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Method: \(viewModel.tableDetectionMethod.rawValue)")
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var tablePageScopePicker: some View {
        Menu {
            Button("Current Page") {
                viewModel.tablePageScope = .currentPage
                viewModel.annotationRevision += 1
            }
            Button("All Pages") {
                viewModel.tablePageScope = .allPages
                viewModel.annotationRevision += 1
            }
            Button("Pages...") {
                viewModel.tablePageScope = .specific(parsePageNumbers(viewModel.tableSpecificPages))
                viewModel.annotationRevision += 1
            }
        } label: {
            HStack(spacing: 4) {
                Text(tablePageScopeLabel)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()

        if case .specific = viewModel.tablePageScope {
            TextField("e.g. 1,3,5", text: $viewModel.tableSpecificPages)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onChange(of: viewModel.tableSpecificPages) { _, newValue in
                    viewModel.tablePageScope = .specific(parsePageNumbers(newValue))
                    viewModel.annotationRevision += 1
                }
        }
    }

    private var tablePageScopeLabel: String {
        switch viewModel.tablePageScope {
        case .currentPage: return "Current Page"
        case .allPages: return "All Pages"
        case .specific(let pages): return "Pages: \(pages.map { String($0 + 1) }.joined(separator: ","))"
        }
    }

    /// Parse user-entered page numbers (1-indexed) to 0-indexed array.
    private func parsePageNumbers(_ text: String) -> [Int] {
        text.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { $0 - 1 }
            .filter { $0 >= 0 }
    }

    // MARK: - Draw Toolbar

    private var drawToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(ShapeType.allCases) { type in
                    Button {
                        viewModel.drawShapeType = type
                    } label: {
                        Label(type.rawValue, systemImage: type.systemImage)
                    }
                    .activeButtonStyle(viewModel.drawShapeType == type)
                    .help(type.tooltip)
                }
            }

            Divider()
                .frame(height: 20)

            HStack(spacing: 4) {
                Text("Width")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", value: drawStrokeWidthDoubleBinding, format: .number)
                    .frame(width: 40)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: $viewModel.drawStrokeWidth, in: 1...20, step: 1)
                    .labelsHidden()
            }

            Picker("Line", selection: $viewModel.drawStrokeStyle) {
                ForEach(OutlineStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .frame(maxWidth: 100)

            ColorPicker("Line", selection: drawStrokeColorBinding)
                .disabled(viewModel.drawStrokeStyle == .none)
                .opacity(viewModel.drawStrokeStyle == .none ? 0.3 : 1)

            if viewModel.drawShapeType == .rectangle || viewModel.drawShapeType == .ellipse {
                Divider()
                    .frame(height: 20)

                Picker("Fill", selection: $viewModel.drawHasFill) {
                    Text("No").tag(false)
                    Text("Yes").tag(true)
                }
                .frame(maxWidth: 80)

                ColorPicker("Fill", selection: drawFillColorBinding)
                    .disabled(!viewModel.drawHasFill)
                    .opacity(viewModel.drawHasFill ? 1 : 0.3)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var drawStrokeWidthDoubleBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.drawStrokeWidth) },
            set: { viewModel.drawStrokeWidth = CGFloat($0) }
        )
    }

    private var drawStrokeColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.drawStrokeColor) },
            set: { viewModel.drawStrokeColor = $0.hexString }
        )
    }

    private var drawFillColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.drawFillColor) },
            set: { viewModel.drawFillColor = $0.hexString }
        )
    }

    // MARK: - Inspector

    private var isCommentModeActive: Bool {
        viewModel.toolMode == .comment
    }

    private var isTextBoxModeActive: Bool {
        viewModel.toolMode == .textBox
    }

    private var selectedIsComment: Bool {
        if let id = viewModel.selectedAnnotationID {
            return viewModel.sidecar.comments.contains { $0.id == id }
        }
        return false
    }

    private var selectedIsTextBox: Bool {
        if let id = viewModel.selectedAnnotationID {
            return viewModel.sidecar.textBoxes.contains { $0.id == id }
        }
        return false
    }

    private var isDrawModeActive: Bool {
        viewModel.toolMode == .draw
    }

    private var selectedIsShape: Bool {
        if let id = viewModel.selectedAnnotationID {
            return viewModel.sidecar.shapes.contains { $0.id == id }
        }
        return false
    }

    private var showInspector: Binding<Bool> {
        Binding(
            get: {
                isCommentModeActive || isTextBoxModeActive || isDrawModeActive ||
                viewModel.selectedAnnotationID != nil
            },
            set: { newValue in
                if !newValue {
                    viewModel.selectedAnnotationID = nil
                    if isCommentModeActive || isTextBoxModeActive || isDrawModeActive {
                        viewModel.toolMode = .select
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if isCommentModeActive || selectedIsComment {
            CommentsPanel(
                viewModel: viewModel,
                selectedCommentID: selectedIsComment ? viewModel.selectedAnnotationID : nil
            )
        } else if isTextBoxModeActive || selectedIsTextBox {
            TextBoxesPanel(
                viewModel: viewModel,
                selectedTextBoxID: selectedIsTextBox ? viewModel.selectedAnnotationID : nil
            )
        } else if selectedIsShape {
            ShapeInspector(viewModel: viewModel, shapeID: viewModel.selectedAnnotationID!)
        } else if isDrawModeActive {
            Text("Click and drag to draw a shape")
                .foregroundStyle(.secondary)
        } else if let id = viewModel.selectedAnnotationID {
            if viewModel.sidecar.stamps.contains(where: { $0.id == id }) {
                StampInspector(viewModel: viewModel, stampID: id)
            } else {
                Text("Select an annotation")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Select an annotation")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Delete Page Confirmation

    private var deletePageDialogTitle: String {
        let count = viewModel.pendingDeletePageIndices.count
        if count == 1, let idx = viewModel.pendingDeletePageIndices.first {
            return "Delete page \(idx + 1)?"
        }
        return "Delete \(count) pages?"
    }

    // MARK: - Export

    private func exportAsPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]

        let baseName = document.pdfDocument.documentURL?
            .deletingPathExtension().lastPathComponent ?? "Exported"
        savePanel.nameFieldStringValue = baseName + ".pdf"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            if let data = DocumentExporter.exportFlattenedPDF(from: document) {
                try? data.write(to: url)
            }
        }
    }

    private func exportAsText() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]

        let baseName = document.pdfDocument.documentURL?
            .deletingPathExtension().lastPathComponent ?? "Exported"
        savePanel.nameFieldStringValue = baseName + ".txt"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try TextExportService.export(
                    document: document.pdfDocument,
                    to: url
                )
            } catch {
                let alert = NSAlert()
                alert.messageText = "Text Export Error"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func exportAsWord() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "docx")!]

        // Default to PDF base name with .docx extension
        let baseName = document.pdfDocument.documentURL?
            .deletingPathExtension().lastPathComponent ?? "Exported"
        savePanel.nameFieldStringValue = baseName + ".docx"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            viewModel.startWordExport(to: url)
        }
    }

    private func exportTableAsCSV(_ table: TableExtractionService.ExtractedTable) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "Table.csv"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try table.toCSV().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                viewModel.tableExportError = error.localizedDescription
            }
        }
    }

    private func exportTablesAsExcel(_ tables: [TableExtractionService.ExtractedTable]) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        savePanel.nameFieldStringValue = "Tables.xlsx"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try ExcelExportService.export(tables: tables, to: url)
            } catch {
                viewModel.tableExportError = error.localizedDescription
            }
        }
    }
}
