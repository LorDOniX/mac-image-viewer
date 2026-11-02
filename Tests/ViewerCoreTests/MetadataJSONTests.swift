import XCTest
@testable import ViewerCore

final class MetadataJSONTests: XCTestCase {
    private func decode(_ metadata: [String: Any]) throws -> [String: Any] {
        let json = try MetadataJSON.encode(metadata)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testNestedMetadataRetainsNumbersBooleansAndUnicode() throws {
        let result = try decode([
            "{Exif}": ["FNumber": 2.8, "ISOSpeedRatings": [100, 200], "Note": "Příliš žluťoučký \"kůň\"\nnový řádek"],
            "PixelWidth": 4032, "Enabled": true
        ])
        let exif = try XCTUnwrap(result["{Exif}"] as? [String: Any])
        XCTAssertEqual(exif["FNumber"] as? Double, 2.8)
        XCTAssertEqual(exif["ISOSpeedRatings"] as? [Int], [100, 200])
        XCTAssertEqual(exif["Note"] as? String, "Příliš žluťoučký \"kůň\"\nnový řádek")
        XCTAssertEqual(result["PixelWidth"] as? Int, 4032)
        XCTAssertEqual(result["Enabled"] as? Bool, true)
    }

    func testBinaryDatesAndNonFiniteNumbersProduceValidJSON() throws {
        let result = try decode([
            "MakerNote": Data([0, 1, 254, 255]), "Date": Date(timeIntervalSince1970: 0),
            "Infinity": Double.infinity, "Null": NSNull()
        ])
        let binary = try XCTUnwrap(result["MakerNote"] as? [String: String])
        XCTAssertEqual(binary["encoding"], "base64")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(binary["data"])), Data([0, 1, 254, 255]))
        XCTAssertEqual(result["Date"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertTrue(result["Infinity"] is String)
        XCTAssertTrue(result["Null"] is NSNull)
    }

    func testMissingEXIFStillProducesAValidObject() throws {
        XCTAssertTrue(try decode([:]).isEmpty)
        XCTAssertEqual(try decode(["PixelHeight": 123])["PixelHeight"] as? Int, 123)
        let json = try MetadataJSON.encode(["z": 1, "a": ["b": 2]])
        XCTAssertTrue(json.contains("\n"))
        XCTAssertLessThan(try XCTUnwrap(json.range(of: "\"a\"")) .lowerBound,
                          try XCTUnwrap(json.range(of: "\"z\"")) .lowerBound)
    }
}
