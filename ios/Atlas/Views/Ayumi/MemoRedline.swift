import SwiftUI
import UIKit

// MARK: - The word-level redline (the finer pen)
//
// The morning memo renders as ONE flowing piece of prose — a brief in Ayumi's
// voice, not bullet rows — and the strike gesture works at WORD granularity:
// drag across three words, exactly three words get the line through them.
//
// Finger ≠ Apple Pencil, so precision is ENGINEERED rather than assumed:
//   · words are the snap grid — the finger paints a rough band, the system
//     resolves it to whole words (precision comes from snapping, not aim);
//   · a haptic tick fires on every word-boundary crossing — the finger feels
//     the grid, so strokes stop where they're meant to;
//   · tap any single word to toggle just that word — the fine-tune layer
//     (bigger target than a drag-handle, and one gesture instead of two);
//   · a horizontal-intent gate keeps ink and scroll from fighting: a drag
//     that starts sideways is ink, a drag that starts downward is scroll.
//
// Persistence semantics (server: turn.strike):
//   · partial strike  → a PUT: the line lives on, its struckWords recorded;
//   · every word of a line struck → the FULL strike (struck=true) with its
//     existing effects (backing notes forgotten, pending proposal dismissed);
//   · nothing is ever hard-deleted — struck ink IS the record.

// MARK: word atoms

/// One word of the memo prose — the atom the red pen snaps to.
struct RedlineWord: Identifiable, Equatable {
    let id: Int          // flat index in reading order across the whole memo
    let lineIdx: Int     // which memo line it belongs to
    let wordIdx: Int     // index within that line's tokenization
    let text: String
    let style: ProseStyle
    let endsSentence: Bool   // last word of its memo line — gets a breath after it

    static func == (a: RedlineWord, b: RedlineWord) -> Bool { a.id == b.id }
}

/// Tokenize memo lines into the flat word list. Markup-aware: each word keeps
/// the run style (*roman* / ==accent== / italic) it was written in. Word
/// indices are per-line and match the server's `struckWords` contract
/// (markup-stripped, whitespace-split).
func tokenizeMemoLines(_ lines: [TurnMemoLine]) -> [RedlineWord] {
    var words: [RedlineWord] = []
    var flat = 0
    for (lineIdx, line) in lines.enumerated() {
        let runs = parseAyumiMarkup(line.text).first ?? [ProseRun(line.text)]
        var pieces: [(String, ProseStyle)] = []
        for run in runs {
            for w in run.text.split(separator: " ", omittingEmptySubsequences: true) {
                pieces.append((String(w), run.style))
            }
        }
        for (wordIdx, piece) in pieces.enumerated() {
            words.append(
                RedlineWord(
                    id: flat,
                    lineIdx: lineIdx,
                    wordIdx: wordIdx,
                    text: piece.0,
                    style: piece.1,
                    endsSentence: wordIdx == pieces.count - 1
                ))
            flat += 1
        }
    }
    return words
}

// MARK: flow layout

/// Wraps the word views into flowing prose lines. Word gap ≈ a serif space;
/// a slightly wider breath after each sentence (memo line) keeps the seams
/// readable without bullets.
struct RedlineFlowLayout: Layout {
    var wordGap: CGFloat = 3.8
    var sentenceGap: CGFloat = 7.5
    var lineSpacing: CGFloat = 7

    /// sizeThatFits + placeSubviews share one pass.
    private func arrange(
        sizes: [CGSize], breaths: [Bool], in width: CGFloat
    ) -> (offsets: [CGPoint], height: CGFloat) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (i, size) in sizes.enumerated() {
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + (breaths[i] ? sentenceGap : wordGap)
        }
        return (offsets, y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let breaths = subviews.map { $0[SentenceBreathKey.self] }
        let (_, height) = arrange(sizes: sizes, breaths: breaths, in: width)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let breaths = subviews.map { $0[SentenceBreathKey.self] }
        let (offsets, _) = arrange(sizes: sizes, breaths: breaths, in: bounds.width)
        for (i, sub) in subviews.enumerated() {
            sub.place(
                at: CGPoint(x: bounds.minX + offsets[i].x, y: bounds.minY + offsets[i].y),
                proposal: .unspecified)
        }
    }
}

/// Marks a word as the last of its sentence so the layout adds a breath.
private struct SentenceBreathKey: LayoutValueKey {
    static let defaultValue = false
}

// MARK: frame capture

private struct WordFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: the prose view + gesture engine

/// The memo as redlineable prose. Owns the stroke gesture; reports committed
/// strikes per line upward (`onCommit(lineIdx, struckWordIdxs)`).
struct RedlineProse: View {
    let lines: [TurnMemoLine]
    let size: CGFloat
    /// Called once per affected line when a stroke/tap commits.
    let onCommit: (_ lineIdx: Int, _ struckWords: [Int]) -> Void

    @State private var frames: [Int: CGRect] = [:]
    /// Live stroke state: anchor + frontier word ids, and whether this stroke erases.
    @State private var anchor: Int? = nil
    @State private var frontier: Int? = nil
    @State private var erasing = false
    /// .undecided until the first ~10pt of movement reveals intent.
    @State private var intent: StrokeIntent = .undecided
    private enum StrokeIntent { case undecided, ink, scroll }

    private let tick = UISelectionFeedbackGenerator()

    private var words: [RedlineWord] { tokenizeMemoLines(lines) }

    /// Word ids inside the live stroke band (reading order between anchor and frontier).
    private var liveSpan: ClosedRange<Int>? {
        guard let a = anchor, let f = frontier else { return nil }
        return min(a, f)...max(a, f)
    }

    private func isPersistedStruck(_ w: RedlineWord) -> Bool {
        let line = lines[w.lineIdx]
        if line.struck { return true }
        return line.struckWords?.contains(w.wordIdx) ?? false
    }

    var body: some View {
        let words = self.words
        let byLine = Dictionary(grouping: words, by: \.lineIdx)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.indices), id: \.self) { lineIdx in
                if lineIdx > 0 {
                    // The soft rule between thoughts — the prototype's rhythm.
                    Rectangle().fill(Theme.Palette.ruleSoft)
                        .frame(height: 1)
                        .padding(.vertical, 11)
                }
                RedlineFlowLayout() {
                    ForEach(byLine[lineIdx] ?? []) { w in
                        wordView(w)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: WordFramesKey.self,
                                        value: [w.id: geo.frame(in: .named("redline"))])
                                })
                    }
                }
            }
        }
        .coordinateSpace(name: "redline")
        .onPreferenceChange(WordFramesKey.self) { frames = $0 }
        .contentShape(Rectangle())
        .gesture(strokeGesture(words: words))
    }

    @ViewBuilder
    private func wordView(_ w: RedlineWord) -> some View {
        let persisted = isPersistedStruck(w)
        let inLive = liveSpan.map { $0.contains(w.id) } ?? false
        // Live ink previews the outcome: striking shows the line-through in
        // teal (wet ink); an erasing stroke previews removal by lifting it.
        let showsStrike = (persisted && !(inLive && erasing)) || (inLive && !erasing)
        let wet = inLive
        ayumiProse([ProseRun(w.text, w.style)], size: size,
                   color: showsStrike ? Theme.Palette.ink3 : Theme.Palette.ink)
            .strikethrough(showsStrike, color: wet ? Theme.Palette.tealDeep : Theme.Palette.ink3)
            .animation(.easeOut(duration: 0.12), value: showsStrike)
            .onTapGesture { commitTap(w) }
    }

    // ── gesture ──────────────────────────────────────────────────────

    private func strokeGesture(words: [RedlineWord]) -> some Gesture {
        DragGesture(minimumDistance: 9, coordinateSpace: .named("redline"))
            .onChanged { g in
                switch intent {
                case .scroll:
                    return
                case .undecided:
                    let dx = abs(g.translation.width), dy = abs(g.translation.height)
                    guard max(dx, dy) > 9 else { return }
                    // The gate: sideways = ink, downward = scroll.
                    if dx > dy * 1.1 {
                        intent = .ink
                        tick.prepare()
                        anchor = nearestWord(to: g.startLocation)
                        erasing = anchor.map { words[$0] }.map(isPersistedStruck) ?? false
                    } else {
                        intent = .scroll
                        return
                    }
                    fallthrough
                case .ink:
                    guard anchor != nil else { return }
                    let hit = nearestWord(to: g.location)
                    if hit != frontier {
                        frontier = hit
                        tick.selectionChanged()   // the finger feels each word
                    }
                }
            }
            .onEnded { _ in
                defer { anchor = nil; frontier = nil; intent = .undecided; erasing = false }
                guard intent == .ink, let span = liveSpan else { return }
                commitSpan(span, erase: erasing, words: words)
            }
    }

    /// Word under the point, else the nearest within a forgiving radius —
    /// vertical misses snap to the row, horizontal misses to the word edge.
    private func nearestWord(to p: CGPoint) -> Int? {
        if let exact = frames.first(where: { $0.value.insetBy(dx: -2, dy: -4).contains(p) }) {
            return exact.key
        }
        var best: (id: Int, d: CGFloat)? = nil
        for (id, f) in frames {
            let cx = max(f.minX, min(p.x, f.maxX))
            let cy = max(f.minY, min(p.y, f.maxY))
            let d = hypot(p.x - cx, p.y - cy)
            if d < (best?.d ?? 28) { best = (id, d) }   // 28pt forgiveness
        }
        return best?.id
    }

    // ── commits ──────────────────────────────────────────────────────

    /// A tap toggles exactly one word — the precision layer.
    private func commitTap(_ w: RedlineWord) {
        let line = lines[w.lineIdx]
        var set = currentStruckSet(line)
        if set.contains(w.wordIdx) { set.remove(w.wordIdx) } else { set.insert(w.wordIdx) }
        tick.selectionChanged()
        onCommit(w.lineIdx, set.sorted())
    }

    /// A stroke commits per affected line: union (ink) or subtraction (erase).
    private func commitSpan(_ span: ClosedRange<Int>, erase: Bool, words: [RedlineWord]) {
        let touched = words.filter { span.contains($0.id) }
        let byLine = Dictionary(grouping: touched, by: \.lineIdx)
        for (lineIdx, ws) in byLine {
            var set = currentStruckSet(lines[lineIdx])
            for w in ws {
                if erase { set.remove(w.wordIdx) } else { set.insert(w.wordIdx) }
            }
            onCommit(lineIdx, set.sorted())
        }
    }

    private func currentStruckSet(_ line: TurnMemoLine) -> Set<Int> {
        if line.struck {
            // A fully-struck line re-entered word-wise: start from "all words".
            let count = tokenizeMemoLines([line]).count
            return Set(0..<count)
        }
        return Set(line.struckWords ?? [])
    }
}
