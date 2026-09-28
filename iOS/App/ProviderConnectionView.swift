import SwiftUI
import WebKit

@MainActor
struct ProviderConnectionView: View {
    @ObservedObject private var session: ProviderWebSession
    @Environment(\.dismiss) private var dismiss

    init(provider: DirectUsageProvider) {
        session = ProviderConnectionService.shared.session(for: provider)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.caption)
                    Text(session.displayedHost).font(.footnote.weight(.medium))
                    Spacer()
                    if session.checking { ProgressView().controlSize(.small) }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                ProviderConnectionWebView(webView: session.webView)
                    .id(ObjectIdentifier(session.webView))
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    if session.workspaces.count > 1 {
                        Picker("Workspace", selection: Binding(
                            get: { session.workspaceID }, set: session.selectWorkspace
                        )) {
                            Text("Choose a workspace").tag("")
                            ForEach(session.workspaces) { Text($0.name).tag($0.id) }
                        }
                        .disabled(session.checking)
                    }
                    Text(session.connectionMessage)
                        .font(.footnote)
                        .foregroundStyle(session.connected ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("providerConnectionStatus")
                    if let diagnostic = session.diagnosticText {
                        Text(diagnostic).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("providerConnectionDiagnostic")
                    }
                    HStack(alignment: .center, spacing: 16) {
                        Text("Your sign-in is saved on this iPhone.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Check connection", action: session.checkConnection)
                            .font(.subheadline.weight(.semibold))
                            .disabled(session.checking)
                            .accessibilityIdentifier("checkProviderConnection")
                    }
                }
                .padding(16)
            }
            .background(PhoneStyle.paper)
            .tint(PhoneStyle.reset)
            .navigationTitle("Connect \(session.provider.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if ProviderConnectionService.shared.hasConnection(session.provider) {
                        Button("Disconnect", role: .destructive) {
                            Task {
                                await ProviderConnectionService.shared.disconnect(session.provider)
                                dismiss()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { session.present() }
            .onDisappear { session.dismiss() }
            .sheet(item: $session.popup, onDismiss: session.closePopup) { popup in
                ProviderConnectionPopupView(popup: popup, session: session)
            }
        }
    }
}

private struct ProviderConnectionWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct ProviderConnectionPopupView: View {
    let popup: ProviderAuthPopup
    @ObservedObject var session: ProviderWebSession

    var body: some View {
        NavigationStack {
            ProviderConnectionWebView(webView: popup.webView)
                .navigationTitle("Sign in to \(session.provider.title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: session.closePopup)
                    }
                }
        }
        .presentationDetents([.large])
    }
}
