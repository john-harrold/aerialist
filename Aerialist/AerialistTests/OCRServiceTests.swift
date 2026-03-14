import XCTest
import PDFKit
@testable import Aerialist

/// Thread-safe collector for progress page indices.
private final class ProgressTracker: @unchecked Sendable {
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
final class OCRServiceTests: XCTestCase {

    // MARK: - Helpers

    private func loadPDF(named name: String) throws -> PDFDocument {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "pdf") else {
            throw NSError(domain: "OCRServiceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing test resource: \(name).pdf"])
        }
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "OCRServiceTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF: \(name).pdf"])
        }
        return document
    }

    // MARK: - Tests

    func testRecognizeTextOnScannedPage() async throws {
        let document = try loadPDF(named: "scansmpl")
        let page = try XCTUnwrap(document.page(at: 0))

        let result = try await OCRService.recognizeText(on: page)

        XCTAssertFalse(result.lines.isEmpty, "OCR should find text on scanned page")

        let allText = result.lines.map(\.text).joined(separator: " ").uppercased()
        XCTAssertTrue(allText.contains("SLEREXE"), "Expected 'SLEREXE' in recognized text, got: \(allText)")
        XCTAssertTrue(allText.contains("FACSIMILE"), "Expected 'facsimile' in recognized text")

        for line in result.lines {
            XCTAssertGreaterThan(line.confidence, 0, "Confidence should be > 0 for '\(line.text)'")
            XCTAssertGreaterThan(line.boundingBox.width, 0, "Bounding box width should be > 0")
            XCTAssertGreaterThan(line.boundingBox.height, 0, "Bounding box height should be > 0")
        }
    }

    func testRecognizeTextReturnsEmptyForBlankPage() async throws {
        let blankPage = PDFPage()

        let result = try await OCRService.recognizeText(on: blankPage)

        XCTAssertTrue(result.lines.isEmpty, "Blank page should produce no OCR lines, got \(result.lines.count)")
    }

    func testRecognizeAllPages() async throws {
        let document = try loadPDF(named: "scansmpl")
        XCTAssertEqual(document.pageCount, 1, "scansmpl.pdf should have 1 page")

        let tracker = ProgressTracker()
        let results = try await OCRService.recognizeAllPages(in: document) { pageIndex in
            tracker.record(pageIndex)
        }

        let page0Result = try XCTUnwrap(results["0"], "Should have result for page 0")
        XCTAssertEqual(results.count, 1, "Should have exactly 1 page result")

        XCTAssertEqual(tracker.pages.count, 1, "Progress should be called once")
        XCTAssertEqual(tracker.pages, [0], "Progress should report page 0")

        XCTAssertFalse(page0Result.lines.isEmpty, "Page 0 should have recognized lines")
    }

    func testRecognizeAllPagesMultiPage() async throws {
        let document = try loadPDF(named: "PublicWaterMassMailing")
        XCTAssertEqual(document.pageCount, 8, "PublicWaterMassMailing.pdf should have 8 pages")

        let tracker = ProgressTracker()
        let results = try await OCRService.recognizeAllPages(in: document) { pageIndex in
            tracker.record(pageIndex)
        }

        XCTAssertEqual(results.count, 8, "Should have results for all 8 pages")
        for i in 0..<8 {
            XCTAssertNotNil(results[String(i)], "Should have result for page \(i)")
        }

        XCTAssertEqual(tracker.pages.count, 8, "Progress should be called 8 times")
        XCTAssertEqual(tracker.pages, Array(0..<8), "Progress should report pages in order")
    }

    func testBoundingBoxesAreWithinPageBounds() async throws {
        let document = try loadPDF(named: "scansmpl")
        let page = try XCTUnwrap(document.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)

        let result = try await OCRService.recognizeText(on: page)
        XCTAssertFalse(result.lines.isEmpty, "Should have lines to validate")

        for line in result.lines {
            let box = line.boundingBox
            XCTAssertGreaterThanOrEqual(box.x, 0,
                "Bounding box x (\(box.x)) should be >= 0 for '\(line.text)'")
            XCTAssertGreaterThanOrEqual(box.y, 0,
                "Bounding box y (\(box.y)) should be >= 0 for '\(line.text)'")
            XCTAssertLessThanOrEqual(box.x + box.width, pageBounds.width + pageBounds.origin.x,
                "Bounding box right edge should be within page width for '\(line.text)'")
            XCTAssertLessThanOrEqual(box.y + box.height, pageBounds.height + pageBounds.origin.y,
                "Bounding box top edge should be within page height for '\(line.text)'")
        }
    }

    func testOCRResultRoundTripThroughSidecar() async throws {
        let document = try loadPDF(named: "scansmpl")
        let page = try XCTUnwrap(document.page(at: 0))

        let ocrResult = try await OCRService.recognizeText(on: page)
        XCTAssertFalse(ocrResult.lines.isEmpty)

        // Store in sidecar
        var sidecar = SidecarModel()
        sidecar.ocrResults["0"] = ocrResult

        // Encode and decode
        let data = try SidecarIO.encode(sidecar)
        let decoded = try SidecarIO.decode(from: data)

        // Verify round-trip
        let decodedResult = try XCTUnwrap(decoded.ocrResults["0"])
        XCTAssertEqual(decodedResult.lines.count, ocrResult.lines.count,
            "Line count should match after round-trip")

        for (original, roundTripped) in zip(ocrResult.lines, decodedResult.lines) {
            XCTAssertEqual(roundTripped.text, original.text)
            XCTAssertEqual(roundTripped.confidence, original.confidence)
            XCTAssertEqual(roundTripped.boundingBox, original.boundingBox)
        }
    }
}
