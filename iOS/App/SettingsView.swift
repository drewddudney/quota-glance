import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var store: DashboardStore
    @Binding var selectedTheme: MobileTheme
    @State private var preferences = NotificationPreferences.load()
    @State private var notificationStatus = "Checking…"

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(MobileTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }

                Section("Reset calculator") {
                    ForEach(ResetSource.calculatorCases) { source in
                        Toggle(source.name, isOn: store.binding(for: source))
                    }
                    Text("The reset dial averages the checked calculators that currently publish a percentage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Reset announced", isOn: $preferences.resetAnnounced)
                    Toggle("Reset completed", isOn: $preferences.resetCompleted)
                    if preferences.resetAnnounced || preferences.resetCompleted {
                        Toggle("Emergency-style reset alert", isOn: $preferences.prominentResetAlert)
                        Text(preferences.prominentResetAlert
                             ? "Time Sensitive, with the reset sound, a high-visibility in-app banner, and a Live Activity countdown. It may break through Focus, but uses no government emergency-alert channel."
                             : "Delivered as a normal notification with a Live Activity countdown.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Approaching usage limit", isOn: $preferences.usageApproachingLimit)
                    if preferences.usageApproachingLimit {
                        Picker("Warn me at", selection: $preferences.usageThreshold) {
                            Text("80%").tag(80.0)
                            Text("90%").tag(90.0)
                            Text("95%").tag(95.0)
                        }
                    }

                    Toggle("Renewal in 3 days", isOn: $preferences.renewalSoon)
                    Toggle("Reset credit expiring", isOn: $preferences.resetCreditExpiring)
                    Toggle("Likely to run out early", isOn: $preferences.paceRisk)
                    Toggle("New Tibo posts", isOn: $preferences.tiboPosts)
                    Toggle("Codex task changes", isOn: $preferences.codexTasks)
                    Toggle("Live Codex session", isOn: $preferences.sessionLiveActivity)
                    Toggle("Mac sync is stale", isOn: $preferences.staleSync)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Live Codex session shows usage and token burn on your Lock Screen while the Mac detects active work. Delivery timing is managed by iOS.")
                }

                Section("Permission") {
                    HStack {
                        Text("Notifications")
                        Spacer()
                        Text(notificationStatus).foregroundStyle(.secondary)
                    }
                    Button("Enable notifications") {
                        Task {
                            _ = await NotificationManager.requestAuthorization()
                            await refreshAuthorizationStatus()
                        }
                    }
                }

                Section("Sync") {
                    LabeledContent("Codex usage", value: "Private iCloud")
                    LabeledContent("Reset sources", value: "Direct")
                    Text("Usage and billing dates come from your Mac. Public reset estimates refresh directly on the phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Quota Glance")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refreshAuthorizationStatus() }
            .onChange(of: preferences.resetAnnounced) { preferences.save() }
            .onChange(of: preferences.resetCompleted) { preferences.save() }
            .onChange(of: preferences.prominentResetAlert) { preferences.save() }
            .onChange(of: preferences.usageApproachingLimit) { preferences.save() }
            .onChange(of: preferences.usageThreshold) { preferences.save() }
            .onChange(of: preferences.renewalSoon) { preferences.save() }
            .onChange(of: preferences.resetCreditExpiring) { preferences.save() }
            .onChange(of: preferences.paceRisk) { preferences.save() }
            .onChange(of: preferences.tiboPosts) { preferences.save() }
            .onChange(of: preferences.codexTasks) { preferences.save() }
            .onChange(of: preferences.sessionLiveActivity) { preferences.save() }
            .onChange(of: preferences.staleSync) { preferences.save() }
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Enabled"
        case .denied: "Disabled"
        case .notDetermined: "Not enabled"
        @unknown default: "Unknown"
        }
    }
}
