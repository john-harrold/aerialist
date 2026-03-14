import SwiftUI

struct HelpView: View {
    enum Topic: String, CaseIterable, Identifiable {
        case wordExport = "Word Export (CLI)"
        case tableExtraction = "Table Extraction (CLI)"
        case autoTableDetection = "Auto Table Detection"
        case manualTableSelection = "Manual Table Selection"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .wordExport: return "doc.richtext"
            case .tableExtraction: return "tablecells"
            case .autoTableDetection: return "sparkle.magnifyingglass"
            case .manualTableSelection: return "rectangle.dashed"
            }
        }
    }

    @State private var selectedTopic: Topic? = .wordExport

    var body: some View {
        NavigationSplitView {
            List(Topic.allCases, selection: $selectedTopic) { topic in
                Label(topic.rawValue, systemImage: topic.systemImage)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let topic = selectedTopic {
                ScrollView {
                    detailContent(for: topic)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Select a topic")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(for topic: Topic) -> some View {
        switch topic {
        case .wordExport:
            wordExportContent
        case .tableExtraction:
            tableExtractionContent
        case .autoTableDetection:
            autoTableDetectionContent
        case .manualTableSelection:
            manualTableSelectionContent
        }
    }

    // MARK: - Word Export

    private var wordExportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Word Export (CLI)")
                .font(.title).bold()

            Text("Convert PDF pages to a Word document using the command-line tool.")

            sectionHeader("Usage")
            codeBlock("AerialistCLI convert <input.pdf> [output.docx]")

            Text("If no output path is given, the output file is written next to the input with a .docx extension.")

            sectionHeader("Options")
            optionRow("--start N", "First page to convert (0-indexed). Default: 0")
            optionRow("--end N", "Page after the last page to convert (exclusive, 0-indexed). Default: all pages")
            optionRow("--pages 0,2,4", "Comma-separated list of specific pages to convert (0-indexed)")
            optionRow("--verbose", "Print progress information")

            sectionHeader("Examples")
            Text("Convert an entire PDF:").bold()
            codeBlock("AerialistCLI convert report.pdf")

            Text("Convert pages 1\u{2013}3 (0-indexed):").bold()
            codeBlock("AerialistCLI convert report.pdf --start 0 --end 3")

            Text("Convert specific pages:").bold()
            codeBlock("AerialistCLI convert report.pdf output.docx --pages 0,2,4")
        }
    }

    // MARK: - Table Extraction

    private var tableExtractionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Table Extraction (CLI)")
                .font(.title).bold()

            Text("Extract tables from a PDF into an Excel workbook using the command-line tool.")

            sectionHeader("Usage")
            codeBlock("AerialistCLI tables <input.pdf> [output.xlsx]")

            Text("If no output path is given, the output file is written next to the input with a .xlsx extension. Each detected table is placed on its own sheet.")

            sectionHeader("Options")
            optionRow("--pages 1,3,5", "Comma-separated list of pages to scan (1-indexed). Default: all pages")
            optionRow("--method auto|lines|text|ocr", "Detection method to use. Default: auto")
            optionRow("--verbose", "Print progress information")

            sectionHeader("Examples")
            Text("Extract tables from all pages:").bold()
            codeBlock("AerialistCLI tables data.pdf")

            Text("Use a specific detection method:").bold()
            codeBlock("AerialistCLI tables data.pdf --method lines")

            Text("Extract from specific pages:").bold()
            codeBlock("AerialistCLI tables data.pdf results.xlsx --pages 1,3,5")
        }
    }

    // MARK: - Auto Table Detection

    private var autoTableDetectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto Table Detection")
                .font(.title).bold()

            Text("When extracting tables, Aerialist offers four detection methods. You can choose a method from the detection method picker in the table toolbar, or pass --method on the command line.")

            methodSection(
                name: "Auto (default)",
                description: "Tries multiple strategies in order: first rules-based detection (using horizontal rules as table borders), then the Lines strategy, then the Text strategy with false-positive filtering. This is the best general-purpose choice for most documents."
            )

            methodSection(
                name: "Lines",
                description: "Uses vector lines and rectangles in the PDF structure to identify table borders. Works best for tables that have visible gridlines or cell borders drawn in the PDF."
            )

            methodSection(
                name: "Text",
                description: "Clusters text elements by positional alignment to detect columns and rows. Works best for borderless tables that have well-aligned columns. Applies aggressive filtering to reject body text that might look like a table: rejects regions taller than 50% of the page height, regions with 2 or fewer columns, regions with more than 70% empty cells, and regions with long text cells."
            )

            methodSection(
                name: "OCR",
                description: "Renders the page as an image and uses Apple\u{2019}s Vision framework to perform text recognition. Clusters OCR results into rows and columns by spatial proximity. This is the only method that works on scanned documents where text is embedded in images rather than in the PDF structure. It is slower than the other methods."
            )
        }
    }

    // MARK: - Manual Table Selection

    private var manualTableSelectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual Table Selection")
                .font(.title).bold()

            Text("Use Manual mode when automatic detection does not find a table, or when you want to extract a specific region of the page.")

            sectionHeader("Drawing Table Regions")
            bulletList([
                "Switch to Manual mode in the table toolbar.",
                "The cursor changes to a crosshair. Click and drag on the PDF to draw a rectangle around a table.",
                "You can draw multiple boxes \u{2014} each one is added to the list.",
                "Click a box to select it. Resize handles appear at the corners and edges.",
                "Drag the body of a selected box to move it; drag a handle to resize.",
                "Press Delete to remove the selected box.",
            ])

            sectionHeader("Previewing Extracted Data")
            bulletList([
                "Click Preview to extract data from all drawn regions.",
                "The preview opens with three tabs: Image, Grid, and Data.",
            ])

            sectionHeader("Adjusting the Grid")
            bulletList([
                "In the Grid tab, red lines represent column boundaries and blue lines represent row boundaries.",
                "Drag a line to adjust its position.",
                "Right-click on the grid to add a new column or row line at that location.",
                "Select a line and press Delete to remove it.",
                "Use the +/\u{2013} buttons or toolbar zoom controls to zoom in and out.",
                "Click Apply to Data to re-extract the table using the adjusted grid positions.",
            ])

            sectionHeader("Exporting")
            bulletList([
                "In the Data tab, review the extracted cell values.",
                "Export to Excel (.xlsx) or CSV from the Data tab toolbar.",
            ])
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3).bold()
            .padding(.top, 4)
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.body, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .textSelection(.enabled)
    }

    private func optionRow(_ option: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(option)
                .font(.system(.body, design: .monospaced))
                .frame(width: 180, alignment: .leading)
            Text(description)
        }
    }

    private func methodSection(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.headline)
            Text(description)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("\u{2022}")
                    Text(item)
                }
            }
        }
    }
}
