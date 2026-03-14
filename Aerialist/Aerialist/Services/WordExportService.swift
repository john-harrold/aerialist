import Foundation
import PDFKit

/// Converts PDF documents to Word (.docx) files using pdf2docx (Python).
///
/// The service locates a bundled or system Python with pdf2docx installed,
/// launches it as a subprocess with the helper script `pdf2docx_convert.py`,
/// and parses structured JSON progress from stdout.
///
/// Supports `Task` cancellation — terminating the Python process and cleaning
/// up temporary files.
@MainActor
enum WordExportService {

    enum WordExportError: LocalizedError {
        case noDocument
        case pythonNotFound
        case helperScriptNotFound
        case conversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDocument:
                return "No PDF document to export."
            case .pythonNotFound:
                return "Python 3 with pdf2docx not found. The bundled Python may be missing — try reinstalling Aerialist."
            case .helperScriptNotFound:
                return "Conversion helper script (pdf2docx_convert.py) not found in app resources."
            case .conversionFailed(let reason):
                return "Word export failed: \(reason)"
            }
        }
    }

    /// Export a PDF document as a Word (.docx) file.
    /// - Parameters:
    ///   - document: The PDF document to export.
    ///   - sidecar: The sidecar model (reserved for future use).
    ///   - url: The destination file URL.
    ///   - progress: Called with the index of each completed page.
    static func export(
        document: PDFDocument,
        sidecar: SidecarModel,
        to url: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws {
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw WordExportError.noDocument
        }

        // 1. Find Python and the helper script
        let pythonPath = try findPython()
        let scriptPath = try findHelperScript()

        // 2. Write PDF to a temp file (pdf2docx needs a file path)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aerialist_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempPDF = tempDir.appendingPathComponent("input.pdf")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        guard document.write(to: tempPDF) else {
            throw WordExportError.conversionFailed("Failed to write temporary PDF file.")
        }

        // 3. Launch the Python conversion process
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, tempPDF.path, url.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set up environment for bundled Python if applicable
        if let bundledPythonDir = bundledPythonDirectory() {
            var env = ProcessInfo.processInfo.environment
            env["PYTHONHOME"] = bundledPythonDir
            // Add bundled site-packages to PYTHONPATH
            let sitePackages = (bundledPythonDir as NSString)
                .appendingPathComponent("lib")
            let pythonVersionDirs = try? FileManager.default
                .contentsOfDirectory(atPath: sitePackages)
                .filter { $0.hasPrefix("python3") }
            if let pyDir = pythonVersionDirs?.first {
                let pyVersionDir = (sitePackages as NSString).appendingPathComponent(pyDir)
                let fullSitePackages = (pyVersionDir as NSString).appendingPathComponent("site-packages")
                env["PYTHONPATH"] = fullSitePackages
            }
            process.environment = env
        }

        try process.run()

        // 4. Read stdout line-by-line and parse JSON progress
        let fileHandle = stdoutPipe.fileHandleForReading
        var lastError: String?

        // Process output on a background thread
        let outputTask = Task.detached { () -> String? in
            var errorMessage: String?
            let data = fileHandle.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return "Failed to read process output"
            }

            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let jsonData = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let status = json["status"] as? String else {
                    continue
                }

                switch status {
                case "progress":
                    if let page = json["page"] as? Int {
                        await MainActor.run {
                            progress(page)
                        }
                    }
                case "error":
                    errorMessage = json["message"] as? String ?? "Unknown conversion error"
                case "complete":
                    if let pagesConverted = json["pages_converted"] as? Int {
                        await MainActor.run {
                            progress(pagesConverted - 1)
                        }
                    }
                default:
                    break
                }
            }
            return errorMessage
        }

        // 5. Support cancellation
        let cancellationTask = Task.detached {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            if process.isRunning {
                process.terminate()
            }
        }

        // Wait for process to finish
        process.waitUntilExit()
        cancellationTask.cancel()

        // Check for cancellation
        try Task.checkCancellation()

        // Get any error from output parsing
        lastError = await outputTask.value

        // 6. Check exit status
        if process.terminationStatus != 0 {
            if let errorMsg = lastError {
                throw WordExportError.conversionFailed(errorMsg)
            }
            // Try to read stderr for additional info
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            let lastLine = stderrString.components(separatedBy: .newlines)
                .last(where: { !$0.isEmpty }) ?? "Process exited with code \(process.terminationStatus)"
            throw WordExportError.conversionFailed(lastLine)
        }

        if let errorMsg = lastError {
            throw WordExportError.conversionFailed(errorMsg)
        }

        // Verify output file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WordExportError.conversionFailed("Output file was not created.")
        }
    }

    /// Export a PDF file at a path to a Word (.docx) file.
    /// Convenience method for CLI use where the PDF is already on disk.
    static func export(
        inputPath: String,
        to outputPath: String,
        startPage: Int = 0,
        endPage: Int? = nil,
        pages: [Int]? = nil,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws {
        let pythonPath = try findPython()
        let scriptPath = try findHelperScript()

        var args = [scriptPath, inputPath, outputPath]

        if let pages = pages {
            args += ["--pages", pages.map(String.init).joined(separator: ",")]
        } else {
            if startPage > 0 {
                args += ["--start", String(startPage)]
            }
            if let endPage = endPage {
                args += ["--end", String(endPage)]
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = args

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
        var lastError: String?

        let outputTask = Task.detached { () -> String? in
            var errorMessage: String?
            let data = fileHandle.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return "Failed to read process output"
            }

            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let jsonData = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let status = json["status"] as? String else {
                    continue
                }

                switch status {
                case "progress":
                    if let page = json["page"] as? Int {
                        await MainActor.run { progress(page) }
                    }
                case "error":
                    errorMessage = json["message"] as? String ?? "Unknown conversion error"
                case "complete":
                    if let pagesConverted = json["pages_converted"] as? Int {
                        await MainActor.run { progress(pagesConverted - 1) }
                    }
                default:
                    break
                }
            }
            return errorMessage
        }

        let cancellationTask = Task.detached {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        cancellationTask.cancel()

        try Task.checkCancellation()

        lastError = await outputTask.value

        if process.terminationStatus != 0 {
            if let errorMsg = lastError {
                throw WordExportError.conversionFailed(errorMsg)
            }
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            let lastLine = stderrString.components(separatedBy: .newlines)
                .last(where: { !$0.isEmpty }) ?? "Process exited with code \(process.terminationStatus)"
            throw WordExportError.conversionFailed(lastLine)
        }

        if let errorMsg = lastError {
            throw WordExportError.conversionFailed(errorMsg)
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw WordExportError.conversionFailed("Output file was not created.")
        }
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

    /// Find a Python 3 interpreter with pdf2docx installed.
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
            "/opt/homebrew/bin/python3",   // Homebrew on Apple Silicon
            "/usr/local/bin/python3",      // Homebrew on Intel
            "/usr/bin/python3",            // System Python
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate),
               hasPdf2docx(pythonPath: candidate) {
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
            if !path.isEmpty, hasPdf2docx(pythonPath: path) {
                return path
            }
        }

        throw WordExportError.pythonNotFound
    }

    /// Check if a Python interpreter has pdf2docx installed.
    private static func hasPdf2docx(pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import pdf2docx"]
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

    /// Find the pdf2docx_convert.py helper script.
    private static func findHelperScript() throws -> String {
        // 1. Check app bundle resources
        if let resourceURL = Bundle.main.resourceURL {
            let bundledScript = resourceURL.appendingPathComponent("pdf2docx_convert.py")
            if FileManager.default.fileExists(atPath: bundledScript.path) {
                return bundledScript.path
            }
        }

        // 2. Check relative to executable (for CLI tool)
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let adjacentScript = executableURL.deletingLastPathComponent()
            .appendingPathComponent("pdf2docx_convert.py")
        if FileManager.default.fileExists(atPath: adjacentScript.path) {
            return adjacentScript.path
        }

        // 3. Check Resources directory relative to project structure (development)
        let devPaths = [
            // When running from Xcode, the working directory varies
            "Aerialist/Aerialist/Resources/pdf2docx_convert.py",
            "../Aerialist/Aerialist/Resources/pdf2docx_convert.py",
        ]
        for devPath in devPaths {
            let fullPath = (FileManager.default.currentDirectoryPath as NSString)
                .appendingPathComponent(devPath)
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        throw WordExportError.helperScriptNotFound
    }
}
