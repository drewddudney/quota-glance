import ActivityKit
import SwiftUI
import WidgetKit

struct ProviderUsageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProviderUsageActivityAttributes.self) { context in
            ProviderUsageActivityContent(readings: context.state.readings, startedAt: context.attributes.startedAt,
                                         isStale: context.isStale)
                .activityBackgroundTint(QuotaStyle.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ProviderUsageActivityContent(readings: context.state.readings, startedAt: context.attributes.startedAt,
                                                 isStale: context.isStale)
                }
            } compactLeading: {
                if let first = context.state.readings.first { compact(first) }
            } compactTrailing: {
                if context.state.readings.count > 1, let last = context.state.readings.last { compact(last) }
                else if let first = context.state.readings.first {
                    ProviderRunoutEstimate(reading: first, isStale: context.isStale)
                }
            } minimal: {
                if let first = context.state.readings.first {
                    LiveCompanionPet(reading: first).frame(width: 22, height: 24)
                }
            }
            .keylineTint(QuotaStyle.reset)
        }
    }

    private func compact(_ reading: ProviderUsageActivityAttributes.Reading) -> some View {
        HStack(spacing: 3) {
            LiveCompanionPet(reading: reading).frame(width: 19, height: 22)
            Text(MobileProviderReading.percent(reading.usedPercent)).monospacedDigit()
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(QuotaStyle.tint(reading.displayProvider))
        }
    }
}
