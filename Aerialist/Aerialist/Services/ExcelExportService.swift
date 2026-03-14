import Foundation
import XLKit

/// Exports extracted tables to Excel (.xlsx) files using XLKit.
@MainActor
enum ExcelExportService {

    enum ExcelExportError: LocalizedError {
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .exportFailed(let reason):
                return "Excel export failed: \(reason)"
            }
        }
    }

    /// Export multiple tables to an Excel file, one sheet per table.
    /// - Parameters:
    ///   - tables: The extracted tables to export.
    ///   - url: The destination file URL.
    static func export(
        tables: [TableExtractionService.ExtractedTable],
        to url: URL
    ) throws {
        let workbook = Workbook()

        for (i, table) in tables.enumerated() {
            let sheetName = "Table \(i + 1) (Page \(table.pageIndex + 1))"
            let sheet = workbook.addSheet(name: sheetName)
            writeTable(table, to: sheet)
        }

        do {
            try workbook.save(to: url)
        } catch {
            throw ExcelExportError.exportFailed(error.localizedDescription)
        }
    }

    /// Export a single table to an Excel file.
    /// - Parameters:
    ///   - table: The extracted table data.
    ///   - url: The destination file URL.
    ///   - sheetName: The name for the worksheet.
    static func export(
        table: TableExtractionService.ExtractedTable,
        to url: URL,
        sheetName: String = "Table"
    ) throws {
        try export(tables: [table], to: url)
    }

    // MARK: - Helpers

    private static func writeTable(
        _ table: TableExtractionService.ExtractedTable,
        to sheet: Sheet
    ) {
        for (rowIndex, row) in table.cells.enumerated() {
            for (colIndex, cellValue) in row.enumerated() {
                let cellRef = "\(columnLetter(for: colIndex))\(rowIndex + 1)"
                if rowIndex == 0 {
                    sheet.setCell(cellRef, string: cellValue, format: CellFormat.header())
                } else {
                    sheet.setCell(cellRef, value: .string(cellValue))
                }
            }
        }
    }

    /// Convert a 0-based column index to an Excel column letter (A, B, ..., Z, AA, AB, ...).
    static func columnLetter(for index: Int) -> String {
        var result = ""
        var n = index
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }
}
