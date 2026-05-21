import SwiftUI
import SwiftData

/// The Morning Page — Atlas drafts a paragraph in your voice from overnight
/// signals; you read it, strike sentences that miss, then Send to chapters
/// to file the extracts. Hosts:
///   • strike-settle (animation #3): drag-left strikethrough draws first
///     then the row compresses (font + padding) with a 120ms delay.
///   • sentence-fly-to-chapters (animation #1): on Send, coloured dots
///     fly from each sentence's right edge to the Chapters bottom-tab.
///     As the last dot arrives, the Chapters tab pulses.
///   • Filed confirmation panel settles in once flying completes.
struct MorningView: View {
    @Environment(\.modelContext) private var context
    @Query private var chapters: [Chapter]

    @State private var struck: Set<String> = []
    @State private var refining: String? = nil
    @State private var overrideText: [String: String] = [:]
    @State private var done: Bool = false
    @State private var flying: [FlyingDot]? = nil

    // The chapters tab target is set by the parent (RootView passes the bounds).
    let chaptersTabFrame: CGRect

    // Captured sentence row frames in global (window) coordinates.
    @State private var sentenceFrames: [String: CGRect] = [:]

    private var page: MorningPageData { SEEDED_MORNING_PAGE }

    private var liveExtractCounts: [String: Int] {
        var totals: [String: Int] = [:]
        for s in page.sentences where !struck.contains(s.id) {
            guard let e = s.extracts else { continue }
            if let n = e.todo     { totals["todo",     default: 0] += n }
            if let n = e.decision { totals["decision", default: 0] += n }
            if let n = e.journal  { totals["journal",  default: 0] += n }
        }
        return totals
    }

    private var countsText: String {
        let totals = liveExtractCounts
        let parts: [String] = [
            totals["todo"].map { "\($0) todo\($0 == 1 ? "" : "s")" },
            totals["decision"].map { "\($0) decision\($0 == 1 ? "" : "s")" },
            totals["journal"].map { "\($0) journal \($0 == 1 ? "note" : "notes")" },
        ].compactMap { $0 }
        guard parts.count > 0 else { return "" }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                    .padding(.vertical, 20)
                sentenceList
                if !done { ifYouKeepThisStrip }
                if !done { actionsRow }
                if done { filedConfirmation }
                Spacer().frame(height: 90)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .overlay(
            // Flying-dot layer — full-screen, ignores safe area so dots can
            // reach the bottom nav.
            Group {
                if let flying { FlyingExtracts(dots: flying) }
            }
        )
        .onPreferenceChange(SentenceFramePref.self) { frames in
            sentenceFrames = frames
        }
    }

    // ─── Header ──────────────────────────────────────────────────
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(page.range) · DRAFTED IN YOUR VOICE")
                .font(Theme.Font.mono(9.5))
                .tracking(2.0)
                .foregroundStyle(Theme.Palette.inkFaint)
            Text("This morning")
                .font(Theme.Font.serifItalic(48))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(2)
            Text("Read it like rereading yourself. Swipe a line away if I got it wrong. Tap to nudge.")
                .font(Theme.Font.serifItalic(14))
                .foregroundStyle(Theme.Palette.inkFaint)
                .lineSpacing(3)
                .padding(.top, 8)
        }
    }

    // ─── Sentences ──────────────────────────────────────────────
    private var sentenceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(page.sentences) { s in
                SentenceRow(
                    sentence: s,
                    isStruck: struck.contains(s.id),
                    isRefining: refining == s.id,
                    override: overrideText[s.id],
                    onStrike: {
                        if struck.contains(s.id) { struck.remove(s.id) }
                        else { struck.insert(s.id) }
                    },
                    onTap: {
                        refining = refining == s.id ? nil : s.id
                    },
                    onRefineSubmit: { text in
                        overrideText[s.id] = text
                        refining = nil
                    },
                    onRefineCancel: { refining = nil }
                )
            }
        }
    }

    // ─── "If you keep this" summary ────────────────────────────
    private var ifYouKeepThisStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IF YOU KEEP THIS")
                .font(Theme.Font.mono(9.5))
                .tracking(1.8)
                .foregroundStyle(Theme.Palette.inkFaint)
            if countsText.isEmpty {
                Text("Nothing will be filed — the page is empty.")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
            } else {
                HStack(spacing: 4) {
                    Text("I'll quietly add ")
                        .font(Theme.Font.serifItalic(14))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    Text(countsText)
                        .font(Theme.Font.serifItalic(14))
                        .foregroundStyle(Theme.Palette.tealDeep)
                    Text(" to your chapters.")
                        .font(Theme.Font.serifItalic(14))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
        .padding(.top, 24)
    }

    // ─── Send to chapters + Ask Atlas ───────────────────────────
    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                fireSendToChapters()
            } label: {
                HStack(spacing: 8) {
                    Text("Send to chapters")
                        .font(Theme.Font.sans(14, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(flying != nil)
            .opacity(flying != nil ? 0.55 : 1)

            Button { /* AskAtlas — Phase 2 */ } label: {
                Text("Ask Atlas")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
    }

    // ─── Filed confirmation ─────────────────────────────────────
    private var filedConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FILED")
                .font(Theme.Font.mono(9.5))
                .tracking(2.0)
                .foregroundStyle(Theme.Palette.forest)
            Text("Your morning is in the chapters." +
                 (countsText.isEmpty ? "" : " \(countsText), all in place."))
                .font(Theme.Font.serifItalic(16))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.forestSoft)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.Palette.forest, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.top, 24)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // ─── Send-to-chapters trigger ───────────────────────────────
    private func fireSendToChapters() {
        guard !done, flying == nil else { return }

        var dots: [FlyingDot] = []
        var stagger: Int = 0
        let target = CGPoint(x: chaptersTabFrame.midX, y: chaptersTabFrame.midY)

        for s in page.sentences {
            if struck.contains(s.id) || s.extracts == nil { continue }
            guard let frame = sentenceFrames[s.id] else { continue }
            let kinds: [(String, Int?)] = [
                ("todo", s.extracts?.todo),
                ("decision", s.extracts?.decision),
                ("journal", s.extracts?.journal),
            ]
            var dotIndex = 0
            for (kind, maybeCount) in kinds {
                guard let count = maybeCount else { continue }
                for _ in 0..<count {
                    let from = CGPoint(
                        x: frame.maxX - 18 - CGFloat(dotIndex) * 12,
                        y: frame.midY
                    )
                    let jitter = CGFloat.random(in: -3...3)
                    dots.append(FlyingDot(
                        id: UUID(),
                        kind: kind,
                        from: from,
                        to: CGPoint(x: target.x + jitter, y: target.y),
                        delay: Double(stagger) / 1000.0
                    ))
                    stagger += 60
                    dotIndex += 1
                }
            }
        }

        if dots.isEmpty {
            persistExtracts()
            withAnimation(.easeOut(duration: 0.32)) { done = true }
            return
        }

        flying = dots
        let arrivalAt = (Double(stagger) / 1000.0) + 0.62

        // One-shot pulse of the Chapters tab (handled via state passed back to
        // RootView via the chaptersTabFrame change — we trigger a notification
        // by posting to NotificationCenter; RootView listens.)
        DispatchQueue.main.asyncAfter(deadline: .now() + arrivalAt - 0.2) {
            NotificationCenter.default.post(name: .atlasChaptersTabPulse, object: nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + arrivalAt + 0.25) {
            self.persistExtracts()
            self.flying = nil
            withAnimation(.easeOut(duration: 0.32)) { self.done = true }
        }
    }

    private func persistExtracts() {
        let now = Date()
        for s in page.sentences where !struck.contains(s.id) {
            guard let e = s.extracts, let hint = s.chapterHint else { continue }
            guard let chapter = chapters.first(where: { $0.title.hasPrefix(hint) }) else { continue }
            let text = overrideText[s.id] ?? s.text
            for _ in 0..<(e.todo ?? 0) {
                let t = Todo(text: text, chapter: chapter)
                t.source = .extracted
                context.insert(t)
            }
            for _ in 0..<(e.decision ?? 0) {
                context.insert(Decision(
                    title: String(text.prefix(120)),
                    rationale: text,
                    decidedAt: now,
                    chapter: chapter
                ))
            }
            for _ in 0..<(e.journal ?? 0) {
                context.insert(Entry(date: now, content: text, source: .manual, chapter: chapter))
            }
        }
        try? context.save()
    }
}

extension Notification.Name {
    static let atlasChaptersTabPulse = Notification.Name("AtlasChaptersTabPulse")
}

// ─── PreferenceKey for sentence frames ────────────────────────────
struct SentenceFramePref: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// ─── FlyingDot model + view ────────────────────────────────────────
struct FlyingDot: Identifiable, Equatable {
    let id: UUID
    let kind: String      // "todo" / "decision" / "journal"
    let from: CGPoint
    let to: CGPoint
    let delay: Double
}

struct FlyingExtracts: View {
    let dots: [FlyingDot]
    @State private var phase: Phase = .start
    enum Phase { case start, flying }

    private func color(for kind: String) -> Color {
        switch kind {
        case "todo":     return Theme.Palette.forest
        case "decision": return Theme.Palette.teal
        default:         return Theme.Palette.inkSecondary
        }
    }

    var body: some View {
        GeometryReader { _ in
            ForEach(dots) { dot in
                Circle()
                    .fill(color(for: dot.kind))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().stroke(.white, lineWidth: 1.6).opacity(0.85)
                    )
                    .scaleEffect(phase == .start ? 0.5 : 1)
                    .opacity(phase == .start ? 0 : 1)
                    .position(phase == .start ? dot.from : dot.to)
                    .animation(
                        .timingCurve(0.55, 0, 0.35, 1, duration: 0.62).delay(dot.delay),
                        value: phase
                    )
                    .animation(
                        .easeOut(duration: 0.24).delay(dot.delay),
                        value: phase
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    phase = .flying
                }
            }
        }
    }
}

// ─── Sentence row with strike-settle (animation #3) ──────────────
struct SentenceRow: View {
    let sentence: MorningSentenceData
    let isStruck: Bool
    let isRefining: Bool
    let override: String?
    let onStrike: () -> Void
    let onTap: () -> Void
    let onRefineSubmit: (String) -> Void
    let onRefineCancel: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var dragging: Bool = false
    @State private var refineDraft: String = ""
    @FocusState private var refineFocused: Bool

    private let threshold: CGFloat = 100

    private var strikeProgress: CGFloat {
        if dragging {
            if isStruck {
                return max(0, 1 - max(0, dragX) / threshold)
            } else {
                return min(1, max(0, -dragX) / threshold)
            }
        }
        return isStruck ? 1 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(override ?? sentence.text)
                    .font(.system(size: isStruck ? 13 : 19, design: .serif))
                    .foregroundStyle(isStruck ? Theme.Palette.inkFainter : Theme.Palette.ink)
                    .lineSpacing(isStruck ? 1.35 - 1 : 1.42 - 1)
                    .opacity(isStruck ? 0.7 : 1)
                    .overlay(
                        GeometryReader { proxy in
                            // Strikethrough bar — draws over the text proportional to progress
                            Rectangle()
                                .fill(Theme.Palette.inkFaint)
                                .frame(width: proxy.size.width * strikeProgress, height: 1.2)
                                .position(
                                    x: proxy.size.width * strikeProgress / 2,
                                    y: proxy.size.height * 0.55
                                )
                                .animation(dragging ? nil : .easeOut(duration: 0.38), value: strikeProgress)
                                .allowsHitTesting(false)
                        }
                    )
                    .animation(.easeOut(duration: 0.42).delay(0.12), value: isStruck)
                Spacer(minLength: 0)
                if override != nil {
                    Text("EDITED")
                        .font(Theme.Font.mono(9))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.tealDeep)
                }
            }
            .padding(.vertical, isStruck ? 5 : 10)
            .animation(.easeOut(duration: 0.42).delay(0.12), value: isStruck)
            .background(
                // Capture the row frame in global coords for sentence-fly anim.
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SentenceFramePref.self,
                        value: [sentence.id: proxy.frame(in: .global)]
                    )
                }
            )

            if isRefining {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NUDGE ATLAS")
                        .font(Theme.Font.mono(9))
                        .tracking(2.0)
                        .foregroundStyle(Theme.Palette.tealDeep)
                    TextField("say it differently…", text: $refineDraft, axis: .vertical)
                        .font(Theme.Font.serifItalic(15))
                        .foregroundStyle(Theme.Palette.ink)
                        .focused($refineFocused)
                        .lineLimit(2...4)
                    HStack {
                        Spacer()
                        Button("cancel") { onRefineCancel() }
                            .font(Theme.Font.serifItalic(12.5))
                            .foregroundStyle(Theme.Palette.inkFaint)
                        Button {
                            let v = refineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if v.isEmpty { onRefineCancel() } else { onRefineSubmit(v) }
                        } label: {
                            Text("use this")
                                .font(Theme.Font.sans(12.5, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.Palette.tealDeep)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Theme.Palette.tealSoft.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.Palette.teal, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.top, 8)
                .padding(.bottom, 4)
                .onAppear {
                    refineDraft = override ?? ""
                    refineFocused = true
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.hairline.opacity(0.5))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragging = true
                    dragX = value.translation.width
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let moved = abs(dx) > 4
                    if !moved {
                        onTap()
                    } else if isStruck && dragX > threshold * 0.5 {
                        onStrike()  // toggle back
                    } else if !isStruck && -dragX > threshold * 0.5 {
                        onStrike()  // strike
                    }
                    dragging = false
                    dragX = 0
                }
        )
    }
}
