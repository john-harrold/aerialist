import XCTest
import PDFKit
@testable import Spindrift

@MainActor
final class TableExtractionServiceTests: XCTestCase {

    // MARK: - Helpers

    private func loadPDF(named name: String) throws -> PDFDocument {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "pdf") else {
            throw NSError(domain: "TableExtractionServiceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing test resource: \(name).pdf"])
        }
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "TableExtractionServiceTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load PDF: \(name).pdf"])
        }
        return document
    }

    private func temporaryURL(filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    // MARK: - Tests

    func testAutoDetectOnTablePDF() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path,
            pages: [0]
        )

        XCTAssertFalse(tables.isEmpty, "Should detect at least one table")
        let table = tables[0]
        XCTAssertGreaterThanOrEqual(table.rowCount, 2, "Table should have at least 2 rows")
        XCTAssertGreaterThanOrEqual(table.columnCount, 2, "Table should have at least 2 columns")
        XCTAssertEqual(table.pageIndex, 0, "Table should be on page 0")
    }

    func testAutoDetectMultiplePages() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path
        )

        // Should find tables on both pages
        XCTAssertGreaterThanOrEqual(tables.count, 2, "Should find tables on multiple pages")
        let pages = Set(tables.map(\.pageIndex))
        XCTAssertTrue(pages.contains(0), "Should have table on page 0")
        XCTAssertTrue(pages.contains(1), "Should have table on page 1")
    }

    func testManualRegionExtraction() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }

        // Use a large clip region covering the full page
        let clip = CGRect(x: 0, y: 0, width: 612, height: 792)
        let tables = try await TableExtractionService.extractFromRegion(
            inputPath: url.path,
            pages: [0],
            clip: clip,
            pageHeight: 792
        )

        XCTAssertFalse(tables.isEmpty, "Should extract at least one table from the region")
    }

    func testExcelMultiSheet() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path
        )

        guard tables.count >= 2 else {
            throw XCTSkip("Need at least 2 tables for multi-sheet test")
        }

        let outputURL = temporaryURL(filename: "multi_sheet_test.xlsx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try ExcelExportService.export(tables: tables, to: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "Excel file should be created")
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(size, 0, "Excel file should not be empty")
    }

    func testNoTablesFound() async throws {
        // ResNetHeEtAl.pdf is a two-column academic paper, not a table
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "scansmpl", withExtension: "pdf") else {
            throw XCTSkip("scansmpl.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path,
            pages: [0]
        )

        // Scanned page with no text — should find no tables
        XCTAssertTrue(tables.isEmpty, "Should find no tables on a scanned page")
    }

    func testCSVExport() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path,
            pages: [0]
        )

        guard let table = tables.first else {
            throw XCTSkip("No tables found for CSV test")
        }

        let csv = table.toCSV()
        XCTAssertFalse(csv.isEmpty, "CSV should not be empty")
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, table.rowCount, "CSV should have one line per row")
    }

    func testVisionDetection() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            throw XCTSkip("Failed to load test_table.pdf")
        }

        let tables = try await VisionTableDetector.detectTables(on: page, pageIndex: 0)

        XCTAssertFalse(tables.isEmpty, "Vision should detect at least one table")
        let table = tables[0]
        XCTAssertGreaterThanOrEqual(table.rowCount, 2, "Table should have at least 2 rows")
        XCTAssertGreaterThanOrEqual(table.columnCount, 2, "Table should have at least 2 columns")
        XCTAssertEqual(table.pageIndex, 0, "Table should be on page 0")
    }

    func testAutoDetectFDATables() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "fda_tables", withExtension: "pdf") else {
            throw XCTSkip("fda_tables.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path
        )

        // FDA PDF has 10 pages, each with a data table
        XCTAssertGreaterThanOrEqual(tables.count, 5, "Should detect tables across multiple pages")

        for table in tables {
            XCTAssertGreaterThanOrEqual(table.rowCount, 2, "Each table should have at least 2 rows (page \(table.pageIndex))")
            XCTAssertGreaterThanOrEqual(table.columnCount, 2, "Each table should have at least 2 columns (page \(table.pageIndex))")
            XCTAssertFalse(table.cells.isEmpty, "Table cells should not be empty (page \(table.pageIndex))")
        }
    }

    func testFDATablesCSVExport() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "fda_tables", withExtension: "pdf") else {
            throw XCTSkip("fda_tables.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path,
            pages: [0]
        )

        guard let table = tables.first else {
            throw XCTSkip("No tables found on page 1 of fda_tables.pdf")
        }

        let csv = table.toCSV()
        XCTAssertFalse(csv.isEmpty, "CSV export should not be empty")
        // FDA tables have many columns; verify the first row has enough
        XCTAssertGreaterThanOrEqual(table.columnCount, 5, "FDA table should have at least 5 columns")
        XCTAssertGreaterThanOrEqual(table.rowCount, 5, "FDA table should have at least 5 rows")
        // Verify CSV contains data from the table
        XCTAssertTrue(csv.contains(","), "CSV should contain comma separators")
    }

    func testFDATablesExcelExport() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "fda_tables", withExtension: "pdf") else {
            throw XCTSkip("fda_tables.pdf not in bundle")
        }

        let tables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path
        )

        guard tables.count >= 2 else {
            throw XCTSkip("Need at least 2 tables for Excel export test")
        }

        let outputURL = temporaryURL(filename: "fda_tables_test.xlsx")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try ExcelExportService.export(tables: tables, to: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "Excel file should be created")
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(size, 0, "Excel file should not be empty")
    }

    func testStrategyPassthrough() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_table", withExtension: "pdf") else {
            throw XCTSkip("test_table.pdf not in bundle")
        }

        // Lines strategy should find bordered tables
        let linesTables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path,
            pages: [0],
            strategy: "lines"
        )
        XCTAssertFalse(linesTables.isEmpty, "Lines strategy should find tables in test_table.pdf")

        // Text strategy should also find tables (text is aligned in the test PDF)
        let textTables = try await TableExtractionService.detectAndExtract(
            inputPath: url.path,
            pages: [0],
            strategy: "text"
        )
        XCTAssertFalse(textTables.isEmpty, "Text strategy should find tables in test_table.pdf")
    }
}
