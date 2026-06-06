import SwiftUI

/// Settings for the thin-client shell (SERVER_ARCHITECTURE.md §4.e).
///
/// The brain runs on the server, so there is NO on-device Anthropic key field
/// and NO editable token budget — both were security/accounting liabilities. We
/// show the server URL, the connection/sync status, the device-pairing state,
/// and the calendar-push state. The bearer token lives in the Keychain (set via
/// pairing), never in `UserDefaults`.
struct AyumiSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AtlasRepo.self) private var repo

    @State private var serverURL = ""
    @State private var deviceToken = ""
    @State private var urlRejected = false
    @State private var paired = Keychain.hasDeviceToken
    /// Opt-in app lock (AtlasApp reads the same key): Face ID with passcode
    /// fallback covers the app on launch and on returning after the grace window.
    @AppStorage("requireBiometricLock") private var requireBiometricLock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Settings").font(Theme.Font.serifItalic(30)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button { dismiss() } label: {
                    Text("DONE").font(Theme.Font.mono(10)).tracking(1.2).foregroundStyle(Theme.Palette.tealDeep)
                }.buttonStyle(.plain)
            }
            .padding(.top, 8)

            field("Server URL") {
                TextField("https://atlas.example.com", text: $serverURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { applyServerURL() }
            }
            if urlRejected {
                Text("Server URL must use https.")
                    .font(Theme.Font.sans(12)).foregroundStyle(Color(hex: 0xB8431E))
            } else {
                Text("Ayumi's brain runs on your server. The connection is https-only.")
                    .font(Theme.Font.sans(12)).foregroundStyle(Theme.Palette.ink3)
            }

            field("Device token") {
                SecureField(paired ? "•••• paired" : "paste device token", text: $deviceToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { applyToken() }
            }
            Text("Stored in the Keychain on this device only — never in cleartext.")
                .font(Theme.Font.sans(12)).foregroundStyle(Theme.Palette.ink3)

            statusRow("CONNECTION", value: statusText, on: statusOn)
            statusRow("DEVICE", value: paired ? "PAIRED" : "NOT PAIRED", on: paired)
            statusRow("CALENDAR",
                      value: EventKitCalendarSource.isAuthorized ? "CONNECTED" : "NOT CONNECTED",
                      on: EventKitCalendarSource.isAuthorized)
            // Delta-sync chrome (§4.d): the one-way cut-over latch + the durable
            // write-through queue depth (items still waiting to flush).
            statusRow("MIGRATION", value: repo.hasBootstrapped ? "CUT OVER" : "PENDING",
                      on: repo.hasBootstrapped)
            statusRow("OUTBOX",
                      value: repo.pendingOutboxCount == 0 ? "CLEAR" : "\(repo.pendingOutboxCount) QUEUED",
                      on: repo.pendingOutboxCount == 0)

            if let synced = repo.lastSyncedAt {
                Text("Last synced \(synced.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.Font.mono(10)).foregroundStyle(Theme.Palette.ink3)
            }

            // App lock — rendered like the status rows (mono label left), with
            // the system toggle tinted to the app's forest accent.
            HStack {
                Text("FACE ID").font(Theme.Font.mono(9)).tracking(1.4).foregroundStyle(Theme.Palette.ink3)
                Spacer()
                Toggle("", isOn: $requireBiometricLock)
                    .labelsHidden()
                    .tint(Theme.Palette.forest)
            }
            .padding(.top, 4)
            Text("Ayumi closes when you step away — only you can open her again.")
                .font(Theme.Font.sans(12)).foregroundStyle(Theme.Palette.ink3)

            // The token budget is enforced + reported by the server gateway
            // (§4.b/§4.e). The old editable on-device cap was advisory and is
            // removed from shipping Settings.
            Text("Token budget is enforced on your server.")
                .font(Theme.Font.sans(12)).foregroundStyle(Theme.Palette.ink3)

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.paper.ignoresSafeArea())
        .task {
            serverURL = await AtlasAPI.shared.configuredBaseURL ?? ""
        }
    }

    // ─── Actions ──────────────────────────────────────────────────
    private func applyServerURL() {
        let value = serverURL
        Task {
            let ok = await AtlasAPI.shared.setBaseURL(value)
            urlRejected = !ok
            if ok { await repo.sync() }
        }
    }

    private func applyToken() {
        let t = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Keychain.deviceToken = t
        deviceToken = ""
        paired = Keychain.hasDeviceToken
        Task { await repo.sync() }
    }

    // ─── Status ───────────────────────────────────────────────────
    private var statusText: String {
        switch repo.syncState {
        case .idle:    return repo.lastSyncedAt == nil ? "READY" : "SYNCED"
        case .syncing: return "SYNCING"
        case .offline: return "OFFLINE"
        case .error:   return "ERROR"
        }
    }
    private var statusOn: Bool {
        switch repo.syncState { case .idle, .syncing: return true; default: return false }
    }

    private func statusRow(_ label: String, value: String, on: Bool) -> some View {
        HStack {
            Text(label).font(Theme.Font.mono(9)).tracking(1.4).foregroundStyle(Theme.Palette.ink3)
            Spacer()
            Text(value)
                .font(Theme.Font.mono(9)).tracking(1.0)
                .foregroundStyle(on ? Theme.Palette.forest : Theme.Palette.ink4)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Font.mono(9)).tracking(1.4).foregroundStyle(Theme.Palette.ink3)
            content()
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Palette.paperDeep)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.Palette.rule, lineWidth: 1))
                )
        }
    }
}
