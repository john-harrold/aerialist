import PDFKit
import AppKit

@MainActor
enum FileCombinerService {

    /// Combine multiple files (PDFs and images) into a single PDFDocument with bookmarks.
    static func combine(files: [URL]) -> PDFDocument? {
        let pairs = files.map { (url: $0, label: $0.deletingPathExtension().lastPathComponent) }
        return combineWithLabels(files: pairs)
    }

    /// Combine files with custom bookmark labels (for collection export).
    static func combineWithLabels(files: [(url: URL, label: String)]) -> PDFDocument? {
        let combined = PDFDocument()
        let outline = PDFOutline()

        for (fileURL, label) in files {
            let startPage = combined.pageCount

            let ext = fileURL.pathExtension.lowercased()

            if ext == "pdf" {
                guard let pdf = PDFDocument(url: fileURL) else { continue }
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i) {
                        combined.insert(page, at: combined.pageCount)
                    }
                }
            } else if ext == "docx" || ext == "doc" {
                if let pdf = convertWordToPDF(url: fileURL) {
                    for i in 0..<pdf.pageCount {
                        if let page = pdf.page(at: i) {
                            combined.insert(page, at: combined.pageCount)
                        }
                    }
                }
            } else {
                // Image file
                if let page = ImageToPDFService.createPDFPage(from: fileURL) {
                    combined.insert(page, at: combined.pageCount)
                }
            }

            // Create bookmark for this source file
            if combined.pageCount > startPage,
               let bookmarkPage = combined.page(at: startPage) {
                let bookmark = PDFOutline()
                bookmark.label = label
                bookmark.destination = PDFDestination(page: bookmarkPage, at: .zero)
                outline.insertChild(bookmark, at: outline.numberOfChildren)
            }
        }

        combined.outlineRoot = outline
        return combined.pageCount > 0 ? combined : nil
    }

    // MARK: - Word to PDF Conversion

    /// Convert a Word document to PDF.
    /// Tries: Microsoft Word → LibreOffice → Pandoc → NSAttributedString fallback.
    private static func convertWordToPDF(url: URL) -> PDFDocument? {
        // 1. Microsoft Word via docx2pdf (best fidelity)
        if let pdf = convertViaWord(url: url) { return pdf }

        // 2. LibreOffice headless (near-Word fidelity)
        if let pdf = convertViaLibreOffice(url: url) { return pdf }

        // 3. Pandoc (decent fidelity)
        if let pdf = convertViaPandoc(url: url) { return pdf }

        // 4. NSAttributedString fallback (basic formatting only)
        return convertViaNSAttributedString(url: url)
    }

    /// Convert docx via Microsoft Word using the bundled Python's docx2pdf.
    private static func convertViaWord(url: URL) -> PDFDocument? {
        // Check if Word is installed
        let wordPath = "/Applications/Microsoft Word.app"
        guard FileManager.default.fileExists(atPath: wordPath) else { return nil }

        // Find the bundled Python
        guard let pythonURL = findBundledPython() else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputURL = tempDir.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + ".pdf"
        )

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", """
            from docx2pdf import convert
            convert('\(url.path.replacingOccurrences(of: "'", with: "\\'"))', \
                    '\(outputURL.path.replacingOccurrences(of: "'", with: "\\'"))')
            """]

        // Suppress docx2pdf's tqdm output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return PDFDocument(url: outputURL)
    }

    /// Convert docx via Pandoc.
    private static func convertViaPandoc(url: URL) -> PDFDocument? {
        // Check common Pandoc locations
        let pandocPaths = [
            "/usr/local/bin/pandoc",
            "/opt/homebrew/bin/pandoc",
            "/usr/bin/pandoc"
        ]
        guard let pandocPath = pandocPaths.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputURL = tempDir.appendingPathComponent("output.pdf")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pandocPath)
        process.arguments = [url.path, "-o", outputURL.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return PDFDocument(url: outputURL)
    }

    /// Convert docx via LibreOffice headless mode.
    private static func convertViaLibreOffice(url: URL) -> PDFDocument? {
        let sofficePaths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice"
        ]
        guard let sofficePath = sofficePaths.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sofficePath)
        process.arguments = [
            "--headless",
            "--convert-to", "pdf",
            "--outdir", tempDir.path,
            url.path
        ]
        // Prevent LibreOffice from conflicting with a running instance
        process.environment = [
            "HOME": NSHomeDirectory(),
            "UserInstallation": "file://\(tempDir.path)/libreoffice-user"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        // LibreOffice names the output after the input file
        let outputName = url.deletingPathExtension().lastPathComponent + ".pdf"
        let outputURL = tempDir.appendingPathComponent(outputName)
        return PDFDocument(url: outputURL)
    }

    /// Fallback: convert docx via NSAttributedString (basic formatting only).
    private static func convertViaNSAttributedString(url: URL) -> PDFDocument? {
        let attrString: NSAttributedString
        if let s = try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        ) {
            attrString = s
        } else if let s = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            attrString = s
        } else {
            return nil
        }
        guard attrString.length > 0 else { return nil }

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 72
        let textWidth = pageWidth - margin * 2
        let textHeight = pageHeight - margin * 2

        let textStorage = NSTextStorage(attributedString: attrString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        // Create pages by adding text containers until all text is laid out
        var textContainers: [NSTextContainer] = []
        var allGlyphsLaidOut = false
        while !allGlyphsLaidOut {
            let container = NSTextContainer(
                containerSize: NSSize(width: textWidth, height: textHeight)
            )
            layoutManager.addTextContainer(container)
            textContainers.append(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length == 0 && textContainers.count > 1 {
                break
            }
            // Check if this container holds the last glyph
            let totalGlyphs = layoutManager.numberOfGlyphs
            if glyphRange.location + glyphRange.length >= totalGlyphs {
                allGlyphsLaidOut = true
            }
        }

        // Render each container as a PDF page
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for container in textContainers {
            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { continue }

            context.beginPDFPage(nil)
            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext

            // Translate to page margins, flip coordinates
            context.translateBy(x: margin, y: pageHeight - margin)
            context.scaleBy(x: 1, y: -1)

            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        context.closePDF()
        return PDFDocument(data: pdfData as Data)
    }

    /// Find the bundled Python in the app's Resources.
    private static func findBundledPython() -> URL? {
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("python/bin/python3")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        // Fallback: system python3
        let systemPython = URL(fileURLWithPath: "/usr/bin/python3")
        if FileManager.default.fileExists(atPath: systemPython.path) {
            return systemPython
        }
        return nil
    }
}
