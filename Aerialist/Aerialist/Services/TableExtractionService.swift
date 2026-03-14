import Foundation
import PDFKit

/// Extracts tabular data from PDF files using PyMuPDF's find_tables().
///
/// Launches table_extract.py as a subprocess and parses structured JSON
/// output. Supports automatic table detection and manual region extraction.
enum TableExtractionService {

    // MARK: - Types

    /// An extracted table as a 2D grid of strings with page location metadata.
    struct ExtractedTable: Sendable {
        var cells: [[String]]
        var pageIndex: Int
        var bbox: CGRect
        var colPositions: [CGFloat]  // x-positions of column boundaries (PDFKit coords)
        var rowPositions: [CGFloat]  // y-positions of row boundaries (PDFKit coords)

        var rowCount: Int { cells.count }
        var columnCount: Int { cells.first?.count ?? 0 }

        /// Convert the table to CSV format.
        func toCSV() -> String {
            cells.map { row in
                row.map { cell in
                    if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                        return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    }
                    return cell
                }.joined(separator: ",")
            }.joined(separator: "\n")
        }
    }

    enum TableExtractionError: LocalizedError {
        case noDocument
        case pythonNotFound
        case helperScriptNotFound
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDocument:
                return "No PDF document to extract tables from."
            case .pythonNotFound:
                return "Python 3 with PyMuPDF not found."
            case .helperScriptNotFound:
                return "Table extraction helper script (table_extract.py) not found in app resources."
            case .extractionFailed(let reason):
                return "Table extraction failed: \(reason)"
            }
        }
    }

    // MARK: - Public API

    /// Auto-detect and extract all tables on the specified pages.
    /// - Parameters:
    ///   - inputPath: Path to the PDF file.
    ///   - pages: 0-indexed page numbers. If nil, processes all pages.
    ///   - strategy: PyMuPDF detection strategy ("lines", "text", or nil for auto).
    ///   - progress: Called with (currentPage, totalPages) as pages are processed.
    /// - Returns: Array of extracted tables across all pages.
    static func detectAndExtract(
        inputPath: String,
        pages: [Int]? = nil,
        strategy: String? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> [ExtractedTable] {
        var args: [String] = [inputPath]
        if let pages = pages {
            args += ["--pages", pages.map(String.init).joined(separator: ",")]
        }
        if let strategy = strategy {
            args += ["--strategy", strategy]
        }
        return try await runHelper(args: args, progress: progress)
    }

    /// Extract tables from a manual region on the specified pages.
    /// - Parameters:
    ///   - inputPath: Path to the PDF file.
    ///   - pages: 0-indexed page numbers to apply the clip region to.
    ///   - clip: Region in PDFKit page coordinates (origin at bottom-left).
    ///   - pageHeight: Height of the PDF page, used for coordinate conversion.
    ///   - strategy: Detection strategy ("lines" or "text"). Defaults to trying both.
    /// - Returns: Array of extracted tables in the region across all pages.
    static func extractFromRegion(
        inputPath: String,
        pages: [Int],
        clip: CGRect,
        pageHeight: CGFloat,
        strategy: String? = nil
    ) async throws -> [ExtractedTable] {
        // Convert clip from PDFKit (bottom-left origin) to PyMuPDF (top-left origin)
        let pyClip = CGRect(
            x: clip.minX,
            y: pageHeight - clip.maxY,
            width: clip.width,
            height: clip.height
        )
        var args: [String] = [
            inputPath,
            "--pages", pages.map(String.init).joined(separator: ","),
            "--clip", "\(pyClip.minX),\(pyClip.minY),\(pyClip.maxX),\(pyClip.maxY)",
        ]
        if let strategy = strategy {
            args += ["--strategy", strategy]
        }
        return try await runHelper(args: args, progress: { _, _ in })
    }

    /// Extract from a known table region using text strategy without false-positive filtering.
    /// Used for re-extraction after resize/move where the clip already defines the table.
    static func extractFromKnownRegion(
        inputPath: String,
        page: Int,
        clip: CGRect,
        pageHeight: CGFloat
    ) async throws -> [ExtractedTable] {
        let pyClip = CGRect(
            x: clip.minX,
            y: pageHeight - clip.maxY,
            width: clip.width,
            height: clip.height
        )
        let args: [String] = [
            inputPath,
            "--pages", String(page),
            "--clip", "\(pyClip.minX),\(pyClip.minY),\(pyClip.maxX),\(pyClip.maxY)",
            "--force-text",
        ]
        return try await runHelper(args: args, progress: { _, _ in })
    }

    /// Extract a table using user-defined grid line positions.
    static func extractWithGrid(
        inputPath: String,
        page: Int,
        clip: CGRect,
        pageHeight: CGFloat,
        colPositions: [CGFloat],   // PDFKit coords (x-values, no conversion needed)
        rowPositions: [CGFloat]    // PDFKit coords (y-values, need flip)
    ) async throws -> [ExtractedTable] {
        let pyClip = CGRect(
            x: clip.minX,
            y: pageHeight - clip.maxY,
            width: clip.width,
            height: clip.height
        )
        // Convert row y-positions from PDFKit (bottom-left) to PyMuPDF (top-left)
        let pyRowPositions = rowPositions.map { pageHeight - $0 }.sorted()
        let colStr = colPositions.map { String(format: "%.2f", $0) }.joined(separator: ",")
        let rowStr = pyRowPositions.map { String(format: "%.2f", $0) }.joined(separator: ",")

        let args: [String] = [
            inputPath,
            "--pages", String(page),
            "--clip", "\(pyClip.minX),\(pyClip.minY),\(pyClip.maxX),\(pyClip.maxY)",
            "--col-positions", colStr,
            "--row-positions", rowStr,
        ]
        return try await runHelper(args: args, progress: { _, _ in })
    }

    // MARK: - Subprocess Execution

    /// Run the table_extract.py helper and parse its JSON output.
    private static func runHelper(
        args: [String],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [ExtractedTable] {
        let pythonPath = try findPython()
        let scriptPath = try findHelperScript()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath] + args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let bundledPythonDir = bundledPythonDirectory() {
            var env = ProcessInfo.processInfo.environment
            env["PYTHONHOME"] = bundledPythonDir
            process.environment = env
        }

        try process.run()

        let fileHandle = stdoutPipe.fileHandleForReading
        var tables: [ExtractedTable] = []
        var lastError: String?

        // Read JSON lines as they arrive
        while true {
            let lineData = fileHandle.availableData
            guard !lineData.isEmpty else {
                break
            }

            let rawLines = String(data: lineData, encoding: .utf8) ?? ""
            for line in rawLines.components(separatedBy: "\n") where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = obj["status"] as? String else {
                    continue
                }

                switch status {
                case "progress":
                    if let page = obj["page"] as? Int,
                       let total = obj["total_pages"] as? Int {
                        Task { @MainActor in
                            progress(page, total)
                        }
                    }

                case "table":
                    if let table = parseTable(from: obj) {
                        tables.append(table)
                    }

                case "error":
                    lastError = obj["message"] as? String

                case "complete":
                    break

                default:
                    break
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0, let error = lastError {
            throw TableExtractionError.extractionFailed(error)
        }

        return tables
    }

    /// Parse a table JSON object into an ExtractedTable.
    /// Converts bbox from PyMuPDF coordinates (top-left origin) to PDFKit coordinates (bottom-left origin).
    private static func parseTable(from obj: [String: Any]) -> ExtractedTable? {
        guard let pageIndex = obj["page"] as? Int,
              let bboxArray = obj["bbox"] as? [Double],
              bboxArray.count == 4,
              let cellsRaw = obj["cells"] as? [[Any]] else {
            return nil
        }

        let pageHeight = obj["page_height"] as? Double ?? 792.0
        let width = bboxArray[2] - bboxArray[0]
        let height = bboxArray[3] - bboxArray[1]

        // Convert from PyMuPDF (top-left origin) to PDFKit (bottom-left origin)
        let bbox = CGRect(
            x: bboxArray[0],
            y: pageHeight - bboxArray[3],
            width: width,
            height: height
        )

        let cells: [[String]] = cellsRaw.map { row in
            row.map { cell in
                if let s = cell as? String { return s }
                return String(describing: cell)
            }
        }

        guard !cells.isEmpty else { return nil }

        // Parse grid positions (convert y from PyMuPDF to PDFKit coords)
        var colPositions: [CGFloat] = []
        if let colPosRaw = obj["col_positions"] as? [Double] {
            colPositions = colPosRaw.map { CGFloat($0) }
        }
        var rowPositions: [CGFloat] = []
        if let rowPosRaw = obj["row_positions"] as? [Double] {
            // Flip y-coordinates from PyMuPDF (top-left) to PDFKit (bottom-left)
            rowPositions = rowPosRaw.map { CGFloat(pageHeight - $0) }.reversed()
        }

        return ExtractedTable(
            cells: cells, pageIndex: pageIndex, bbox: bbox,
            colPositions: colPositions, rowPositions: rowPositions
        )
    }

    // MARK: - Python Discovery

    /// Returns the path to the bundled Python directory, if it exists.
    private static func bundledPythonDirectory() -> String? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledPython = resourceURL.appendingPathComponent("python")
            if FileManager.default.fileExists(atPath: bundledPython.path) {
                return bundledPython.path
            }
        }
        return nil
    }

    /// Find a Python 3 interpreter with PyMuPDF installed.
    private static func findPython() throws -> String {
        // 1. Check for bundled Python
        if let bundledDir = bundledPythonDirectory() {
            let bundledPython = (bundledDir as NSString).appendingPathComponent("bin/python3")
            if FileManager.default.isExecutableFile(atPath: bundledPython) {
                return bundledPython
            }
        }

        // 2. Check common system Python locations
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate),
               hasPyMuPDF(pythonPath: candidate) {
                return candidate
            }
        }

        // 3. Try `which python3`
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["python3"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice
        try? whichProcess.run()
        whichProcess.waitUntilExit()

        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, hasPyMuPDF(pythonPath: path) {
                return path
            }
        }

        throw TableExtractionError.pythonNotFound
    }

    /// Check if a Python interpreter has PyMuPDF installed.
    private static func hasPyMuPDF(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import fitz"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Find the table_extract.py helper script.
    private static func findHelperScript() throws -> String {
        // 1. Check app bundle resources
        if let resourceURL = Bundle.main.resourceURL {
            let bundledScript = resourceURL.appendingPathComponent("table_extract.py")
            if FileManager.default.fileExists(atPath: bundledScript.path) {
                return bundledScript.path
            }
        }

        // 2. Check relative to executable (for CLI tool)
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let adjacentScript = executableURL.deletingLastPathComponent()
            .appendingPathComponent("table_extract.py")
        if FileManager.default.fileExists(atPath: adjacentScript.path) {
            return adjacentScript.path
        }

        // 3. Check Resources directory relative to project structure (development)
        let devPaths = [
            "Aerialist/Aerialist/Resources/table_extract.py",
            "../Aerialist/Aerialist/Resources/table_extract.py",
        ]
        for devPath in devPaths {
            let fullPath = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(devPath)
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        throw TableExtractionError.helperScriptNotFound
    }
}
