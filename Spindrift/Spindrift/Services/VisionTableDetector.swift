@preconcurrency import Vision
import PDFKit
import AppKit

/// Detects tables in PDF pages using Apple Vision OCR.
///
/// Renders each page to an image, runs text recognition, then clusters
/// the resulting text observations into rows and columns by spatial proximity.
/// Works on scanned documents where PyMuPDF's structural approach cannot.
enum VisionTableDetector {

    /// Detect tables on a single PDF page using Vision OCR.
    /// - Parameters:
    ///   - page: The PDF page to analyze.
    ///   - pageIndex: 0-indexed page number (stored in results).
    ///   - clip: Optional clip region in PDFKit coordinates (bottom-left origin).
    /// - Returns: Array of extracted tables found on the page.
    @MainActor
    static func detectTables(
        on page: PDFPage,
        pageIndex: Int,
        clip: CGRect? = nil
    ) async throws -> [TableExtractionService.ExtractedTable] {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let cgImage = renderPageToCGImage(page, dpi: 300) else {
            return []
        }

        let observations = try await performOCR(cgImage: cgImage, pageBounds: pageBounds)
        guard !observations.isEmpty else { return [] }

        // Filter to clip region if specified
        let filtered: [TextObs]
        if let clip = clip {
            filtered = observations.filter { clip.intersects($0.bounds) }
        } else {
            filtered = observations
        }

        guard filtered.count >= 2 else { return [] }

        let tables = clusterIntoTables(observations: filtered, pageBounds: pageBounds, pageIndex: pageIndex)
        return tables
    }

    // MARK: - Text Observation

    private struct TextObs {
        let text: String
        let bounds: CGRect   // PDFKit coordinates (bottom-left origin)
        let confidence: Float
    }

    // MARK: - Rendering

    @MainActor
    private static func renderPageToCGImage(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = Int(pageBounds.width * scale)
        let height = Int(pageBounds.height * scale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBounds.origin.x, y: -pageBounds.origin.y)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    // MARK: - Vision OCR

    private nonisolated static func performOCR(
        cgImage: CGImage,
        pageBounds: CGRect
    ) async throws -> [TextObs] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let obs = results.compactMap { observation -> TextObs? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let vb = observation.boundingBox
                    // Convert normalized Vision coords to PDFKit page coords
                    let pdfBounds = CGRect(
                        x: vb.origin.x * pageBounds.width + pageBounds.origin.x,
                        y: vb.origin.y * pageBounds.height + pageBounds.origin.y,
                        width: vb.width * pageBounds.width,
                        height: vb.height * pageBounds.height
                    )
                    return TextObs(text: candidate.string, bounds: pdfBounds, confidence: candidate.confidence)
                }

                continuation.resume(returning: obs)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Table Clustering

    private static func clusterIntoTables(
        observations: [TextObs],
        pageBounds: CGRect,
        pageIndex: Int
    ) -> [TableExtractionService.ExtractedTable] {
        // Sort by vertical position (top of page = highest Y in PDFKit coords)
        let sorted = observations.sorted { $0.bounds.midY > $1.bounds.midY }

        // Compute median line height for row clustering tolerance
        let heights = sorted.map { $0.bounds.height }.filter { $0 > 0 }
        guard !heights.isEmpty else { return [] }
        let medianHeight = heights.sorted()[heights.count / 2]
        let rowTolerance = medianHeight * 0.6

        // 1. Cluster into rows by Y midpoint
        var rows: [[TextObs]] = []
        var currentRow: [TextObs] = [sorted[0]]
        var currentMidY = sorted[0].bounds.midY

        for obs in sorted.dropFirst() {
            if abs(obs.bounds.midY - currentMidY) <= rowTolerance {
                currentRow.append(obs)
            } else {
                rows.append(currentRow.sorted { $0.bounds.minX < $1.bounds.minX })
                currentRow = [obs]
                currentMidY = obs.bounds.midY
            }
        }
        rows.append(currentRow.sorted { $0.bounds.minX < $1.bounds.minX })

        // Need at least 3 rows for a table
        guard rows.count >= 3 else { return [] }

        // 2. Find column structure
        // Collect all left-edge X positions across all rows
        let allLeftEdges = rows.flatMap { row in row.map { $0.bounds.minX } }
        guard !allLeftEdges.isEmpty else { return [] }

        // Cluster left edges into column positions
        let columnTolerance = medianHeight * 1.5
        let columnPositions = clusterValues(allLeftEdges, tolerance: columnTolerance)

        guard columnPositions.count >= 2 else { return [] }

        // 3. Find contiguous runs of rows that match the column structure
        let tables = findTableRuns(
            rows: rows,
            columnPositions: columnPositions,
            columnTolerance: columnTolerance,
            pageBounds: pageBounds,
            pageIndex: pageIndex
        )

        return tables
    }

    /// Cluster numeric values into groups within a tolerance.
    private static func clusterValues(_ values: [CGFloat], tolerance: CGFloat) -> [CGFloat] {
        let sorted = values.sorted()
        var clusters: [[CGFloat]] = []
        var current: [CGFloat] = []

        for val in sorted {
            if let last = current.last, abs(val - last) > tolerance {
                clusters.append(current)
                current = [val]
            } else {
                current.append(val)
            }
        }
        if !current.isEmpty {
            clusters.append(current)
        }

        // Return the median of each cluster
        return clusters.map { cluster in
            cluster.sorted()[cluster.count / 2]
        }
    }

    /// Assign an observation to a column index based on its left edge.
    private static func assignColumn(obs: TextObs, columns: [CGFloat], tolerance: CGFloat) -> Int? {
        for (i, colX) in columns.enumerated() {
            if abs(obs.bounds.minX - colX) <= tolerance {
                return i
            }
        }
        return nil
    }

    /// Find contiguous runs of rows that match the column structure and build tables.
    private static func findTableRuns(
        rows: [[TextObs]],
        columnPositions: [CGFloat],
        columnTolerance: CGFloat,
        pageBounds: CGRect,
        pageIndex: Int
    ) -> [TableExtractionService.ExtractedTable] {
        var tables: [TableExtractionService.ExtractedTable] = []
        let numCols = columnPositions.count

        var tableRows: [[[TextObs]]] = []  // Each element is a row of cells grouped by column
        var tableBounds: CGRect = .zero

        for row in rows {
            // Try to assign each observation in this row to a column
            var columnCells: [[TextObs]] = Array(repeating: [], count: numCols)
            var matched = 0

            for obs in row {
                if let colIdx = assignColumn(obs: obs, columns: columnPositions, tolerance: columnTolerance) {
                    columnCells[colIdx].append(obs)
                    matched += 1
                }
            }

            // A row "matches" the table structure if most observations fit columns
            let matchRatio = row.isEmpty ? 0 : Double(matched) / Double(row.count)

            if matchRatio >= 0.5 && matched >= 2 {
                // Extend the current table run
                tableRows.append(columnCells)
                let rowBounds = row.reduce(CGRect.null) { $0.union($1.bounds) }
                tableBounds = tableBounds == .zero ? rowBounds : tableBounds.union(rowBounds)
            } else {
                // End of a table run — emit if large enough
                if let table = buildTable(from: tableRows, numCols: numCols, bbox: tableBounds, pageBounds: pageBounds, pageIndex: pageIndex) {
                    tables.append(table)
                }
                tableRows = []
                tableBounds = .zero
            }
        }

        // Flush remaining
        if let table = buildTable(from: tableRows, numCols: numCols, bbox: tableBounds, pageBounds: pageBounds, pageIndex: pageIndex) {
            tables.append(table)
        }

        return tables
    }

    /// Build an ExtractedTable from clustered rows. Returns nil if too small or likely a false positive.
    private static func buildTable(
        from tableRows: [[[TextObs]]],
        numCols: Int,
        bbox: CGRect,
        pageBounds: CGRect,
        pageIndex: Int
    ) -> TableExtractionService.ExtractedTable? {
        guard tableRows.count >= 2 && numCols >= 2 else { return nil }

        // Reject: ≤2 columns spanning >90% of page height (likely body text)
        if numCols <= 2 && bbox.height > pageBounds.height * 0.9 {
            return nil
        }

        // Build cell text grid
        let cells: [[String]] = tableRows.map { columnCells in
            columnCells.map { obsInCell in
                obsInCell.map(\.text).joined(separator: " ")
            }
        }

        return TableExtractionService.ExtractedTable(
            cells: cells,
            pageIndex: pageIndex,
            bbox: bbox,
            colPositions: [],
            rowPositions: []
        )
    }
}
