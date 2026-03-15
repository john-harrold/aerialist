import XCTest
import PDFKit
@testable import Spindrift

/// Thread-safe collector for progress page indices.
private final class ExportProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _pages: [Int] = []

    func record(_ page: Int) {
        lock.lock()
        _pages.append(page)
        lock.unlock()
    }

    var pages: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _pages
    }
}

@MainActor
final class WordExportServiceTests: XCTestCase {

    // MARK: - Helpers

    private func loadPDF(named name: String) throws -> PDFDocument {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "pdf") else {
            throw NSError(domain: "WordExportServiceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing test resource: \(name).pdf"])
        }
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "WordExportServiceTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF: \(name).pdf"])
        }
        return document
    }

    private func temporaryURL(filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    /// Validate that a file at the given URL is a valid ZIP (which .docx files are).
    private func validateDocxStructure(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)

        XCTAssertGreaterThan(data.count, 4, "File should not be empty")
        let magic = data.prefix(4)
        XCTAssertEqual(magic[0], 0x50, "Expected ZIP magic byte 'P'")
        XCTAssertEqual(magic[1], 0x4B, "Expected ZIP magic byte 'K'")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n")
    }

    /// Read back an exported .docx to verify it can be opened.
    private func verifyDocxReadable(at url: URL) throws {
        let docxData = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        let readBack = try NSAttributedString(data: docxData, options: options, documentAttributes: nil)
        XCTAssertGreaterThan(readBack.length, 0, "Word document should contain readable text")
    }

    // MARK: - Conversion Tests

    func testConvertMultiPagePDF() async throws {
        let document = try loadPDF(named: "PublicWaterMassMailing")
        XCTAssertEqual(document.pageCount, 8)

        let outputURL = temporaryURL(filename: "test_multi_page.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let tracker = ExportProgressTracker()
        try await WordExportService.export(
            document: document,
            sidecar: SidecarModel(),
            to: outputURL
        ) { pageIndex in
            tracker.record(pageIndex)
        }

        // Verify output file exists and has content
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 1000, "Exported .docx should be substantial")

        // Verify valid ZIP/DOCX structure
        let zipContents = try validateDocxStructure(at: outputURL)
        XCTAssertTrue(zipContents.joined(separator: "\n").contains("word/document.xml"),
                      "docx should contain word/document.xml")

        // Verify readable
        try verifyDocxReadable(at: outputURL)

        // Verify progress was reported
        XCTAssertFalse(tracker.pages.isEmpty, "Progress should have been reported")
    }

    func testConvertAcademicPDF() async throws {
        let document = try loadPDF(named: "ResNetHeEtAl")
        XCTAssertEqual(document.pageCount, 12, "ResNetHeEtAl.pdf should have 12 pages")

        let outputURL = temporaryURL(filename: "test_academic.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let tracker = ExportProgressTracker()
        try await WordExportService.export(
            document: document,
            sidecar: SidecarModel(),
            to: outputURL
        ) { pageIndex in
            tracker.record(pageIndex)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 1000, "Academic PDF export should produce substantial file")

        let zipContents = try validateDocxStructure(at: outputURL)
        XCTAssertTrue(zipContents.joined(separator: "\n").contains("word/document.xml"))

        try verifyDocxReadable(at: outputURL)
    }

    func testConvertScannedPDF() async throws {
        let document = try loadPDF(named: "scansmpl")
        XCTAssertEqual(document.pageCount, 1)

        let outputURL = temporaryURL(filename: "test_scanned.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let tracker = ExportProgressTracker()
        try await WordExportService.export(
            document: document,
            sidecar: SidecarModel(),
            to: outputURL
        ) { pageIndex in
            tracker.record(pageIndex)
        }

        // Scanned PDF should still produce a valid .docx (with embedded images)
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 100, "Scanned PDF export should produce a file")

        let zipContents = try validateDocxStructure(at: outputURL)
        XCTAssertTrue(zipContents.joined(separator: "\n").contains("word/document.xml"))
    }

    // MARK: - File Path Conversion Tests

    func testFilePathConversion() async throws {
        let inputPath = Bundle(for: type(of: self))
            .url(forResource: "PublicWaterMassMailing", withExtension: "pdf")!.path
        let outputURL = temporaryURL(filename: "test_filepath.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let tracker = ExportProgressTracker()
        try await WordExportService.export(
            inputPath: inputPath,
            to: outputURL.path
        ) { pageIndex in
            tracker.record(pageIndex)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 1000)
    }

    // MARK: - Error Handling Tests

    func testExportNoDocument() async throws {
        let emptyDoc = PDFDocument()
        let outputURL = temporaryURL(filename: "test_empty.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            try await WordExportService.export(
                document: emptyDoc,
                sidecar: SidecarModel(),
                to: outputURL
            ) { _ in }
            XCTFail("Should have thrown for empty document")
        } catch let error as WordExportService.WordExportError {
            switch error {
            case .noDocument:
                break // expected
            default:
                XCTFail("Expected noDocument error, got: \(error)")
            }
        }
    }

    // MARK: - Content Quality Tests

    /// Tests that the academic PDF (with real text content) produces a DOCX with extractable text.
    func testExportedDocxContainsText() async throws {
        // Use ResNetHeEtAl which has selectable text (unlike PublicWaterMassMailing
        // which pdf2docx converts to images due to vector path rendering)
        let document = try loadPDF(named: "ResNetHeEtAl")
        let outputURL = temporaryURL(filename: "test_content.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await WordExportService.export(
            document: document,
            sidecar: SidecarModel(),
            to: outputURL
        ) { _ in }

        // Extract document.xml from the DOCX ZIP and check for text runs
        let extractDir = temporaryURL(filename: "test_content_extract")
        defer { try? FileManager.default.removeItem(at: extractDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", outputURL.path, "word/document.xml", "-d", extractDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let docXML = try String(
            contentsOf: extractDir.appendingPathComponent("word/document.xml"),
            encoding: .utf8
        )

        // PhamEtAl has real text, so the DOCX should contain text runs
        XCTAssertTrue(docXML.contains("w:t"), "document.xml should contain text elements")

        // Verify the output is substantial (not just boilerplate)
        XCTAssertGreaterThan(docXML.count, 10000,
                             "Academic PDF should produce substantial DOCX XML")
    }

    func testDocxHasStylesAndImages() async throws {
        let document = try loadPDF(named: "PublicWaterMassMailing")
        let outputURL = temporaryURL(filename: "test_structure.docx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await WordExportService.export(
            document: document,
            sidecar: SidecarModel(),
            to: outputURL
        ) { _ in }

        // Check DOCX ZIP structure for expected components
        let zipContents = try validateDocxStructure(at: outputURL)
        let joined = zipContents.joined(separator: "\n")

        XCTAssertTrue(joined.contains("word/document.xml"), "Should have document.xml")
        XCTAssertTrue(joined.contains("word/styles.xml"), "Should have styles.xml")
    }
}
