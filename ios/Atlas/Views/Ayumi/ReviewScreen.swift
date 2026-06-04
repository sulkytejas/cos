import SwiftUI
import SwiftData

/// Review — approve/decline what Ayumi did overnight. A stack of review cards;
/// resolving one slides it out with a Halo pulse, and clearing the queue blooms
/// the Halo gold and reveals "All clear."
struct ReviewScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    @Environment(AtlasRepo.self) private var repo

    @Query(filter: #Predicate<Proposal> { $0.statusRaw == "pending" },
           sort: \.createdAt, order: .reverse)
    private var pending: [Proposal]

    enum Tone { case draft, filed, held }
    struct Item: Identifiable {
        let id = UUID()
        let tag: String; let tone: Tone; let when: String
        let lead: String; let said: String; let trail: String
        let why: String; let cite: String
        let approve: String; let decline: String
        /// Backing proposal when this card is driven by live data; nil for seed.
        var proposal: Proposal? = nil
    }

    @State private var queue: [Item] = seed
    @State private var flickerWork: DispatchWorkItem?

    /// True when the cards on screen are seed fallback (empty DB).
    private var usingSeed: Bool { pending.isEmpty }

    /// The cards to render — live proposals when present, else seed fallback.
    private var items: [Item] {
        pending.isEmpty ? queue : pending.map(Self.toViewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                openLine
                if items.isEmpty {
                    allClear
                } else {
                    countRow
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            card(item)
                                .transition(.asymmetric(insertion: .identity,
                                                         removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    }
                    .padding(.top, 8)
                }
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
        }
    }

    // ─── Framing ──────────────────────────────────────────────────
    private var openLine: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AyumiAvatar(size: 18)
                Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("02:14 → 06:38").font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink4)
            }
            ayumiProse([
                .init("I did "),
                .init("four things", .accent),
                .init(" overnight and held them for you. Nothing's been sent — your call on each."),
            ], size: 21, color: Theme.Palette.ink)
            .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var countRow: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text("\(items.count)").font(Theme.Font.serifItalic(22)) + Text(" to review").font(Theme.Font.serif(22)))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { approveAll() } label: {
                Text("APPROVE ALL").font(Theme.Font.mono(9.5)).tracking(1.0).foregroundStyle(Theme.Palette.tealDeep)
            }.buttonStyle(.plain)
        }
        .padding(.top, 18).padding(.bottom, 8)
    }

    // ─── Card ─────────────────────────────────────────────────────
    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                tagPill(item)
                Spacer()
                Text(item.when).font(Theme.Font.mono(9)).tracking(0.4).foregroundStyle(Theme.Palette.ink4)
            }
            .padding(.bottom, 8)

            (Text(item.lead).font(Theme.Font.serif(16)).foregroundStyle(Theme.Palette.ink)
             + Text(item.said).font(Theme.Font.serifItalic(16)).foregroundStyle(Theme.Palette.ink2)
             + Text(item.trail).font(Theme.Font.serif(16)).foregroundStyle(Theme.Palette.ink))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)

            Text(item.why).font(Theme.Font.serifItalic(13.5)).foregroundStyle(Theme.Palette.inkFaint)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.top, 8)

            Text(item.cite).font(Theme.Font.mono(9)).tracking(0.6).foregroundStyle(Theme.Palette.tealDeep).padding(.top, 8)

            HStack(spacing: 8) {
                Button { approve(item) } label: {
                    Text(item.approve).font(Theme.Font.serif(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.ink))
                }.buttonStyle(.plain)
                Button { decline(item) } label: {
                    Text(item.decline).font(Theme.Font.serif(14)).foregroundStyle(Theme.Palette.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.paperDeep)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.Palette.rule, lineWidth: 1)))
                }.buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.card))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow1()
    }

    private func tagPill(_ item: Item) -> some View {
        let (bg, fg, border): (Color, Color, Color?) = {
            switch item.tone {
            case .draft: return (Theme.Palette.tealSoft, Theme.Palette.tealDeep, nil)
            case .filed: return (Theme.Palette.paperDeep, Theme.Palette.ink2, Theme.Palette.rule)
            case .held:  return (Theme.Palette.confLowBg, Theme.Palette.confLowInk, nil)
            }
        }()
        return Text(item.tag.uppercased())
            .font(Theme.Font.mono(8.5)).tracking(1.2).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(bg))
            .overlay(border.map { Capsule().stroke($0, lineWidth: 1) })
    }

    private var allClear: some View {
        VStack(spacing: 12) {
            Text("All clear.").font(Theme.Font.serifItalic(40)).foregroundStyle(Theme.Palette.ink)
            Text("Nothing else waiting. I'll keep watching and bring you the next thing when it matters.")
                .font(Theme.Font.serifItalic(16)).foregroundStyle(Theme.Palette.inkFaint)
                .multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60).padding(.horizontal, 24)
        .transition(.opacity)
    }

    // ─── Resolve ──────────────────────────────────────────────────

    /// Approve: live → repo.approve (optimistic-local flip + server fan-out,
    /// transition-guarded so a retry can't double-file, §4.d); seed → array removal.
    private func approve(_ item: Item) {
        if let proposal = item.proposal {
            halo.setState(.thinking)
            let id = proposal.id
            // The visible row removal animates off the @Query refresh after the
            // server write lands; the write itself isn't an animatable mutation,
            // so run it as a plain Task (wrapping it in withAnimation is a no-op).
            Task { try? await repo.approve(id) }
            scheduleHalo()
        } else {
            resolveSeed(item)
        }
    }

    /// Decline: live → repo.dismiss (optimistic-local then write-through);
    /// seed → array removal.
    private func decline(_ item: Item) {
        if let proposal = item.proposal {
            halo.setState(.thinking)
            let id = proposal.id
            // See approve(_:) — the row animates off the @Query refresh, so the
            // server write runs as a plain Task (withAnimation here is a no-op).
            Task { try? await repo.dismiss(id) }
            scheduleHalo()
        } else {
            resolveSeed(item)
        }
    }

    /// Halo flicker after a live resolve — delivered once the live queue empties.
    private func scheduleHalo() {
        flickerWork?.cancel()
        // pending still contains this proposal until the @Query refreshes; the
        // queue is empty when it was the last one.
        let empty = pending.count <= 1
        let work = DispatchWorkItem { halo.setState(empty ? .delivered : .idle) }
        flickerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    /// Seed fallback resolve — keeps the original demo array-removal animation.
    private func resolveSeed(_ item: Item) {
        halo.setState(.thinking)
        withAnimation(.timingCurve(0.34, 1.06, 0.64, 1, duration: 0.36)) {
            queue.removeAll { $0.id == item.id }
        }
        flickerWork?.cancel()
        let empty = queue.isEmpty
        let work = DispatchWorkItem { halo.setState(empty ? .delivered : .idle) }
        flickerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func approveAll() {
        if !pending.isEmpty {
            halo.setState(.thinking)
            let ids = pending.map(\.id)
            for (i, id) in ids.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i)) {
                    // Staggered server writes; rows animate off the @Query refresh.
                    Task { try? await repo.approve(id) }
                    if i == ids.count - 1 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { halo.setState(.delivered) }
                    }
                }
            }
            return
        }
        halo.setState(.thinking)
        let items = queue
        for (i, item) in items.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i)) {
                withAnimation(.timingCurve(0.34, 1.06, 0.64, 1, duration: 0.36)) {
                    queue.removeAll { $0.id == item.id }
                }
                if i == items.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { halo.setState(.delivered) }
                }
            }
        }
    }

    // ─── Mapping ──────────────────────────────────────────────────

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Map a live Proposal onto the existing card Item shape, deriving the tag /
    /// tone / button labels from the proposal type.
    private static func toViewModel(_ p: Proposal) -> Item {
        let (tag, tone, approve, decline): (String, Tone, String, String) = {
            switch p.type {
            case .todo:
                return ("Todo drafted", .draft, "Add todo", "Skip")
            case .decision, .journalEntry:
                return ("Filed", .filed, "Keep", "Archive")
            case .chapter, .chapterLink:
                return ("Held", .held, "Add", "Dismiss")
            }
        }()
        let cite: String = {
            switch (p.sourceLabel, p.sourceMeta) {
            case let (label?, meta?): return "trace · \(label) · \(meta)"
            case let (label?, nil):   return "trace · \(label)"
            case let (nil, meta?):    return "trace · \(meta)"
            default:                  return ""
            }
        }()
        return Item(
            tag: tag, tone: tone,
            when: timeFormatter.string(from: p.createdAt),
            lead: "", said: p.summary ?? "", trail: "",
            why: p.reasoning ?? "", cite: cite,
            approve: approve, decline: decline,
            proposal: p
        )
    }

    // ─── Seed ─────────────────────────────────────────────────────
    // Authoritative copy mirrors `Atlas v0.6 - Review × Halo.html`: only the
    // `said` span is the italic ink-2 run; the lead/trail stay roman ink.
    static let seed: [Item] = [
        .init(tag: "Draft reply", tone: .draft, when: "03:42",
              lead: "Reply to ", said: "Karan", trail: " — \"Sending the M6 cohort slice ahead of 2:30. See you then.\"",
              why: "He asked twice; a short ack keeps you warm without overcommitting.",
              cite: "trace · gmail thread + your calendar", approve: "Send it", decline: "Not yet"),
        .init(tag: "Filed", tone: .filed, when: "04:10",
              lead: "Filed 23 newsletters; surfaced ", said: "one", trail: " — the SaaS retention teardown you star things like.",
              why: "Matches 9 prior saves. Want it in the Stratyfix thread?",
              cite: "trace · inbox rules + save history", approve: "Keep in thread", decline: "Just archive"),
        .init(tag: "Held", tone: .held, when: "05:05",
              lead: "A recruiter pinged about a Dublin role. I ", said: "held it", trail: " — looked relevant to Ireland MBA.",
              why: "Could be noise. Promote to the chapter, or dismiss?",
              cite: "trace · linkedin + Ireland watcher", approve: "Add to Ireland", decline: "Dismiss"),
        .init(tag: "Todo drafted", tone: .draft, when: "06:30",
              lead: "Drafted a todo: ", said: "\"Confirm V.'s new 11:30 studio time.\"", trail: "",
              why: "Her email moved the sitting; you haven't replied.",
              cite: "trace · gmail + calendar", approve: "Add todo", decline: "Skip"),
    ]
}
