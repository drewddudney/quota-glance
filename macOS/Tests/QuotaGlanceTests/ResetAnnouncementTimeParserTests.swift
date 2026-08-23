import XCTest
@testable import QuotaGlance

final class ResetAnnouncementTimeParserTests: XCTestCase {
    func testPacificTomorrowUsesAuthorsPacificCalendarAndDaylightSavingTime() throws {
        let postedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T06:29:05Z"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T21:00:00Z"))

        let parsed = ResetAnnouncementTimeParser.expectedDate(
            in: "Reset will land around 14pm PST tomorrow.",
            postedAt: postedAt
        )

        XCTAssertEqual(parsed, expected)
    }

    func testCentralRenderingCanUseTheAbsoluteInstant() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-23T21:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let components = calendar.dateComponents([.hour, .minute], from: instant)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 0)
    }

    func testRelativeResetWindowIsConvertedToAnAbsoluteInstant() throws {
        let postedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T01:01:37Z"))
        XCTAssertEqual(
            ResetAnnouncementTimeParser.expectedDate(
                in: "Landing in the next hour or so.",
                postedAt: postedAt
            ),
            postedAt.addingTimeInterval(3_600)
        )
    }
}
