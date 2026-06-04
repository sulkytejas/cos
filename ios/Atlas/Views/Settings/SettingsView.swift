import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var chapters: [Chapter]
    @Query private var allProposals: [Proposal]
    @Query private var allEvents: [AppEvent]
    @Query private var allWatchers: [Watcher]
    @State private var tone: BriefTone = .calm
    @State private var briefTime: String = "06:30"
    @State private var apiKey: String = ""
    @State private var iconStatus: IconStatus = .idle
    @State private var iconErrors: [String: String] = [:]   // title → error message
    @State private var engineStatus: EngineStatus = .init()

    enum IconStatus: Equatable {
        case idle, working(Int, Int), done(Int, Int), failed(String)
        var label: String {
            switch self {
            case .idle: return "READY"
            case .working(let i, let n): return "GENERATING \(i)/\(n)"
            case .done(let ok, let total):
                return ok == total ? "DONE · \(ok) generated" : "PARTIAL · \(ok)/\(total)"
            case .failed(let msg): return "FAILED · \(msg)".uppercased()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                engineSection
                aiSection
                connectorsSection
                briefSection
                dataSection

                Spacer().frame(height: 90)
            }
            .padding(.top, 18)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .task {
            await refreshEngineStatus()
        }
        // 30s cadence — engine status is "did the agent tick recently" data,
        // not realtime. 5s was triggering @Query re-counts and re-renders
        // every few seconds for no perceptible benefit.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task { await refreshEngineStatus() }
        }
    }

    // ─── Atlas engine ─────────────────────────────────────────────
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(title: "Ayumi engine", meta: engineStatus.statusLabel)
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 10) {
                Text("Ayumi's agent runs on the server now, behind one throttled AI gateway. There is no API key on this device — the device holds only a Keychain bearer token and reads results over https.")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)

                VStack(spacing: 0) {
                    SettingRow(label: "Pending events") {
                        Text("\(engineStatus.pendingEvents)")
                            .font(Theme.Font.mono(12))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    Hairline().opacity(0.5)
                    SettingRow(label: "Active watchers") {
                        Text("\(engineStatus.activeWatchers)")
                            .font(Theme.Font.mono(12))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    Hairline().opacity(0.5)
                    SettingRow(label: "Last tick") {
                        Text(engineStatus.lastTickLabel)
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Palette.inkFaint)
                    }
                    if let err = engineStatus.lastError, !err.isEmpty {
                        Hairline().opacity(0.5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LAST ERROR")
                                .font(Theme.Font.mono(9))
                                .tracking(1.5)
                                .foregroundStyle(Theme.Palette.ember)
                            Text(err)
                                .font(Theme.Font.mono(10.5))
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                }

                NavigationLink {
                    ReviewQueueView()
                } label: {
                    HStack(spacing: 8) {
                        Text("Review queue")
                            .font(Theme.Font.serifItalic(15))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Text("\(engineStatus.pendingProposals)")
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Palette.inkFaint)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.inkFainter)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await AtlasAgent.shared.tickOnce()
                        await refreshEngineStatus()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Run a pass now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.atlasGhost)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.horizontal, 22)
        }
    }

    private func refreshEngineStatus() async {
        let pendingEv = allEvents.filter { $0.status == .pending }.count
        let activeWa = allWatchers.filter { $0.status == .active }.count
        let pendingPr = allProposals.filter { $0.status == .pending }.count
        let last = await AtlasAgent.shared.lastTickAt
        let err = await AtlasAgent.shared.lastError
        engineStatus = EngineStatus(
            pendingEvents: pendingEv,
            activeWatchers: activeWa,
            pendingProposals: pendingPr,
            lastTickAt: last,
            lastError: err
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroText(text: "Configuration")
            Text("Settings")
                .font(Theme.Font.serif(46))
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.horizontal, 22)
    }

    // ─── AI · Nano Banana ──────────────────────────────────────────
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(title: "AI · Nano Banana", meta: iconStatus.label)
                .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 12) {
                Text("Generate editorial line-drawn icons for each chapter using Gemini 2.5 Flash Image (\"Nano Banana\"). Paste your key below — it stays on this device.")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    MicroText(text: "Key")
                    SecureField("AIza…", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.Palette.bgSunk)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiKey) { _, new in
                            UserDefaults.standard.set(new.trimmingCharacters(in: .whitespacesAndNewlines),
                                                      forKey: "GeminiAPIKey")
                        }
                }

                Button {
                    Task { await generateAll() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                        Text(generateButtonLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.atlasPrimary)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                // Force a fresh pass — useful after a prompt change.
                Button {
                    Task {
                        IconGenerator.clearAllIcons(in: context)
                        await generateAll()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Reset & regenerate all")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.atlasGhost)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                // Per-chapter status — shows which chapters got icons + any failures
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chapters) { c in
                        HStack(alignment: .top, spacing: 8) {
                            Text(c.iconData != nil ? "✓" : "·")
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(c.iconData != nil ? Theme.Palette.forest : Theme.Palette.inkFainter)
                                .frame(width: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title)
                                    .font(Theme.Font.sans(12.5))
                                    .foregroundStyle(Theme.Palette.ink)
                                if let err = iconErrors[c.title] {
                                    Text(err)
                                        .font(Theme.Font.mono(10))
                                        .foregroundStyle(Theme.Palette.teal)
                                        .lineLimit(5)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if let data = c.iconData {
                                    Text("\(data.count / 1024) KB")
                                        .font(Theme.Font.mono(10))
                                        .foregroundStyle(Theme.Palette.inkFainter)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.horizontal, 22)
        }
    }

    private var isWorking: Bool {
        if case .working = iconStatus { return true }
        return false
    }
    private var generateButtonLabel: String {
        switch iconStatus {
        case .working: return "Generating…"
        default:        return "Generate icons for all chapters"
        }
    }
    private func generateAll() async {
        iconErrors.removeAll()
        let toDo = chapters.filter { IconGenerator.needsIcon($0) }
        guard !toDo.isEmpty else {
            iconStatus = .done(0, 0)
            return
        }
        let total = toDo.count
        var success = 0
        for (i, c) in toDo.enumerated() {
            iconStatus = .working(i + 1, total)
            if let err = await IconGenerator.regenerate(c, in: context) {
                iconErrors[c.title] = err
                // If the project has zero quota OR is billing-blocked, every
                // subsequent request will fail the same way. Bail out.
                if err.lowercased().contains("billing") || err.contains("flagged") {
                    for remaining in toDo.dropFirst(i + 1) {
                        iconErrors[remaining.title] = "Skipped — billing issue must be resolved first."
                    }
                    iconStatus = .failed("billing blocked")
                    return
                }
            } else {
                success += 1
            }
            // Stay under the ~10 RPM free-tier ceiling: pace at one request
            // every 7s (≈8.5 RPM). The client also auto-retries on 429.
            if i < total - 1 {
                try? await Task.sleep(nanoseconds: 7 * 1_000_000_000)
            }
        }
        iconStatus = .done(success, total)
    }

    // ─── Connectors ────────────────────────────────────────────────
    private var connectorsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(title: "Connectors", meta: "0 of 3")
                .padding(.horizontal, 22)
            VStack(spacing: 12) {
                ConnectorRow(
                    name: "Gmail",
                    symbol: "envelope",
                    description: "Pull travel confirmations, decision threads, and meeting recaps into chapters."
                )
                ConnectorRow(
                    name: "Google Calendar",
                    symbol: "calendar",
                    description: "Surface upcoming events on Today. Auto-tag events to the right chapter."
                )
                ConnectorRow(
                    name: "Google Drive",
                    symbol: "doc.text",
                    description: "Index docs and link them to the chapter they belong to."
                )
            }
            .padding(.horizontal, 22)
        }
    }

    // ─── Brief ─────────────────────────────────────────────────────
    private var briefSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(title: "Brief", meta: "DAILY")
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                SettingRow(label: "Time") {
                    Text(briefTime)
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(Theme.Palette.ink)
                }
                Hairline().opacity(0.5)
                SettingRow(label: "Tone") {
                    ToneSegmented(value: $tone)
                }
                Hairline().opacity(0.5)
                SettingRow(label: "Home tz") {
                    Text("Asia/Kolkata")
                        .font(Theme.Font.mono(12))
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // ─── Data ──────────────────────────────────────────────────────
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(title: "Data")
                .padding(.horizontal, 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Text("Ayumi stores everything locally in ")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Text("./data/atlas.db")
                        .font(Theme.Font.mono(11.5))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(". No cloud, no auth, no telemetry.")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                Text("$ rm ./data/atlas.db && restart")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.horizontal, 22)
        }
    }
}

struct EngineStatus {
    var pendingEvents: Int = 0
    var activeWatchers: Int = 0
    var pendingProposals: Int = 0
    var lastTickAt: Date? = nil
    var lastError: String? = nil

    var statusLabel: String {
        if pendingEvents > 0 { return "\(pendingEvents) PENDING" }
        if let _ = lastError { return "ERROR" }
        if lastTickAt == nil { return "IDLE" }
        return "READY"
    }

    var lastTickLabel: String {
        guard let d = lastTickAt else { return "never" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }
}

struct SettingRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.inkSecondary)
            Spacer()
            trailing()
        }
        .padding(.vertical, 14)
    }
}

struct ConnectorRow: View {
    let name: String
    let symbol: String
    let description: String
    @State private var phase: Phase = .idle

    enum Phase { case idle, connecting, connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(phase == .connected ? Theme.Palette.forest : Theme.Palette.inkSecondary)
                Text(name)
                    .font(Theme.Font.serif(18))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(statusLabel)
                    .font(Theme.Font.mono(9))
                    .tracking(1.5)
                    .foregroundStyle(phase == .connected ? Theme.Palette.forest : Theme.Palette.inkFaint)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
            }
            Text(description)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineSpacing(3)

            Button {
                advance()
            } label: {
                HStack(spacing: 6) {
                    if phase == .connected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Connected")
                    } else if phase == .connecting {
                        Text("Authorizing")
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text("Connect")
                    }
                }
                .font(Theme.Font.sans(13.5, weight: .medium))
                .foregroundStyle(phase == .connected ? Theme.Palette.forest : Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(phase == .connected ? Theme.Palette.forestSoft : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(phase != .idle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statusLabel: String {
        switch phase {
        case .idle:       return "NOT CONNECTED"
        case .connecting: return "AUTHORIZING"
        case .connected:  return "CONNECTED"
        }
    }

    private func advance() {
        guard phase == .idle else { return }
        phase = .connecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { phase = .connected }
    }
}
