import ArgumentParser
import Foundation
import PDFKit

struct ConvertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert a PDF file to DOCX format"
    )

    @Argument(help: "Input PDF file path")
    var input: String

    @Argument(help: "Output DOCX file path (default: input with .docx extension)")
    var output: String?

    @Option(name: .long, help: "Start page (0-indexed)")
    var start: Int?

    @Option(name: .long, help: "End page (exclusive)")
    var end: Int?

    @Option(name: .long, help: "Comma-separated page indices (overrides --start/--end)")
    var pages: String?

    @Flag(name: .shortAndLong, help: "Show detailed progress")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        // Validate input file
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ValidationError("Input file not found: \(input)")
        }

        // Determine output path
        let outputPath: String
        if let output = output {
            outputPath = output
        } else {
            outputPath = inputURL.deletingPathExtension()
                .appendingPathExtension("docx").path
        }
        let outputURL = URL(fileURLWithPath: outputPath)

        // Load PDF to get page count for progress display
        guard let pdfDoc = PDFDocument(url: inputURL) else {
            throw ValidationError("Failed to open PDF: \(input)")
        }
        let pageCount = pdfDoc.pageCount

        if verbose {
            print("Input:  \(input)")
            print("Output: \(outputPath)")
            print("Pages:  \(pageCount)")
            print()
        }

        // Parse page selection
        var pageIndices: [Int]?
        var startPage = 0
        var endPage: Int?

        if let pagesStr = pages {
            pageIndices = pagesStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if verbose {
                print("Converting pages: \(pageIndices!.map(String.init).joined(separator: ", "))")
            }
        } else {
            if let s = start { startPage = s }
            if let e = end { endPage = e }
            if verbose && (startPage > 0 || endPage != nil) {
                print("Converting pages \(startPage) to \(endPage ?? pageCount)")
            }
        }

        print("Converting \(input) to DOCX...")

        do {
            try await WordExportService.export(
                inputPath: inputURL.path,
                to: outputPath,
                startPage: startPage,
                endPage: endPage,
                pages: pageIndices
            ) { page in
                if verbose {
                    print("  Progress: page \(page + 1)")
                }
            }

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
