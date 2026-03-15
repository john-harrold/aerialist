import ArgumentParser
import Foundation
import PDFKit

struct TextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Extract text from a PDF file"
    )

    @Argument(help: "Input PDF file path")
    var input: String

    @Argument(help: "Output text file path (default: input with .txt extension)")
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
                .appendingPathExtension("txt").path
        }

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

        if let pagesStr = pages {
            pageIndices = pagesStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if verbose {
                print("Extracting pages: \(pageIndices!.map(String.init).joined(separator: ", "))")
            }
        } else if start != nil || end != nil {
            let s = start ?? 0
            let e = end ?? pageCount
            pageIndices = Array(s..<e)
            if verbose {
                print("Extracting pages \(s) to \(e)")
            }
        }

        print("Extracting text from \(input)...")

        do {
            try TextExportService.export(
                inputPath: inputURL.path,
                to: outputPath,
                pages: pageIndices
            )

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
