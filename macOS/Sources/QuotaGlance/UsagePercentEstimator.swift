import Foundation

/// Fills the gaps between Codex's coarse percentage updates using the same
/// quota-weighted cost ledger that backs the token intelligence view.
///
/// The service percentage remains the authority and is kept in history
/// unchanged. This estimator only advances the live display from a recent
/// official anchor after it has learned the account's observed cost-per-point.
enum UsagePercentEstimator {
    static func estimate(
        officialPercent: Double,
        quotaWeightedUSD: Double?,
        windowStart: Date,
        history: [UsageCheckpoint]
    ) -> Double {
        guard let currentCost = quotaWeightedUSD, currentCost.isFinite else {
            return officialPercent
        }

        let points = history
            .filter {
                abs($0.windowStart.timeIntervalSince(windowStart))
                    < UsageHistoryStore.windowTolerance
            }
            .sorted { $0.recordedAt < $1.recordedAt }

        // Keep the first observation of each new official high-water mark.
        // Repeated 29% samples are not additional calibration evidence.
        var anchors: [(percent: Double, cost: Double)] = []
        var highestPercent = -Double.infinity
        for point in points {
            guard let cost = point.quotaWeightedUSD,
                  cost.isFinite,
                  point.usedPercent > highestPercent + 0.001 else { continue }
            anchors.append((point.usedPercent, cost))
            highestPercent = point.usedPercent
        }

        guard anchors.count >= 2 else { return officialPercent }

        var costPerPoint: [Double] = []
        for pair in zip(anchors, anchors.dropFirst()) {
            let percentDelta = pair.1.percent - pair.0.percent
            let costDelta = pair.1.cost - pair.0.cost
            guard percentDelta > 0,
                  percentDelta <= 10,
                  costDelta > 0 else { continue }
            let value = costDelta / percentDelta
            if value.isFinite { costPerPoint.append(value) }
        }
        guard !costPerPoint.isEmpty else { return officialPercent }

        // A median prevents one delayed or unusually expensive sample from
        // changing the calibration for the entire week.
        let recent = Array(costPerPoint.suffix(8)).sorted()
        let middle = recent.count / 2
        let calibratedCostPerPoint = recent.count.isMultiple(of: 2)
            ? (recent[middle - 1] + recent[middle]) / 2
            : recent[middle]
        guard calibratedCostPerPoint > 0 else { return officialPercent }

        let authoritativeFloor = max(officialPercent, anchors.last?.percent ?? officialPercent)
        guard let base = anchors.last(where: { $0.percent <= authoritativeFloor + 0.001 }) else {
            return authoritativeFloor
        }
        let inferredAdvance = max(0, currentCost - base.cost) / calibratedCostPerPoint

        // The estimate is intentionally bounded. If the endpoint and ledger
        // ever disagree substantially, the next official sample wins instead
        // of allowing inference to run away.
        return min(100, min(authoritativeFloor + 10, authoritativeFloor + inferredAdvance))
    }
}
