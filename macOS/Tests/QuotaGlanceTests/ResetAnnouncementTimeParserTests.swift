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

    func testRelativeWindowDoesNotCreateALiveCountdown() throws {
        let postedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T01:01:37Z"))
        XCTAssertNil(
            ResetAnnouncementTimeParser.expectedDate(
                in: "Landing in the next hour or so.",
                postedAt: postedAt
            )
        )
    }

    func testCentralWithoutMeridiemChoosesNextOccurrenceToday() throws {
        let postedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T20:00:00Z"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T21:30:00Z"))

        XCTAssertEqual(
            ResetAnnouncementTimeParser.expectedDate(
                in: "There will be one at 4:30 Central.",
                postedAt: postedAt
            ),
            expected
        )
    }
}
