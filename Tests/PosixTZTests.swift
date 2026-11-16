import XCTest
@testable import WorldClockSync

final class PosixTZTests: XCTestCase {
    private let ref = ISO8601DateFormatter().date(from: "2026-11-15T12:00:00Z")!

    // Les abréviations (CET, EST…) dépendent de la langue du système : on vérifie surtout décalages et règles.
    private func posix(_ id: String) -> String {
        PosixTZ.string(for: TimeZone(identifier: id)!, referenceDate: ref)
    }

    func testCentralEurope() {
        // La chaîne qui a remis l'horloge à l'heure.
        XCTAssertEqual(posix("Europe/Zurich"), "CET-1CEST,M3.5.0,M10.5.0/3")
        XCTAssertEqual(posix("Europe/Paris"), "CET-1CEST,M3.5.0,M10.5.0/3")
    }

    func testLondon() { XCTAssertTrue(posix("Europe/London").hasSuffix("0<+01>,M3.5.0/1,M10.5.0") || posix("Europe/London").hasSuffix("0BST,M3.5.0/1,M10.5.0"), posix("Europe/London")) }
    func testNewYork() { XCTAssertTrue(posix("America/New_York").hasSuffix(",M3.2.0,M11.1.0"), posix("America/New_York")) }
    func testNoDST() { XCTAssertTrue(posix("Asia/Tokyo").hasSuffix("-9") && !posix("Asia/Tokyo").contains(","), posix("Asia/Tokyo")) }
    func testHalfHour() { XCTAssertTrue(posix("Asia/Kolkata").hasSuffix("-5:30"), posix("Asia/Kolkata")) }
    func testUTC() { XCTAssertEqual(posix("UTC"), "GMT0") }
}
