import XCTest
@testable import QuotaGlance

final class ProviderSelectionTests: XCTestCase {
    func testLayoutShuffleVisitsAllLayoutsWithoutRepeatsAcrossCycleBoundaries() throws {
        var shuffle = ProviderLayoutShuffle()
        var random = SystemRandomNumberGenerator()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var current = ProviderDisplayStyle.cornerArcs
        shuffle.setEnabled(true, at: now)
        for _ in 0..<4 {
            var cycle = Set<ProviderDisplayStyle>()
            for _ in ProviderDisplayStyle.allCases {
                let next = try XCTUnwrap(shuffle.advance(after: current, at: now, using: &random))
                XCTAssertNotEqual(next, current)
                XCTAssertTrue(cycle.insert(next).inserted)
                current = next
            }
            XCTAssertEqual(cycle, Set(ProviderDisplayStyle.allCases))
        }
    }

    func testLayoutShuffleTimerChoicesAndLateWakeMakeOnlyOneChange() throws {
        var shuffle = ProviderLayoutShuffle()
        var random = SystemRandomNumberGenerator()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(shuffle.isDue(at: now))
        shuffle.setEnabled(true, at: now)
        XCTAssertTrue(shuffle.isDue(at: now))
        var current = try XCTUnwrap(shuffle.advance(after: .cornerArcs, at: now, using: &random))
        for interval in ProviderLayoutShuffleInterval.allCases {
            shuffle.setInterval(interval, at: now)
            let deadline = now.addingTimeInterval(Double(interval.rawValue))
            XCTAssertEqual(shuffle.nextChangeAt, deadline)
            XCTAssertFalse(shuffle.isDue(at: deadline.addingTimeInterval(-0.01)))
            XCTAssertTrue(shuffle.isDue(at: deadline))
        }
        let afterSleep = now.addingTimeInterval(4 * 86_400)
        current = try XCTUnwrap(shuffle.advance(after: current, at: afterSleep, using: &random))
        XCTAssertEqual(shuffle.nextChangeAt, afterSleep.addingTimeInterval(86_400))
        XCTAssertFalse(shuffle.isDue(at: afterSleep))
        shuffle.setEnabled(false, at: afterSleep)
        XCTAssertNil(shuffle.nextChangeAt)
        XCTAssertFalse(shuffle.isDue(at: afterSleep.addingTimeInterval(86_400)))
        XCTAssertNil(shuffle.advance(after: current, at: afterSleep, using: &random))
    }

    func testLayoutShuffleRestoresDailyDeadlineAndRemainingChoices() throws {
        let suite = "QuotaGlanceTests.LayoutShuffle." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var shuffle = ProviderLayoutShuffle.load(from: defaults)
        XCTAssertFalse(shuffle.isEnabled)
        XCTAssertEqual(shuffle.interval, .hour)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var random = SystemRandomNumberGenerator()
        shuffle.setInterval(.day, at: now)
        shuffle.setEnabled(true, at: now)
        let first = try XCTUnwrap(shuffle.advance(after: .twinDials, at: now, using: &random))
        shuffle.save(to: defaults)
        var restored = ProviderLayoutShuffle.load(from: defaults)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(restored.interval, .day)
        XCTAssertEqual(restored.nextChangeAt, now.addingTimeInterval(86_400))
        XCTAssertFalse(restored.isDue(at: now.addingTimeInterval(3_600)))
        var visited = Set([first])
        var current = first
        for _ in 1..<ProviderDisplayStyle.allCases.count {
            let next = try XCTUnwrap(restored.advance(after: current, at: now, using: &random))
            XCTAssertTrue(visited.insert(next).inserted, "Relaunching must preserve the remaining shuffle choices")
            current = next
        }
        XCTAssertEqual(visited, Set(ProviderDisplayStyle.allCases))
    }

    func testExistingInstallsKeepBothAndSavedProviderChoicesRestore() {
        XCTAssertEqual(ProviderSelection.resolved(nil), .both)
        XCTAssertEqual(ProviderSelection.resolved("old-unknown-choice"), .both)
        for selection in ProviderSelection.allCases {
            XCTAssertEqual(ProviderSelection.resolved(selection.rawValue), selection)
        }
    }

    func testSelectionNeverSubstitutesTheOtherProvidersDataWhenUsageIsUnavailable() {
        let readings = [
            ProviderReading(provider: .codex, usage: 0, calendar: 11, deadline: nil, status: "Live", live: true, resetChance: 62),
            ProviderReading(provider: .claude, usage: nil, calendar: nil, deadline: nil, status: "Disconnected", live: false)
        ]
        let soloClaude = ProviderSelection.claude.filter(readings)
        XCTAssertEqual(soloClaude.map(\.provider), [.claude])
        XCTAssertNil(soloClaude.first?.usage)
        XCTAssertNil(soloClaude.first?.resetChance)
        let soloCodex = ProviderSelection.codex.filter(readings)
        XCTAssertEqual(soloCodex.first?.usage, 0)
        XCTAssertEqual(soloCodex.first?.thirdValue, 62)
        XCTAssertEqual(ProviderSelection.both.filter(readings).map(\.provider), [.codex, .claude])
        XCTAssertTrue(ProviderSelection.claude.filter([readings[0]]).isEmpty)
    }

    func testAnnouncedResetCountdownTurnsDelayedAtItsPinnedTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var codex = ProviderReading(provider: .codex, usage: 93, calendar: 85,
                                    deadline: nil, status: "Live", live: true, resetChance: 100)
        XCTAssertNil(codex.announcedResetCountdown(at: now))
        codex.announcedResetAt = now.addingTimeInterval(3_601)
        XCTAssertEqual(codex.announcedResetCountdown(at: now), "1h 01m")
        XCTAssertEqual(codex.announcedResetCountdown(at: now.addingTimeInterval(60)), "1h 00m")
        XCTAssertEqual(codex.announcedResetCountdown(at: codex.announcedResetAt!), "Delayed")
        XCTAssertEqual(codex.resetChance, 100)
    }

    func testSingleProviderNotchIsCenteredAndUsesHalfTheWidthAtTheSameHeight() {
        let screen = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        let both = ProviderDisplayGeometry.edgeFrames(screen: screen, safeTop: 0, leftArea: nil, rightArea: nil)
        for selection in [ProviderSelection.codex, .claude] {
            let frames = ProviderDisplayGeometry.edgeFrames(screen: screen, safeTop: 0, leftArea: nil, rightArea: nil, selection: selection)
            XCTAssertEqual(frames.count, 1)
            XCTAssertEqual(frames[0].midX, screen.midX)
            XCTAssertEqual(frames[0].maxY, screen.maxY)
            XCTAssertEqual(frames[0].width * 2, both[0].width)
            XCTAssertEqual(frames[0].height, 40)
        }
    }

    func testSingleProviderLayoutsFitOffsetDisplaysWithoutAnEmptySecondCell() {
        let screen = CGRect(x: 1600, y: -800, width: 1440, height: 860)
        for style in [ProviderDisplayStyle.twinDials, .stackedSlate, .metricMatrix, .cornerBlade] {
            let solo = ProviderDisplayGeometry.size(style: style, providerCount: 1)
            let both = ProviderDisplayGeometry.size(style: style)
            XCTAssertLessThan(solo.width * solo.height, both.width * both.height)
            let frame = CGRect(origin: ProviderDisplayGeometry.initialOrigin(style: style, in: screen, providerCount: 1), size: solo)
            XCTAssertTrue(screen.contains(frame))
        }
    }

    func testCornerWidgetsKeepTheRequested100PointWidthAtThePhysicalCorners() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        // The requested footprint is fixed even when a wider Dock leaves less
        // space beside its shelf. Dock size must not shrink or lift the corners.
        for style in [ProviderDisplayStyle.cornerDials, .cornerPerches, .cornerArcs] {
            let solo = ProviderDisplayGeometry.size(style: style, providerCount: 1)
            let combined = ProviderDisplayGeometry.size(style: style)
            XCTAssertEqual(solo.width, 100)
            XCTAssertEqual(combined.width, solo.width * 2 + 40)
            let frames = ProviderDisplayGeometry.cornerFrames(style: style, screen: screen, selection: .both)
            XCTAssertEqual(frames.count, 2)
            XCTAssertEqual(frames[0].minX, screen.minX)
            XCTAssertEqual(frames[1].maxX, screen.maxX)
            for frame in frames {
                XCTAssertEqual(frame.width, 100)
                XCTAssertEqual(frame.size, solo)
                XCTAssertEqual(frame.minY, screen.minY, "Corners must not float above the Dock")
                XCTAssertTrue(screen.contains(frame))
            }
        }
    }

    func testCornerAnchorsFollowPhysicalEdgesOnOffsetDisplaysAndSoloModes() {
        for screen in [CGRect(x: -1920, y: -480, width: 1920, height: 1080),
                       CGRect(x: 2560, y: 1440, width: 1440, height: 900)] {
            for selection in ProviderSelection.allCases {
                let frames = ProviderDisplayGeometry.cornerFrames(style: .cornerArcs, screen: screen, selection: selection)
                XCTAssertEqual(frames.count, selection.providers.count)
                for (provider, frame) in zip(selection.providers, frames) {
                    XCTAssertTrue(screen.contains(frame))
                    XCTAssertEqual(frame.minY, screen.minY)
                    if provider == .codex { XCTAssertEqual(frame.minX, screen.minX) }
                    else { XCTAssertEqual(frame.maxX, screen.maxX) }
                }
            }
        }
    }

    func testCornerContextMenusFitAboveTheDockOnEitherScreenEdge() {
        let size = CGSize(width: 132, height: 84)
        for visible in [CGRect(x: 0, y: 94, width: 2560, height: 1322),
                        CGRect(x: -1920, y: -386, width: 1920, height: 962)] {
            for point in [CGPoint(x: visible.minX + 50, y: visible.minY - 44),
                          CGPoint(x: visible.maxX - 50, y: visible.minY - 44)] {
                let origin = ProviderDisplayGeometry.menuOrigin(size: size, at: point, in: visible)
                let frame = CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
                XCTAssertTrue(visible.contains(frame), "A physical corner click must open a complete menu above the Dock")
                XCTAssertGreaterThanOrEqual(frame.minY - visible.minY, 6)
            }
        }
    }

    func testSingleProviderRidesUseOneRowAndStillCompleteTheirVisit() {
        let screen = CGRect(x: -1440, y: 400, width: 1440, height: 860)
        for kind in [ProviderTravelKind.plane, .balloon, .skateboard] {
            var solo = ProviderTravelPhysics(kind: kind, bounds: screen, providerCount: 1)
            let both = ProviderTravelPhysics(kind: kind, bounds: screen)
            XCTAssertLessThan(solo.bannerRect.height, both.bannerRect.height)
            for _ in 0..<2100 {
                solo.step(1.0 / 30)
                if solo.hasExited { break }
            }
            XCTAssertTrue(solo.hasExited)
            XCTAssertFalse(screen.intersects(solo.renderBounds))
        }
    }
}
