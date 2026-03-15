import SwiftUI
import PDFKit

/// Shows extracted tables in a scrollable grid with a picker for multiple tables.
/// Includes a Data/Grid tab switcher: Data shows extracted cell text, Grid shows the
/// PDF region with draggable grid lines for adjusting column/row boundaries.
struct TablePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var viewTab: ViewTab = .data
    @State private var editedColPositions: [Int: [CGFloat]] = [:]
    @State private var editedRowPositions: [Int: [CGFloat]] = [:]
    @State private var gridModified = false

    enum ViewTab: String, CaseIterable {
        case data = "Data"
        case grid = "Grid"
    }

    let tables: [TableExtractionService.ExtractedTable]
    var initialPageIndex: Int = 0
    var pdfDocument: PDFDocument?
    var onExportCSV: (TableExtractionService.ExtractedTable) -> Void
    var onExportAllExcel: () -> Void
    var onReExtractWithGrid: ((Int, [CGFloat], [CGFloat]) -> Void)?

    private var selectedTable: TableExtractionService.ExtractedTable? {
        guard selectedIndex < tables.count else { return nil }
        return tables[selectedIndex]
    }

    private var colPositionsBinding: Binding<[CGFloat]> {
        Binding(
            get: { editedColPositions[selectedIndex] ?? selectedTable?.colPositions ?? [] },
            set: { newValue in
                editedColPositions[selectedIndex] = newValue
                gridModified = true
            }
        )
    }

    private var rowPositionsBinding: Binding<[CGFloat]> {
        Binding(
            get: { editedRowPositions[selectedIndex] ?? selectedTable?.rowPositions ?? [] },
            set: { newValue in
                editedRowPositions[selectedIndex] = newValue
                gridModified = true
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentSection
            Divider()
            actionButtons
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
        .onAppear {
            if let idx = tables.firstIndex(where: { $0.pageIndex == initialPageIndex }) {
                selectedIndex = idx
            }
        }
        .onChange(of: viewTab) { oldTab, newTab in
            // Auto-apply grid changes when switching from Grid to Data
            if oldTab == .grid && newTab == .data && gridModified {
                applyGridChanges()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Table Preview")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Picker("View", selection: $viewTab) {
                    ForEach(ViewTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Text(summaryText)
                    .foregroundStyle(.secondary)
            }

            if tables.count > 1 {
                tableNavigator
            }
        }
        .padding()
    }

    private var tableNavigator: some View {
        HStack(spacing: 8) {
            Button {
                if selectedIndex > 0 { selectedIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIndex <= 0)

            Menu {
                ForEach(Array(tables.enumerated()), id: \.offset) { i, table in
                    Button {
                        selectedIndex = i
                    } label: {
                        if i == selectedIndex {
                            Label("Table \(i + 1) (Page \(table.pageIndex + 1)) \u{2014} \(table.rowCount)\u{00D7}\(table.columnCount)", systemImage: "checkmark")
                        } else {
                            Text("Table \(i + 1) (Page \(table.pageIndex + 1)) \u{2014} \(table.rowCount)\u{00D7}\(table.columnCount)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let table = selectedTable {
                        Text("Table \(selectedIndex + 1) (Page \(table.pageIndex + 1)) \u{2014} \(table.rowCount)\u{00D7}\(table.columnCount)")
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                if selectedIndex < tables.count - 1 { selectedIndex += 1 }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIndex >= tables.count - 1)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch viewTab {
        case .data:
            tableGridSection
        case .grid:
            gridOverlaySection
        }
    }

    private var tableGridSection: some View {
        Group {
            if let table = selectedTable {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(Array(table.cells.enumerated()), id: \.offset) { rowIndex, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                    Text(cell)
                                        .font(rowIndex == 0 ? .body.bold() : .body)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .frame(minWidth: 80, alignment: .leading)
                                        .background(cellBackground(rowIndex: rowIndex))
                                        .border(Color.gray.opacity(0.3), width: 0.5)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Text("No tables found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var gridOverlaySection: some View {
        if let table = selectedTable {
            VStack(spacing: 4) {
                TableGridOverlayView(
                    pdfDocument: pdfDocument,
                    table: table,
                    colPositions: colPositionsBinding,
                    rowPositions: rowPositionsBinding
                )
                .padding()

                if gridModified {
                    HStack {
                        Text("Grid lines modified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Apply to Data") {
                            applyGridChanges()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.bottom, 4)
                }
            }
        } else {
            Text("No table selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if let table = selectedTable {
                Button("Export CSV") {
                    onExportCSV(table)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Button(tables.count > 1 ? "Export All as Excel" : "Export as Excel") {
                onExportAllExcel()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(tables.isEmpty)
        }
        .padding()
    }

    // MARK: - Actions

    private func applyGridChanges() {
        guard let table = selectedTable else { return }
        let cols = editedColPositions[selectedIndex] ?? table.colPositions
        let rows = editedRowPositions[selectedIndex] ?? table.rowPositions
        guard !cols.isEmpty, !rows.isEmpty else { return }
        onReExtractWithGrid?(selectedIndex, cols, rows)
        gridModified = false
    }

    // MARK: - Helpers

    private var summaryText: String {
        if tables.count == 1, let t = tables.first {
            return "\(t.rowCount) rows \u{00D7} \(t.columnCount) columns"
        }
        let pages = Set(tables.map(\.pageIndex)).count
        return "\(tables.count) table(s) across \(pages) page(s)"
    }

    private func cellBackground(rowIndex: Int) -> Color {
        if rowIndex == 0 {
            return Color.accentColor.opacity(0.1)
        }
        return rowIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.05)
    }
}
