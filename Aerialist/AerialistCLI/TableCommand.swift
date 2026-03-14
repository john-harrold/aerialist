import ArgumentParser
import Foundation
import PDFKit

struct TableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tables",
        abstract: "Detect and extract tables from a PDF file to Excel"
    )

    @Argument(help: "Input PDF file path")
    var input: String

    @Argument(help: "Output Excel file path (default: input with .xlsx extension)")
    var output: String?

    @Option(name: .long, help: "Comma-separated page numbers (1-indexed)")
    var pages: String?

    @Option(name: .long, help: "Detection method: auto, lines, text, or ocr")
    var method: String = "auto"

    @Flag(name: .shortAndLong, help: "Show detailed progress")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ValidationError("Input file not found: \(input)")
        }

        let validMethods = ["auto", "lines", "text", "ocr"]
        guard validMethods.contains(method) else {
            throw ValidationError("Invalid method '\(method)'. Use: \(validMethods.joined(separator: ", "))")
        }

        // Determine output path
        let outputPath: String
        if let output = output {
            outputPath = output
        } else {
            outputPath = inputURL.deletingPathExtension()
                .appendingPathExtension("xlsx").path
        }
        let outputURL = URL(fileURLWithPath: outputPath)

        // Load PDF to get page count
        guard let pdfDoc = PDFDocument(url: inputURL) else {
            throw ValidationError("Failed to open PDF: \(input)")
        }
        let pageCount = pdfDoc.pageCount

        if verbose {
            print("Input:   \(input)")
            print("Output:  \(outputPath)")
            print("Pages:   \(pageCount)")
            print("Method:  \(method)")
            print()
        }

        // Parse page selection (user provides 1-indexed, convert to 0-indexed)
        var pageIndices: [Int]?
        if let pagesStr = pages {
            pageIndices = pagesStr.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .map { $0 - 1 }
                .filter { $0 >= 0 && $0 < pageCount }

            if verbose {
                print("Scanning pages: \(pageIndices!.map { String($0 + 1) }.joined(separator: ", "))")
            }
        }

        print("Detecting tables in \(input) (method: \(method))...")

        do {
            let tables: [TableExtractionService.ExtractedTable]

            if method == "ocr" {
                // Vision OCR path — uses PDFKit directly
                var allTables: [TableExtractionService.ExtractedTable] = []
                let indicesToScan = pageIndices ?? Array(0..<pageCount)
                for i in indicesToScan {
                    guard let page = pdfDoc.page(at: i) else { continue }
                    if verbose {
                        print("  OCR scanning page \(i + 1) of \(pageCount)...")
                    }
                    let pageTables = try await VisionTableDetector.detectTables(
                        on: page, pageIndex: i
                    )
                    allTables.append(contentsOf: pageTables)
                }
                tables = allTables
            } else {
                // PyMuPDF path
                let strategy: String? = (method == "auto") ? nil : method
                tables = try await TableExtractionService.detectAndExtract(
                    inputPath: inputURL.path,
                    pages: pageIndices,
                    strategy: strategy
                ) { page, total in
                    if verbose {
                        print("  Scanning page \(page + 1) of \(total)...")
                    }
                }
            }

            guard !tables.isEmpty else {
                print("No tables found.")
                return
            }

            if verbose {
                for (i, table) in tables.enumerated() {
                    print("  Table \(i + 1): Page \(table.pageIndex + 1), \(table.rowCount) rows x \(table.columnCount) cols")
                }
                print()
            }

            print("Found \(tables.count) table(s). Exporting to Excel...")

            try ExcelExportService.export(tables: tables, to: outputURL)

            let attrs = try FileManager.default.attributesOfItem(atPath: outputPath)
            let fileSize = attrs[.size] as? Int64 ?? 0
            let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

            print("Done! Output: \(outputPath) (\(fileSizeStr))")
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
