import SwiftUI
import SwiftData

/// Brief — the densest AI surface: Ayumi's pre-meeting brief on a person.
/// Framing → title → person → timeline (with citations) → tactical → predictions
/// → materials checklist → quote, over a sticky "Start the meeting" action bar.
struct BriefScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    @Environment(AtlasRepo.self) private var repo

    /// Most-recent surfaced Brief, if any. Empty → hardcoded fallback below.
    @Query(filter: #Predicate<Brief> { $0.statusRaw == "surfaced" },
           sort: \.surfaceAt, order: .reverse)
    private var surfacedBriefs: [Brief]

    @State private var ready: [String: Bool] = ["m1": true, "m2": true, "m3": false, "m4": false]
    @State private var receipt: Receipt? = nil
    @State private var rings: [EORingItem] = []
    @State private var started = false

    // ─── Live brief binding ───────────────────────────────────────
    /// The brief we drive sections from, or nil → fully hardcoded screen.
    private var liveBrief: Brief? { surfacedBriefs.first }

    /// Decode structureData ONCE (same approach as BriefRenderer.structure).
    private var structure: BriefStructure? {
        guard let liveBrief else { return nil }
        return try? JSONDecoder().decode(BriefStructure.self, from: liveBrief.structureData)
    }

    // Per-kind section data, present only when the decoded brief carries it.
    private var personData: PersonData? {
        structure?.sections.compactMap { if case .person(let d) = $0 { return d } else { return nil } }.first
    }
    private var timelineData: TimelineData? {
        structure?.sections.compactMap { if case .timeline(let d) = $0 { return d } else { return nil } }.first
    }
    private var tacticalData: TacticalData? {
        structure?.sections.compactMap { if case .tactical(let d) = $0 { return d } else { return nil } }.first
    }
    private var predictionData: PredictionData? {
        structure?.sections.compactMap { if case .prediction(let d) = $0 { return d } else { return nil } }.first
    }
    private var materialsData: MaterialsData? {
        structure?.sections.compactMap { if case .materials(let d) = $0 { return d } else { return nil } }.first
    }
    private var quoteData: QuoteData? {
        structure?.sections.compactMap { if case .quote(let d) = $0 { return d } else { return nil } }.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    framing
                    // The 46pt slot is a subject/name, not a sentence. Use the
                    // brief's person name when it carries one; otherwise this is
                    // the static demo, so show the demo subject (matches the mock)
                    // rather than a live digest title like "Handled while you slept."
                    Text((personData?.name).map { $0 + "." } ?? "Karan Mehta.")
                        .font(Theme.Font.serifItalic(46))
                        .foregroundStyle(Theme.Palette.ink)
                        .tracking(-0.9)
                        .padding(.top, 18)
                    HStack(spacing: 8) {
                        Text("today · 14:30").font(Theme.Font.mono(10)).tracking(0.4).foregroundStyle(Theme.Palette.tealDeep)
                        Rectangle().fill(Theme.Palette.rule).frame(width: 1, height: 9)
                        Text("Sequoia India · seed").font(Theme.Font.mono(10)).tracking(0.4).foregroundStyle(Theme.Palette.ink3)
                    }
                    .padding(.top, 6)

                    section("Person") { personBlock }
                    section("Your history with Karan") { timeline }
                    section("Ayumi suggests") { tactical }
                    section("Likely to come up") { predictions }
                    section("Have these open") { materials }
                    section("In his words") { quote }

                    Spacer().frame(height: 110)
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
            }

            actionZone
            EOLayer(rings: rings)

            if let receipt {
                ReceiptSheetView(receipt: receipt) { withAnimation(Theme.Motion.standard(0.28)) { self.receipt = nil } }
                    .zIndex(30)
            }
        }
        .onAppear(perform: syncReadyFromMaterials)
    }

    // ─── Sections ─────────────────────────────────────────────────
    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(Theme.Font.mono(9)).tracking(2.0)
                .foregroundStyle(Theme.Palette.ink3)
                .padding(.bottom, 10)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
    }

    private var framing: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AyumiAvatar(size: 18)
                Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("drafted 06:40 · 6 sources").font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink4)
            }
            ayumiProse([
                .init("You have "),
                .init("20 minutes", .accent),
                .init(" with "),
                .init("Karan", .roman),
                .init(". He'll want signal, not a pitch — open with the retention curve and let the round come to you."),
            ], size: 21, color: Theme.Palette.ink)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var personBlock: some View {
        HStack(alignment: .top, spacing: 13) {
            AvatarObsidian(initials: personData.map { Self.initials($0.name) } ?? "KM", size: 50)
            VStack(alignment: .leading, spacing: 0) {
                Text(personData?.name ?? "Karan Mehta").font(Theme.Font.serif(21)).foregroundStyle(Theme.Palette.ink)
                Text(personData?.role ?? "Partner · Sequoia India").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink2).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    if let facts = personData?.facts, !facts.isEmpty {
                        ForEach(facts, id: \.self) { fact($0) }
                    } else {
                        fact("Led the seed in your last company; warm but exacting.")
                        fact("Writes publicly about retention — reads replies.")
                        fact("Prefers a 20-minute walk to a deck.")
                    }
                }
                .padding(.top, 12)
            }
        }
    }
    private func fact(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.Palette.ink4).frame(width: 4, height: 4)
            Text(s).font(Theme.Font.serif(15)).foregroundStyle(Theme.Palette.ink2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let items = timelineData?.items, !items.isEmpty {
                ForEach(items) { item in
                    timelineItem(date: item.date, text: item.text, inferred: item.subtle ?? false, cite: nil)
                }
            } else {
                timelineItem(date: "2026 · 01 · 14", text: "Dinner at Soam — you walked him through the wedge.", inferred: false, cite: nil)
                timelineItem(date: "2026 · 03 · 02", text: "Liked your tweet about the M6 curve.", inferred: true, cite: ("cite · twitter", .tw))
                timelineItem(date: "2026 · 04 · 11", text: "Coffee at Blue Tokai — he floated intros.", inferred: false, cite: nil)
                timelineItem(date: "2026 · 05 · 18", text: "No reply to the data-room email yet.", inferred: true, cite: ("cite · email", .em))
            }
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Palette.rule).frame(width: 1).padding(.vertical, 4)
        }
    }
    private func timelineItem(date: String, text: String, inferred: Bool, cite: (String, ReceiptKey)?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date).font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink3)
            Text(text)
                .font(inferred ? Theme.Font.serifItalic(15) : Theme.Font.serif(15))
                .foregroundStyle(Theme.Palette.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let cite { CiteButton(label: cite.0) { open(cite.1) }.padding(.top, 5) }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(inferred ? Color.clear : Theme.Palette.ink)
                .overlay(Circle().stroke(Theme.Palette.ink, lineWidth: inferred ? 1 : 0))
                .frame(width: 7, height: 7)
                .offset(x: -20, y: 4)
        }
    }

    private var tactical: some View {
        JadeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("OPEN WITH").font(Theme.Font.mono(9)).tracking(1.6).foregroundStyle(Theme.Palette.jadeCardInk.opacity(0.7))
                Text(tacticalData.map { "\"\($0.text)\"" } ?? "\"The churn moved — V. sent fresher M6 numbers this morning. Want me to walk you through it?\"")
                    .font(Theme.Font.serifItalic(17)).foregroundStyle(Theme.Palette.jadeCardInk).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                CiteButton(label: "2 traces · email + voice memo", tint: Color(hex: 0x1F6647)) { open(.tac) }
            }
        }
    }

    private var predictions: some View {
        VStack(spacing: 0) {
            if let items = predictionData?.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    predictionRow(item.text, Self.confidenceScore(item.confidence), last: idx == items.count - 1)
                }
            } else {
                predictionRow("Whether the M6 cohort held after the pricing change.", 0.94, last: false)
                predictionRow("How you're thinking about the next hire.", 0.88, last: false)
                predictionRow("Burn vs. the new plan.", 0.62, last: false)
                predictionRow("A follow-on — early, but he may float it.", 0.31, last: true)
            }
        }
    }
    private func predictionRow(_ text: String, _ score: Double, last: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text).font(Theme.Font.serifItalic(15.5)).foregroundStyle(Theme.Palette.ink2)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ConfidencePill(value: score, forced: score >= 0.8 ? .high : (score >= 0.5 ? .med : .low))
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
    }

    private var materials: some View {
        VStack(spacing: 0) {
            if let items = materialsData?.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    materialRow("m\(idx)", item.text, last: idx == items.count - 1)
                }
            } else {
                materialRow("m1", "M6 retention dashboard", last: false)
                materialRow("m2", "Fresh churn slide (V.'s numbers)", last: false)
                materialRow("m3", "Cap table — current", last: false)
                materialRow("m4", "The one-line ask", last: true)
            }
        }
    }
    private func materialRow(_ id: String, _ text: String, last: Bool) -> some View {
        let on = ready[id] ?? false
        return Button { ready[id] = !on } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.Palette.ink : Theme.Palette.ink4, lineWidth: 1)
                    if on {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.ink)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 17, height: 17)
                Text(text).font(Theme.Font.serif(15))
                    .foregroundStyle(on ? Theme.Palette.inkFaint : Theme.Palette.ink)
                    .strikethrough(on, color: Theme.Palette.rule)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.standard(0.2), value: on)
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quoteData.map { "\"\($0.text)\"" } ?? "\"Show me the curve held. The rest is narrative.\"")
                .font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.ink).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(quoteData.map { "— \($0.attribution)" } ?? "— Karan, dinner at Soam, Jan 14")
                .font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink3)
        }
        .padding(.leading, 18)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.rule).frame(width: 2) }
    }

    // ─── Action zone ──────────────────────────────────────────────
    private var actionZone: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.Palette.paper.opacity(0), Theme.Palette.paper], startPoint: .top, endPoint: .bottom)
                .frame(height: 32).allowsHitTesting(false)
            HStack(spacing: 10) {
                Button {
                    emitRing(); halo.setState(.delivered)
                    withAnimation(Theme.Motion.standard(0.22)) { started = true }
                    act(.start)   // server flips status + emits brief_acted_on (§4.a)
                } label: {
                    Text(started ? "Meeting started" : "Start the meeting")
                        .font(Theme.Font.serif(17)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(started ? Theme.Palette.forest : Theme.Palette.ink))
                }
                .buttonStyle(.plain)
                Button { act(.snooze) } label: {
                    Text("Snooze").font(Theme.Font.serif(15)).foregroundStyle(Theme.Palette.ink)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.paperDeep)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.Palette.rule, lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.bottom, 12)
            .background(Theme.Palette.paper)
        }
    }

    // ─── Brief actions (Start / Snooze) ───────────────────────────
    /// Act on the live brief through the repo: optimistic-local status flip +
    /// write-through (server flips status AND emits `brief_acted_on`, §4.a).
    /// No-op for the static demo brief (no server row to act on).
    private func act(_ action: BriefAction) {
        guard let id = liveBrief?.id else { return }
        Task { try? await repo.actOnBrief(id, action: action) }
    }

    // ─── Receipts ─────────────────────────────────────────────────
    private func open(_ key: ReceiptKey) {
        withAnimation(Theme.Motion.overshootStrong(0.38)) { receipt = Receipt.canned[key] }
    }
    private func emitRing() {
        let item = EORingItem(point: CGPoint(x: 150, y: 740))
        rings.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { rings.removeAll { $0.id == item.id } }
    }

    // ─── Live-data helpers ────────────────────────────────────────
    /// Seed the checkbox state from the decoded materials' `ready` flags so
    /// the live checklist opens in the brief's intended state.
    private func syncReadyFromMaterials() {
        guard let items = materialsData?.items, !items.isEmpty else { return }
        var next = ready
        for (idx, item) in items.enumerated() where next["m\(idx)"] == nil {
            next["m\(idx)"] = item.ready
        }
        ready = next
    }

    private static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }

    private static func confidenceScore(_ c: PredictionData.Item.Confidence) -> Double {
        switch c {
        case .high:   return 0.94
        case .medium: return 0.62
        case .low:    return 0.31
        }
    }
}

// MARK: - Receipt model + sheet

enum ReceiptKey { case tw, em, tac }
struct Receipt: Identifiable {
    let id = UUID()
    let title: String
    let deck: String
    let sources: [Source]
    struct Source: Identifiable { let id = UUID(); let kind: String; let ref: String; let tint: Color }

    static let canned: [ReceiptKey: Receipt] = [
        .tw: Receipt(title: "He liked your tweet about the M6 curve.",
                     deck: "First signal Karan reads your public writing.",
                     sources: [.init(kind: "Twitter", ref: "@karanm liked · 2026-03-02 18:42", tint: Theme.Palette.tealDeep)]),
        .em: Receipt(title: "No reply yet to the data-room email.",
                     deck: "Thread is open; he read it twice on his phone.",
                     sources: [.init(kind: "Gmail", ref: "sent 2026-05-16 09:11 · 2 opens", tint: Theme.Palette.tealDeep)]),
        .tac: Receipt(title: "Lead with retention, not the round.",
                      deck: "Two traces support this.",
                      sources: [.init(kind: "Email", ref: "karan@sequoiacap.com · 2026-01-15 09:33", tint: Theme.Palette.tealDeep),
                                .init(kind: "Voice", ref: "voice memo · 2026-05-26 walk · 02:11 in", tint: Theme.Palette.forest)]),
    ]
}

private struct ReceiptSheetView: View {
    let receipt: Receipt
    let onClose: () -> Void
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x0D141A).opacity(0.32).ignoresSafeArea()
                .onTapGesture(perform: onClose).transition(.opacity)
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Theme.Palette.ink4.opacity(0.6)).frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity).padding(.bottom, 14)
                Text(receipt.title).font(Theme.Font.serif(21)).foregroundStyle(Theme.Palette.ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(receipt.deck).font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink2)
                    .padding(.top, 6).padding(.bottom, 14).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(receipt.sources.enumerated()), id: \.element.id) { idx, s in
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 5).fill(s.tint).frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.kind.uppercased()).font(Theme.Font.mono(9)).tracking(1.5).foregroundStyle(Theme.Palette.ink3)
                            Text(s.ref).font(Theme.Font.serif(13.5)).foregroundStyle(Theme.Palette.ink)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { if idx < receipt.sources.count - 1 { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
                }
                Text("ANCHORED · OBSIDIAN SEAL").font(Theme.Font.mono(9)).tracking(1.5).foregroundStyle(Theme.Palette.tealDeep)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.5))
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: Color(hex: 0x141820, opacity: 0.18), radius: 18, x: 0, y: -8)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea()
    }
}
