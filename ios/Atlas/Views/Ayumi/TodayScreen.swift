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
    @State private var rings: [EORingItem] = []

    private let space = "today.scroll"

    /// DEBUG: `--today-demo` forces the seeded demo thread (the design-mock copy)
    /// so the screen can be pixel-compared against the handout regardless of live data.
    private var forceDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--today-demo")
        #else
        false
        #endif
    }
    /// DEBUG: `--today-bottom` opens the thread scrolled to the foot (for shooting
    /// the bottom of the screen against the mock).
    private var scrollBottomDebug: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--today-bottom")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DayDivider(label: "while you slept", roman: "02:14 → 06:38")

                    if briefs.isEmpty || forceDemo {
                    AyumiTurn(when: "06:38",
                              paragraphs: [
                                ayumiProse([
                                    .init("I worked through the night. A note from "),
                                    .init("Karan", .roman),
                                    .init(" landed at "),
                                    .init("03:42", .roman),
                                    .init(" — I held it."),
                                ], size: 17),
                                ayumiProse([
                                    .init("Drafted you a brief for "),
                                    .init("14:30", .accent),
                                    .init(", opened with the cohort, not the round. The portrait sitting tomorrow shifted one block south — folded under your stack."),
                                ], size: 17),
                              ],
                              source: "6 sources · email, voice memo, calendar, deck v3") {
                        BriefCapsule(glyph: "K", title: "Karan, in 90 minutes.", when: "14:30",
                                     onOpen: { emitRing(); halo.setState(.delivered) })
                    }

                    UserTurn(text: "thanks — anything else I should know before the call?", when: "07:15")

                    AyumiTurn(when: "07:15",
                              thinking: "reading the deck and yesterday's voice memo…")

                    AyumiTurn(when: "07:16",
                              paragraphs: [ayumiProse([
                                .init("Two small things. Your "),
                                .init("deck v3", .accent),
                                .init(" still has the old churn slide — I can swap it for the cohort curve in five minutes if you want. And "),
                                .init("V.", .roman),
                                .init(" emailed about Thursday with a softer studio time, "),
                                .init("11:30", .accent),
                                .init(" instead of "),
                                .init("11:00", .accent),
                                .init(" — I haven't accepted yet."),
                              ], size: 17)],
                              source: "3 sources · drive, gmail, calendar") {
                        BriefCapsule(glyph: "S", title: "Swap the churn slide", when: "5 min",
                                     onOpen: { emitRing(); halo.setState(.delivered) })
                    }
                    } else {
                        ForEach(Array(briefs.prefix(4))) { b in
                            AyumiTurn(when: b.when ?? "today",
                                      paragraphs: [ayumiProse([.init(b.preview ?? b.relevance ?? b.situationDescription)], size: 17)],
                                      source: b.drafted) {
                                BriefCapsule(glyph: String(b.title.prefix(1)).uppercased(),
                                             title: b.title, when: b.when ?? "",
                                             onOpen: { emitRing(); halo.setState(.delivered) },
                                             onOpenFull: { withAnimation(Theme.Motion.overshoot()) { router.go(.brief) } })
                            }
                        }
                    }

                    DayDivider(label: "now", roman: "09:41")
                    Spacer().frame(height: 76)   // CSS .conv bottom inset 60 + padding 16
                }
                .padding(.horizontal, 22)
                .padding(.top, 60)               // app-mark(pageTop+30) → divider ≈ +38px gap
            }
            .coordinateSpace(name: space)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(scrollBottomDebug ? .bottom : .top)
            // The page already sits below the Dynamic Island (PageShell insets it
            // within the safe area). Without this the ScrollView ADDS the safe-area
            // inset a second time, pushing the whole thread ~59px down — the "huge"
            // top gap. Our explicit .padding(.top, 76) now positions content exactly.
            .ignoresSafeArea(.container, edges: .top)

            // v0.7: the bottom compose pill was removed — it was redundant with
            // the global Capture cue (mounted in PageShell). Today now reaches
            // Ayumi the same way every other screen does: summon in place.
            EOLayer(rings: rings)
        }
    }

    // ─── Capture ──────────────────────────────────────────────────
    // The bottom compose pill was retired in v0.7. Capturing a thought is now
    // global: summon Ayumi in place from the cue at the foot of every screen
    // (PageShell → CaptureHost). This screen keeps only its reading thread.

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
    var paragraphs: [Text] = []
    var source: String? = nil
    var thinking: String? = nil
    @ViewBuilder var embed: () -> Embed

    init(when: String, paragraphs: [Text] = [], source: String? = nil, thinking: String? = nil,
         @ViewBuilder embed: @escaping () -> Embed = { EmptyView() }) {
        self.when = when; self.paragraphs = paragraphs; self.source = source
        self.thinking = thinking; self.embed = embed
    }

    var body: some View {
        // CSS: `.turn { padding: 10px 0 14px 18px }` — 18px left gutter = the
        // 12px avatar/thread column + 6px spacing.
        HStack(alignment: .top, spacing: 6) {
            // thread line + avatar (CSS: 1px line, teal-deep→rule, opacity .7)
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
                .padding(.bottom, 8)   // .turn-meta { margin-bottom: 8px }

                // CSS: `.body { font-size:17px; line-height:1.46 }`, paragraphs
                // separated by `p + p { margin-top: 8px }` (NOT a blank line).
                if !paragraphs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                            p.lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // The thinking line sits in the prose column (green-dot bullet),
                // not at content-left — it reads as Ayumi reasoning aloud.
                if let thinking {
                    ThinkingLine(text: thinking)
                }

                if let source {
                    Text(source)
                        .font(Theme.Font.mono(9.5))
                        .tracking(0.5)
                        .foregroundStyle(Theme.Palette.ink4)
                        .padding(.top, 8)   // .src-tag { margin-top: 8px }
                }

                embed().padding(.top, 12)   // .ssatom { margin-top: 12px }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

/// The green-dot "thinking" bullet. Rendered inside an `AyumiTurn` prose column
/// (the avatar/thread gutter + "Ayumi 07:15" header come from the parent), so the
/// dot sits indented under the prose — matching the mock — not at content-left.
private struct ThinkingLine: View {
    let text: String
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.Palette.jade)
                .frame(width: 7, height: 7)
                .scaleEffect(on ? 1.18 : 1.0)
                .opacity(on ? 1 : 0.55)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
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
                .font(Theme.Font.sans(15.5))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 4, topTrailingRadius: 18, style: .continuous)
                        .fill(Theme.Palette.ink)
                )
                .frame(maxWidth: 248, alignment: .trailing)
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
        Group {
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow(stretch: true)
                    letter.transition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Collapsed: hug short titles (like the mock), but never exceed the
                // thread column. A long live title caps to the available width and
                // truncates instead of forcing the whole screen wider — that
                // intrinsic overflow is what was centering/clipping all of Today.
                ViewThatFits(in: .horizontal) {
                    headerRow(stretch: false)
                    headerRow(stretch: true).frame(maxWidth: .infinity)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: open ? 8 : 999, style: .continuous).fill(Theme.Palette.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: open ? 8 : 999, style: .continuous))
        .shadow1()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Theme.Motion.overshootStrong(0.55)) { open.toggle() }
            if open { onOpen() }
        }
    }

    /// The pill / letter head row. `stretch` pushes time+chevron to the far edge
    /// (used when the capsule fills its column); otherwise the row hugs content.
    private func headerRow(stretch: Bool) -> some View {
        let meta = Self.shortWhen(when)
        // The cap-glyph is a plain obsidian square with a single catchlight —
        // no initial inside (matches the mock). The `glyph` argument is kept on
        // the API for callers but is intentionally not rendered here.
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.Palette.ink)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(RadialGradient(colors: [Theme.Palette.avatarInk.opacity(0.55), .clear],
                                             center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 11))
                )
                .frame(width: 18, height: 18)

            // Title fills (and truncates) when the capsule stretches; the short
            // time meta keeps its intrinsic width so it always stays readable.
            Text(title).font(Theme.Font.serifItalic(15)).foregroundStyle(Theme.Palette.ink)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: stretch ? .infinity : nil, alignment: .leading)
            if !stretch { Spacer().frame(width: 12) }
            if !meta.isEmpty {
                Text(meta).font(Theme.Font.mono(9.5)).tracking(0.4).foregroundStyle(Theme.Palette.tealDeep)
                    .lineLimit(1).fixedSize()
            }
        }
        // Capsule: padding 8px 12px 8px 16px (the mock hugs its content and
        // shows no chevron — open is signalled by the letter unfurling).
        .padding(.vertical, 8)
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }

    /// The live `when` is "today · X"; everything is "today", so drop that
    /// redundant prefix and keep the meaningful tail (a time or short label) so
    /// the title gets the room — matching the mock's short trailing time.
    static func shortWhen(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        let lower = t.lowercased()
        for p in ["today · ", "today·", "today - ", "today "] where lower.hasPrefix(p) {
            t = String(t.dropFirst(p.count)); break
        }
        return t.lowercased() == "today" ? "" : t.trimmingCharacters(in: .whitespaces)
    }

    private var letter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.Palette.rule).frame(height: 1)   // border-top 1px
            label("Person")
            row("Karan Mehta · Partner at Sequoia · led your A round in '22. He runs late — plan for 20 minutes, not 30.")
            label("Likely to come up")
            confRow(0.94, "Net retention by cohort — M6 and M12.")
            confRow(0.88, "Whether seed is enough to skip an A.")
            confRow(0.31, "The IP side-letter.")
            label("Open with")
            row("Retention, not the round. He'll be impatient otherwise — and the cohort is the strongest thing you have.")
            Button { onOpenFull() } label: {
                Text("OPEN FULL BRIEF →")
                    .font(Theme.Font.mono(10)).tracking(1.2)
                    .foregroundStyle(Theme.Palette.tealDeep)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {        // border-bottom 1px teal
                        Rectangle().fill(Theme.Palette.tealDeep.opacity(0.3)).frame(height: 1)
                    }
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
