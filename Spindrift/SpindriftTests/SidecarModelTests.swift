import XCTest
@testable import Spindrift

final class SidecarModelTests: XCTestCase {

    func testEmptySidecarRoundTrip() throws {
        let model = SidecarModel()
        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertTrue(decoded.stamps.isEmpty)
        XCTAssertTrue(decoded.textBoxes.isEmpty)
        XCTAssertTrue(decoded.comments.isEmpty)
        XCTAssertTrue(decoded.markups.isEmpty)
        XCTAssertTrue(decoded.ocrResults.isEmpty)
        XCTAssertTrue(decoded.formFieldOverrides.isEmpty)
    }

    func testSidecarWithStampsRoundTrip() throws {
        var model = SidecarModel()
        model.stamps = [
            StampAnnotationModel(
                pageIndex: 0,
                bounds: AnnotationBounds(x: 10, y: 20, width: 100, height: 100),
                imageData: "dGVzdA==", // "test" in base64
                opacity: 0.8
            )
        ]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.stamps.count, 1)
        XCTAssertEqual(decoded.stamps[0].pageIndex, 0)
        XCTAssertEqual(decoded.stamps[0].bounds.x, 10)
        XCTAssertEqual(decoded.stamps[0].opacity, 0.8)
        XCTAssertEqual(decoded.stamps[0].imageData, "dGVzdA==")
    }

    func testSidecarWithTextBoxRoundTrip() throws {
        var model = SidecarModel()
        model.textBoxes = [
            TextBoxAnnotationModel(
                pageIndex: 2,
                bounds: AnnotationBounds(x: 50, y: 100, width: 200, height: 40),
                text: "Hello World",
                fontName: "Courier",
                fontSize: 16,
                color: "#FF0000"
            )
        ]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.textBoxes.count, 1)
        XCTAssertEqual(decoded.textBoxes[0].text, "Hello World")
        XCTAssertEqual(decoded.textBoxes[0].fontName, "Courier")
        XCTAssertEqual(decoded.textBoxes[0].fontSize, 16)
        XCTAssertEqual(decoded.textBoxes[0].color, "#FF0000")
    }

    func testSidecarWithCommentRoundTrip() throws {
        var model = SidecarModel()
        let date = Date(timeIntervalSince1970: 1_000_000)
        model.comments = [
            CommentAnnotationModel(
                pageIndex: 1,
                bounds: AnnotationBounds(x: 0, y: 0, width: 24, height: 24),
                text: "Fix this",
                author: "Test User",
                date: date
            )
        ]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.comments.count, 1)
        XCTAssertEqual(decoded.comments[0].text, "Fix this")
        XCTAssertEqual(decoded.comments[0].author, "Test User")
    }

    func testSidecarWithMarkupRoundTrip() throws {
        var model = SidecarModel()
        model.markups = [
            MarkupAnnotationModel(
                pageIndex: 3,
                type: .highlight,
                quadrilateralPoints: [[
                    QuadPoint(x: 10, y: 10),
                    QuadPoint(x: 100, y: 10),
                    QuadPoint(x: 100, y: 20),
                    QuadPoint(x: 10, y: 20)
                ]],
                color: "#FFFF00"
            )
        ]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.markups.count, 1)
        XCTAssertEqual(decoded.markups[0].type, .highlight)
        XCTAssertEqual(decoded.markups[0].color, "#FFFF00")
        XCTAssertEqual(decoded.markups[0].quadrilateralPoints[0].count, 4)
    }

    func testSidecarWithOCRResultsRoundTrip() throws {
        var model = SidecarModel()
        model.ocrResults = [
            "0": OCRPageResult(lines: [
                OCRLineResult(
                    text: "Hello",
                    boundingBox: AnnotationBounds(x: 10, y: 700, width: 100, height: 20),
                    confidence: 0.98
                )
            ])
        ]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.ocrResults["0"]?.lines.count, 1)
        XCTAssertEqual(decoded.ocrResults["0"]?.lines[0].text, "Hello")
        XCTAssertEqual(decoded.ocrResults["0"]?.lines[0].confidence, 0.98)
    }

    func testSidecarWithFormFieldOverridesRoundTrip() throws {
        var model = SidecarModel()
        model.formFieldOverrides = [
            "name": "John Doe",
            "email": "john@example.com"
        ]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.formFieldOverrides["name"], "John Doe")
        XCTAssertEqual(decoded.formFieldOverrides["email"], "john@example.com")
    }

    func testAnnotationBoundsToCGRect() {
        let bounds = AnnotationBounds(x: 10, y: 20, width: 100, height: 200)
        let rect = bounds.cgRect
        XCTAssertEqual(rect.origin.x, 10)
        XCTAssertEqual(rect.origin.y, 20)
        XCTAssertEqual(rect.size.width, 100)
        XCTAssertEqual(rect.size.height, 200)
    }

    func testAnnotationBoundsFromCGRect() {
        let rect = CGRect(x: 15, y: 25, width: 150, height: 250)
        let bounds = AnnotationBounds(rect)
        XCTAssertEqual(bounds.x, 15)
        XCTAssertEqual(bounds.y, 25)
        XCTAssertEqual(bounds.width, 150)
        XCTAssertEqual(bounds.height, 250)
    }

    func testFullSidecarRoundTrip() throws {
        var model = SidecarModel()
        model.sourceFileHash = "abc123"
        model.stamps = [
            StampAnnotationModel(pageIndex: 0, bounds: AnnotationBounds(x: 0, y: 0, width: 50, height: 50), imageData: "dGVzdA==")
        ]
        model.textBoxes = [
            TextBoxAnnotationModel(pageIndex: 1, bounds: AnnotationBounds(x: 10, y: 10, width: 200, height: 40))
        ]
        model.comments = [
            CommentAnnotationModel(pageIndex: 0, bounds: AnnotationBounds(x: 0, y: 0, width: 24, height: 24), text: "Note")
        ]
        model.formFieldOverrides = ["field1": "value1"]

        let data = try SidecarIO.encode(model)
        let decoded = try SidecarIO.decode(from: data)

        XCTAssertEqual(decoded.version, model.version)
        XCTAssertEqual(decoded.sourceFileHash, model.sourceFileHash)
        XCTAssertEqual(decoded.stamps.count, 1)
        XCTAssertEqual(decoded.textBoxes.count, 1)
        XCTAssertEqual(decoded.comments.count, 1)
        XCTAssertEqual(decoded.formFieldOverrides.count, 1)
    }
}
