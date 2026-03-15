import XCTest
import PDFKit
@testable import Spindrift

@MainActor
final class TextExportServiceTests: XCTestCase {

    // MARK: - Helpers

    private func loadPDF(named name: String) throws -> PDFDocument {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "pdf") else {
            throw NSError(domain: "TextExportServiceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing test resource: \(name).pdf"])
        }
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "TextExportServiceTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF: \(name).pdf"])
        }
        return document
    }

    private func temporaryURL(filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    // MARK: - Tests

    func testExportMultiPagePDF() throws {
        let pdf = try loadPDF(named: "ResNetHeEtAl")
        let outputURL = temporaryURL(filename: "text_export_multi.txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try TextExportService.export(document: pdf, to: outputURL)

        let text = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "Exported text should not be empty")
        XCTAssertTrue(text.contains("--- Page 1 ---"), "Should contain page 1 header")
        XCTAssertTrue(text.contains("--- Page 12 ---"), "Should contain page 12 header (last page)")
        XCTAssertTrue(text.count > 1000, "Academic PDF should produce substantial text")
    }

    func testExportWithPageSelection() throws {
        let pdf = try loadPDF(named: "ResNetHeEtAl")
        let outputURL = temporaryURL(filename: "text_export_pages.txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try TextExportService.export(document: pdf, to: outputURL, pages: [0, 2])

        let text = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(text.contains("--- Page 1 ---"), "Should contain page 1")
        XCTAssertTrue(text.contains("--- Page 3 ---"), "Should contain page 3")
        XCTAssertFalse(text.contains("--- Page 2 ---"), "Should NOT contain page 2")
        XCTAssertFalse(text.contains("--- Page 12 ---"), "Should NOT contain page 12")
    }

    func testExportScannedPDF() throws {
        let pdf = try loadPDF(named: "scansmpl")
        let outputURL = temporaryURL(filename: "text_export_scanned.txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Scanned PDFs may produce little or no text — should not throw
        try TextExportService.export(document: pdf, to: outputURL)

        let text = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(text.contains("--- Page 1 ---"), "Should still have page header")
    }

    func testExportFilePathAPI() throws {
        let bundle = Bundle(for: type(of: self))
        guard let inputURL = bundle.url(forResource: "ResNetHeEtAl", withExtension: "pdf") else {
            throw XCTSkip("Test PDF not in bundle")
        }
        let outputURL = temporaryURL(filename: "text_export_path.txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try TextExportService.export(inputPath: inputURL.path, to: outputURL.path)

        let text = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "File-path API should produce text")
        XCTAssertTrue(text.contains("--- Page 1 ---"))
    }

    func testExportNoDocument() throws {
        let emptyDoc = PDFDocument()
        let outputURL = temporaryURL(filename: "text_export_empty.txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        XCTAssertThrowsError(try TextExportService.export(document: emptyDoc, to: outputURL)) { error in
            XCTAssertTrue(error is TextExportService.TextExportError)
        }
    }
}
