import XCTest
@testable import QuotaGlance

@MainActor
final class MenuBarSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFiveHourWindowIsAbsentWhenAccountOnlyReportsWeeklyQuota() {
        let model = MenuBarSummaryModel.shared
        model.update(payload(
            primary: window(id: "weekly", duration: 10_080, used: 42),
            secondary: nil
        ))

        XCTAssertNil(model.shortWindow)
        XCTAssertEqual(model.weeklyWindow?.usedPercent, 42)
        XCTAssertEqual(model.statusText(mode: .dual, at: now), "W 42%")
    }

    func testFiveHourWindowAppearsOnlyWhenReported() {
        let model = MenuBarSummaryModel.shared
        model.update(payload(
            primary: window(id: "short", duration: 300, used: 18),
            secondary: window(id: "weekly", duration: 10_080, used: 64)
        ))

        XCTAssertEqual(model.shortWindow?.usedPercent, 18)
        XCTAssertEqual(model.weeklyWindow?.usedPercent, 64)
        XCTAssertEqual(model.statusText(mode: .dual, at: now), "5H 18% · W 64%")
    }

    func testModelSpecificFiveHourDoesNotMasqueradeAsAccountWindow() {
        let model = MenuBarSummaryModel.shared
        model.update(payload(
            primary: window(id: "primary", duration: 10_080, used: 28),
            secondary: nil,
            inventory: [window(id: "codex_bengalfox.primary", duration: 300, used: 71)]
        ))

        XCTAssertNil(model.shortWindow)
        XCTAssertEqual(model.statusText(mode: .dual, at: now), "W 28%")
    }

    func testSmartDisplayPrioritizesAnnouncedResetCountdown() {
        let model = MenuBarSummaryModel.shared
        var value = payload(
            primary: window(id: "weekly", duration: 10_080, used: 64),
            secondary: nil
        )
        value = MenuBarSummaryPayload(
            primary: value.primary,
            secondary: value.secondary,
            inventory: value.inventory,
            planName: value.planName,
            paceHeadline: value.paceHeadline,
            paceRunout: value.paceRunout,
            forecastPercent: value.forecastPercent,
            forecastRange: value.forecastRange,
            expectedResetAt: now.addingTimeInterval(90 * 60),
            resetIsDelayed: false,
            lastBlessingAt: value.lastBlessingAt,
            unreadTweet: value.unreadTweet,
            lastSuccessfulAt: value.lastSuccessfulAt,
            lastAttemptFailed: value.lastAttemptFailed,
            statusMessage: value.statusMessage
        )
        model.update(value)

        XCTAssertEqual(model.statusText(mode: .smart, at: now), "↻ 1H 30M")
    }

    private func window(id: String, duration: Double, used: Double) -> MenuBarQuotaWindow {
        MenuBarQuotaWindow(
            id: id,
            label: "Codex",
            usedPercent: used,
            resetAt: now.addingTimeInterval(duration * 60),
            durationMinutes: duration
        )
    }

    private func payload(
        primary: MenuBarQuotaWindow?,
        secondary: MenuBarQuotaWindow?,
        inventory: [MenuBarQuotaWindow] = []
    ) -> MenuBarSummaryPayload {
        MenuBarSummaryPayload(
            primary: primary,
            secondary: secondary,
            inventory: inventory,
            planName: "Pro 20X",
            paceHeadline: "On pace",
            paceRunout: "3D 4H",
            forecastPercent: 29,
            forecastRange: "RANGE 15–52%",
            expectedResetAt: nil,
            resetIsDelayed: false,
            lastBlessingAt: nil,
            unreadTweet: false,
            lastSuccessfulAt: now,
            lastAttemptFailed: false,
            statusMessage: "Live"
        )
    }
}
