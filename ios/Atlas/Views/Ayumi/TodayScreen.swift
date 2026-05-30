import SwiftUI
import SwiftData

/// Today — the conversational home. One scrolling thread between the user and
/// Ayumi (italic-serif voice, roman user bubbles), with embedded brief/action
/// capsules that morph into letters, and a fixed compose bar.
struct TodayScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    @Environment(NavRouter.self) private var router
    @Query(filter: #Predicate<Brief> { $0.statusRaw == "surfaced" },
           sort: \.surfaceAt, order: .reverse) private var briefs: [Brief]
    @State private var draft = ""
    @State private var composeOpen = false
    @State private var userTurns: [String] = []
    @State private var rings: [EORingItem] = []
    @FocusState private var composeFocused: Bool

    private let space = "today.scroll"

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DayDivider(label: "while you slept", roman: "02:14 → 06:38")

                    if briefs.isEmpty {
                    AyumiTurn(when: "06:38",
                              prose: ayumiProse([
                                .init("I sat with last night while you slept. "),
                                .init("Karan", .roman),
                                .init(" moved the intro to "),
                                .init("14:30", .accent),
                                .init(" — I pulled the thread and drafted what you'll want to open with."),
                              ], size: 17),
                              source: "6 sources · email, voice memo, calendar, deck v3") {
                        BriefCapsule(glyph: "K", title: "Karan, in 90 minutes.", when: "14:30",
                                     onOpen: { emitRing(); halo.setState(.delivered) })
                    }

                    UserTurn(text: "thanks — anything else I should know before the call?", when: "07:15")

                    ThinkingTurn(text: "reading the deck and yesterday's voice memo…")

                    AyumiTurn(when: "08:02",
                              prose: ayumiProse([
                                .init("Two things. The "),
                                .init("deck v3", .accent),
                                .init(" churn slide is stale — "),
                                .init("V.", .roman),
                                .init(" sent fresher numbers at "),
                                .init("11:30", .accent),
                                .init(". I can swap it before "),
                                .init("11:00", .accent),
                                .init("."),
                              ], size: 17),
                              source: "3 sources · drive, gmail, calendar") {
                        BriefCapsule(glyph: "S", title: "Swap the churn slide", when: "5 min",
                                     onOpen: { emitRing(); halo.setState(.delivered) })
                    }
                    } else {
                        ForEach(Array(briefs.prefix(4))) { b in
                            AyumiTurn(when: b.when ?? "today",
                                      prose: ayumiProse([.init(b.preview ?? b.relevance ?? b.situationDescription)], size: 17),
                                      source: b.drafted) {
                                BriefCapsule(glyph: String(b.title.prefix(1)).uppercased(),
                                             title: b.title, when: b.when ?? "",
                                             onOpen: { emitRing(); halo.setState(.delivered) },
                                             onOpenFull: { withAnimation(Theme.Motion.overshoot()) { router.go(.brief) } })
                            }
                        }
                    }

                    ForEach(Array(userTurns.enumerated()), id: \.offset) { _, t in
                        UserTurn(text: t, when: "now")
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }

                    DayDivider(label: "now", roman: "09:41")
                    Spacer().frame(height: 120)   // clears the compose bar
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)               // clears the app-mark
            }
            .coordinateSpace(name: space)
            .scrollDismissesKeyboard(.interactively)

            composeBar
            EOLayer(rings: rings)
        }
    }

    // ─── Compose ──────────────────────────────────────────────────
    private var composeBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.Palette.paper.opacity(0), Theme.Palette.paper],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 8) {
                Group {
                    if composeOpen {
                        TextField("What's on your mind?", text: $draft, axis: .vertical)
                            .font(Theme.Font.serifItalic(16))
                            .foregroundStyle(Theme.Palette.ink)
                            .focused($composeFocused)
                            .lineLimit(1...6)
                            .submitLabel(.send)
                            .onSubmit(send)
                    } else {
                        Text("Capture, ask, or note…")
                            .font(Theme.Font.serifItalic(15))
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(Theme.Motion.overshoot(0.42)) { composeOpen = true }
                                composeFocused = true
                            }
                    }
                }
                .padding(.leading, 18)
                .padding(.vertical, 8)

                Button(action: composeOpen ? send : { composeOpen = true; composeFocused = true }) {
                    Image(systemName: composeOpen ? "arrow.up" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(composeOpen ? Theme.Palette.forest : Theme.Palette.ink))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .frame(minHeight: 52, alignment: composeOpen ? .bottom : .center)
            .background(
                RoundedRectangle(cornerRadius: composeOpen ? 18 : 26, style: .continuous)
                    .fill(Theme.Palette.card)
                    .overlay(RoundedRectangle(cornerRadius: composeOpen ? 18 : 26, style: .continuous)
                        .stroke(Theme.Palette.rule, lineWidth: 1))
            )
            .shadow1()
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
            .background(Theme.Palette.paper)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            withAnimation(Theme.Motion.standard()) { composeOpen = false }
            return
        }
        withAnimation(Theme.Motion.overshoot(0.4)) {
            userTurns.append(text)
            draft = ""
            composeOpen = false
        }
        composeFocused = false
        emitRing()
        halo.setState(.thinking)

        // Hand the message to the agent loop (a capture the agent reasons over).
        let payload = CapturePayload(text: text, kind: "auto", chapterID: nil)
        let event = AppEvent(type: .captureReceived, payload: payload)
        context.insert(event)
        try? context.save()
        let eventID = event.id
        Task { await AtlasAgent.shared.tickOnce() }
        Task { @MainActor in
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let evt = (try? context.fetch(FetchDescriptor<AppEvent>()))?.first { $0.id == eventID }
                if let evt, evt.status == .done || evt.status == .failed { halo.setState(.delivered); return }
            }
            halo.setState(.delivered)
        }
    }

    private func emitRing() {
        let item = EORingItem(point: CGPoint(x: 200, y: 560))
        rings.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            rings.removeAll { $0.id == item.id }
        }
    }
}

// MARK: - Ayumi turn

private struct AyumiTurn<Embed: View>: View {
    let when: String
    let prose: Text
    var source: String? = nil
    @ViewBuilder var embed: () -> Embed

    init(when: String, prose: Text, source: String? = nil, @ViewBuilder embed: @escaping () -> Embed = { EmptyView() }) {
        self.when = when; self.prose = prose; self.source = source; self.embed = embed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // thread line + avatar
            VStack(spacing: 6) {
                AyumiAvatar(size: 12)
                Rectangle()
                    .fill(LinearGradient(colors: [Theme.Palette.tealDeep.opacity(0.7), Theme.Palette.rule],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                    Text(when).font(Theme.Font.mono(9.5)).tracking(0.6).foregroundStyle(Theme.Palette.ink3)
                }
                .padding(.bottom, 6)

                prose
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                if let source {
                    Text(source)
                        .font(Theme.Font.mono(9))
                        .tracking(0.5)
                        .foregroundStyle(Theme.Palette.ink4)
                        .padding(.top, 8)
                }

                embed().padding(.top, 12)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

private struct ThinkingTurn: View {
    let text: String
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.Palette.jade)
                .frame(width: 7, height: 7)
                .scaleEffect(on ? 1.18 : 1.0)
                .opacity(on ? 1 : 0.55)
                .padding(.leading, 14)
            Text(text)
                .font(Theme.Font.serifItalic(14.5))
                .foregroundStyle(Theme.Palette.ink2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

// MARK: - User turn

private struct UserTurn: View {
    let text: String
    let when: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Text(when).font(Theme.Font.mono(9.5)).tracking(0.6).foregroundStyle(Theme.Palette.ink3)
                Text("YOU").font(Theme.Font.mono(9.5)).tracking(1.5).foregroundStyle(Theme.Palette.ink3)
            }
            Text(text)
                .font(Theme.Font.sans(14.5))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 4, topTrailingRadius: 18, style: .continuous)
                        .fill(Theme.Palette.ink)
                )
                .frame(maxWidth: 280, alignment: .trailing)
                .shadow1()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 10)
    }
}

// MARK: - Brief capsule (morphs to a letter)

private struct BriefCapsule: View {
    let glyph: String
    let title: String
    let when: String
    let onOpen: () -> Void
    var onOpenFull: () -> Void = {}
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.Palette.ink)
                    Circle().fill(RadialGradient(colors: [Theme.Palette.avatarInk.opacity(0.55), .clear],
                                                 center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: 10))
                    Text(glyph).font(Theme.Font.serifItalic(11)).foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)

                Text(title).font(Theme.Font.serifItalic(15)).foregroundStyle(Theme.Palette.ink).lineLimit(1)
                Spacer(minLength: 8)
                Text(when).font(Theme.Font.mono(9.5)).tracking(0.4).foregroundStyle(Theme.Palette.tealDeep)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink4)
            }
            .padding(.vertical, 9)
            .padding(.leading, 14)
            .padding(.trailing, 14)

            if open {
                letter
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: open ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: open ? 10 : 999, style: .continuous).fill(Theme.Palette.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: open ? 10 : 999, style: .continuous))
        .shadow1()
        .fixedSize(horizontal: !open, vertical: false)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Theme.Motion.overshootStrong(0.55)) { open.toggle() }
            if open { onOpen() }
        }
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
            label("Person")
            row("Karan Mehta — VP Product. You met at the Lightspeed dinner; he runs the retention pod.")
            label("Likely to come up")
            confRow(0.94, "Whether m6 cohort retention held after the pricing change.")
            confRow(0.31, "A follow-on round — early, but he may float it.")
            label("Open with")
            row("\"The churn slide moved — V. sent fresher numbers this morning.\"")
            Button { onOpenFull() } label: {
                Text("OPEN FULL BRIEF →")
                    .font(Theme.Font.mono(10)).tracking(1.2)
                    .foregroundStyle(Theme.Palette.tealDeep)
                    .padding(.top, 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
    private func label(_ s: String) -> some View {
        Text(s.uppercased()).font(Theme.Font.mono(9.5)).tracking(1.5)
            .foregroundStyle(Theme.Palette.ink3).padding(.top, 14).padding(.bottom, 2)
    }
    private func row(_ s: String) -> some View {
        Text(s).font(Theme.Font.serifItalic(14.5)).foregroundStyle(Theme.Palette.ink2)
            .lineSpacing(4).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
    }
    private func confRow(_ v: Double, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ConfidencePill(value: v)
            Text(s).font(Theme.Font.serifItalic(14.5)).foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) }
    }
}
