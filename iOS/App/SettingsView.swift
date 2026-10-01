import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = NotificationPreferences.load()
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var connecting: DirectUsageProvider?
    @State private var connectionRevision = 0
    @AppStorage(PhoneSyncSettings.macDetailsKey) private var macDetails = false
    @ObservedObject private var liveActivity = ProviderUsageActivityManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(DirectUsageProvider.allCases) { provider in
                        Button { connecting = provider } label: {
                            HStack(spacing: 12) {
                                ProviderBrandMark(provider: provider == .codex ? .codex : .claude)
                                    .fill(PhoneStyle.tint(provider == .codex ? .codex : .claude))
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(provider == .codex ? "OpenAI · Codex" : "Claude").foregroundStyle(PhoneStyle.ink)
                                    Text(connectionLabel(provider)).font(.caption).foregroundStyle(PhoneStyle.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(PhoneStyle.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                } header: { Text("Accounts") } footer: {
                    Text("Sign in here to fetch usage directly on your iPhone. Your Mac can be off.")
                }
                Section {
                    Toggle("Follow active providers", isOn: Binding(
                        get: { liveActivity.isEnabled },
                        set: { enabled in Task { await liveActivity.setEnabled(enabled, snapshot: store.snapshot) } }
                    ))
                    NavigationLink("Pet animations") { PhonePetMotionSettings() }
                    if let message = liveActivity.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Live Activity") } footer: {
                    Text("Follows usage changes from the last six minutes. Background checks depend on iOS.")
                }
                if authorization != .authorized && authorization != .provisional && authorization != .ephemeral {
                    Section {
                        Button {
                            Task {
                                if authorization == .denied {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
                                } else { _ = await NotificationManager.requestAuthorization() }
                                await refreshAuthorization()
                            }
                        } label: {
                            Label(authorization == .denied ? "Allow notifications in Settings" : "Enable notifications", systemImage: "bell.badge")
                        }
                    }
                }
                Section("Notifications") {
                    Toggle("Codex usage limit", isOn: $preferences.usageApproachingLimit)
                    Toggle("Claude usage limits", isOn: $preferences.claudeUsage)
                    if preferences.usageApproachingLimit || preferences.claudeUsage {
                        Picker("Warn at", selection: $preferences.usageThreshold) {
                            Text("80%").tag(80.0)
                            Text("90%").tag(90.0)
                            Text("95%").tag(95.0)
                            if ![80.0, 90.0, 95.0].contains(preferences.usageThreshold) {
                                Text("\(Int(preferences.usageThreshold))%").tag(preferences.usageThreshold)
                            }
                        }
                    }
                    Toggle("Codex resets", isOn: Binding(
                        get: { preferences.resetAnnounced || preferences.resetCompleted },
                        set: { preferences.resetAnnounced = $0; preferences.resetCompleted = $0 }
                    ))
                    Toggle("Tibo’s updates", isOn: $preferences.tiboPosts)
                    NavigationLink("Activity & more alerts") { additionalAlerts }
                }
                Section {
                    Toggle("Include Mac history & tasks", isOn: $macDetails)
                } header: { Text("Optional") } footer: {
                    Text("Adds local token totals and task details through iCloud. Phone connections stay in charge of usage.")
                }
            }
            .font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .background(PhoneStyle.paper)
            .tint(PhoneStyle.reset)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $connecting) { ProviderConnectionView(provider: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .directProviderUsageChanged)) { _ in connectionRevision += 1 }
            .onChange(of: macDetails) {
                Task {
                    if macDetails { await CloudSnapshotService.installSubscriptionIfNeeded() }
                    await store.refresh()
                }
            }
            .task { await refreshAuthorization() }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await refreshAuthorization() } } }
            .onChange(of: preferences) {
                preferences.save()
            }
        }
    }

    private var additionalAlerts: some View {
        Form {
            Section("Claude") { Toggle("New weekly allowance", isOn: $preferences.claudeWeek) }
            Section("Codex resets") {
                Toggle("Reset announced", isOn: $preferences.resetAnnounced)
                Toggle("Reset confirmed", isOn: $preferences.resetCompleted)
                Toggle("Time Sensitive alerts", isOn: $preferences.prominentResetAlert)
                Toggle("Reset credit expiring", isOn: $preferences.resetCreditExpiring)
            }
            Section("Codex activity") {
                Toggle("Running out early", isOn: $preferences.paceRisk)
                if macDetails {
                    Toggle("Subscription renewal", isOn: $preferences.renewalSoon)
                    Toggle("Task changes", isOn: $preferences.codexTasks)
                }
                Toggle("Usage out of date", isOn: $preferences.staleSync)
            }
            Section { Button("iPhone notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
        }
        .font(.system(size: 15))
            .scrollContentBackground(.hidden)
        .background(PhoneStyle.paper)
        .navigationTitle("More alerts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func connectionLabel(_ provider: DirectUsageProvider) -> String {
        _ = connectionRevision
        let service = ProviderConnectionService.shared
        if service.needsSignIn(provider) { return "Sign in again" }
        return service.hasConnection(provider) ? "Connected on this iPhone" : "Connect account"
    }
}
