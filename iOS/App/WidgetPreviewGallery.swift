#if DEBUG
import SwiftUI
import WidgetKit

/// A native QA surface for the production widget content, including its actual
/// small and accessory constraints. It is available only through debug launch arguments.
struct WidgetPreviewGallery: View {
    let snapshot: QuotaSnapshot
    private var selection: MobileProviderSelection {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--quota-preview-claude") { return .claude }
        if args.contains("--quota-preview-codex") { return .codex }
        return .both
    }
    private var activityPreview: Bool { ProcessInfo.processInfo.arguments.contains("--quota-preview-live-activity") }
    private var lockScreen: Bool { ProcessInfo.processInfo.arguments.contains("--quota-preview-lock-widgets") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activityPreview ? "Live Activity" : lockScreen ? "Lock Screen companions" : "Home Screen companions").font(.title2.weight(.semibold))
                    Text("\(selection.title) · Production widget views").font(.caption).foregroundStyle(.secondary)
                }
                if activityPreview {
                    ProviderUsageActivityContent(readings: ProviderUsageActivityAttributes.state(snapshot: snapshot, providers: selection.providers).readings, startedAt: .now)
                        .frame(width: 350).background(QuotaStyle.background, in: RoundedRectangle(cornerRadius: 26))
                    Text("Activity · provider changes animate in place").font(.caption).foregroundStyle(.secondary)
                } else if lockScreen {
                    Text("Friday, September 25").font(.title3.weight(.medium)).frame(maxWidth: .infinity).padding(.top, 22)
                    Text("9:41").font(.system(size: 82, weight: .thin, design: .rounded)).frame(maxWidth: .infinity).padding(.top, -24)
                    HStack(spacing: 20) {
                        widget(.accessoryCircular, width: 72, height: 72)
                        widget(.accessoryRectangular, width: 170, height: 72)
                    }.frame(maxWidth: .infinity)
                    widget(.accessoryInline, width: 320, height: 26).frame(maxWidth: .infinity)
                    Text("Circular · Rectangular · Inline").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 16)
                } else {
                    widget(.systemMedium, width: 364, height: 170)
                    Text("Medium").font(.caption).foregroundStyle(.secondary).padding(.top, -18)
                    widget(.systemSmall, width: 170, height: 170)
                    Text("Small").font(.caption).foregroundStyle(.secondary).padding(.top, -18)
                }
            }.padding(24)
        }
        .background((lockScreen ? Color(red: 0.15, green: 0.20, blue: 0.25) : PhoneStyle.field).ignoresSafeArea())
        .preferredColorScheme(lockScreen ? .dark : nil)
    }
    private func widget(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        CompanionWidgetContent(snapshot: snapshot, date: .now, family: family, selection: selection)
            .frame(width: width, height: height)
            .background(lockScreen ? Color.clear : CompanionStyle.paper, in: RoundedRectangle(cornerRadius: 24))
    }
}
#endif
