import SwiftUI
import SwiftData

/// Capture — the full cognitive loop. Write a note → Ayumi reads (halo thinking,
/// real agent run) → files it (halo delivered) → a result turn cross-fades in
/// with the extracted items (the Proposals the agent created from this capture).
struct CaptureScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context

    enum Phase { case writing, reading, filed }
    @State private var phase: Phase = .writing
    /// The agent's real output for this capture (empty → show canned demo items).
    @State private var liveExtracted: [(Tag, String, String)] = []
    @State private var loopTask: Task<Void, Never>?
    @State private var draft = "We can't keep eating the churn slide every QBR — V. has fresher M6 numbers. Decide before the Karan call: do we reprice, or hold and show the curve?"
    @State private var rings: [EORingItem] = []
    @FocusState private var focused: Bool

    private var wordCount: Int {
        draft.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                if phase == .filed {
                    result.transition(.opacity)
                } else {
                    writing.transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            sendZone
            EOLayer(rings: rings)
        }
        .task {
            // DEV: auto-fire the capture loop for screenshot verification.
            if ProcessInfo.processInfo.arguments.contains("--autosend") {
                try? await Task.sleep(nanoseconds: 900_000_000)
                send()
            }
        }
    }

    // ─── Writing phase ────────────────────────────────────────────
    private var writing: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(AtlasFormat.weekday.string(from: Date())) · 9:41 AM".uppercased())
                .font(Theme.Font.mono(9.5)).tracking(1.7).foregroundStyle(Theme.Palette.ink3)
                .padding(.bottom, 8)
            Text("What did you notice today?")
                .font(Theme.Font.serifItalic(34)).foregroundStyle(Theme.Palette.ink)
                .tracking(-0.4).lineSpacing(1).fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Begin anywhere…")
                        .font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.inkFaint)
                        .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(Theme.Font.serif(18))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(8)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .disabled(phase == .reading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.paperDeep)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1))
            )
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
        .opacity(phase == .reading ? 0.55 : 1)
    }

    // ─── Result phase ─────────────────────────────────────────────
    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AyumiAvatar(size: 18)
                    Text("Ayumi").font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text("just now").font(Theme.Font.mono(9.5)).foregroundStyle(Theme.Palette.ink4)
                }
                .padding(.vertical, 6)

                ayumiProse([
                    .init("Filed under "),
                    .init("Stratyfix", .accent),
                    .init(". I pulled three things out."),
                ], size: 19, color: Theme.Palette.ink)
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

                Text(draft.isEmpty ? "We can't keep eating the churn slide every QBR — V. has fresher numbers." : draft)
                    .font(Theme.Font.serif(15)).foregroundStyle(Theme.Palette.ink2).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.Palette.hairline).frame(width: 2) }
                    .padding(.vertical, 12)

                VStack(spacing: 8) {
                    if liveExtracted.isEmpty {
                        extractedItem(.todo, "Send Karan the M6 retention dashboard", "due today · linked to Stratyfix", idx: 0)
                        extractedItem(.decision, "Lead with retention, not the round", "logged · Stratyfix", idx: 1)
                        extractedItem(.chapter, "Stratyfix", "6th note this month", idx: 2)
                    } else {
                        ForEach(Array(liveExtracted.enumerated()), id: \.offset) { idx, e in
                            extractedItem(e.0, e.1, e.2, idx: idx)
                        }
                    }
                }
                .padding(.top, 8)

                Spacer().frame(height: 96)
            }
        }
        .scrollIndicators(.hidden)
    }

    private enum Tag { case todo, decision, chapter }
    @State private var revealed = false
    private func extractedItem(_ tag: Tag, _ title: String, _ meta: String, idx: Int) -> some View {
        HStack(alignment: .top, spacing: 11) {
            tagPill(tag)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Font.serif(15.5)).foregroundStyle(Theme.Palette.ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta).font(Theme.Font.mono(9)).tracking(0.4).foregroundStyle(Theme.Palette.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.card))
        .shadow1()
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 8)
        .animation(Theme.Motion.overshootStrong(0.42).delay(0.12 * Double(idx + 1)), value: revealed)
    }
    private func tagPill(_ tag: Tag) -> some View {
        let (text, bg, fg, border): (String, Color, Color, Color?) = {
            switch tag {
            case .todo:     return ("TODO", Theme.Palette.tealSoft, Theme.Palette.tealDeep, nil)
            case .decision: return ("DECISION", Theme.Palette.forest, Color(hex: 0xD7E8DE), nil)
            case .chapter:  return ("CHAPTER", Theme.Palette.paperDeep, Theme.Palette.ink2, Theme.Palette.rule)
            }
        }()
        return Text(text)
            .font(Theme.Font.mono(8.5)).tracking(1.2).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(bg))
            .overlay(border.map { Capsule().stroke($0, lineWidth: 1) })
            .padding(.top, 1)
    }

    // ─── Send zone ────────────────────────────────────────────────
    private var sendZone: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.Palette.paper.opacity(0), Theme.Palette.paper], startPoint: .top, endPoint: .bottom)
                .frame(height: 30).allowsHitTesting(false)
            HStack(spacing: 10) {
                if phase == .filed {
                    Button { reset() } label: {
                        Text("NEW CAPTURE").font(Theme.Font.mono(9.5)).tracking(1.0).foregroundStyle(Theme.Palette.ink3)
                    }.buttonStyle(.plain)
                    Spacer()
                } else {
                    Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
                        .font(Theme.Font.mono(9.5)).tracking(0.5).foregroundStyle(Theme.Palette.ink4)
                    Spacer()
                    Button { send() } label: {
                        Text(phase == .reading ? "Ayumi is reading…" : "Send to Ayumi")
                            .font(Theme.Font.serif(16)).foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Capsule().fill(phase == .reading ? Theme.Palette.jade : Theme.Palette.ink))
                            .opacity(wordCount == 0 && phase == .writing ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(phase == .reading || (wordCount == 0 && phase == .writing))
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 14).padding(.top, 4)
            .background(Theme.Palette.paper)
        }
    }

    // ─── Loop ─────────────────────────────────────────────────────
    private func send() {
        guard wordCount > 0 else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendStart = Date()
        emitRing()
        halo.setState(.thinking)
        withAnimation(Theme.Motion.standard(0.22)) { phase = .reading }
        focused = false

        // Write the real AppEvent → wake the agent → poll until it's processed →
        // render the Proposals it created. Works with the dormant fallback too
        // (CaptureHandler files a pending proposal when there's no API key).
        let payload = CapturePayload(text: trimmed, kind: "auto", chapterID: nil)
        let event = AppEvent(type: .captureReceived, payload: payload)
        context.insert(event)
        try? context.save()
        let eventID = event.id

        Task { await AtlasAgent.shared.tickOnce() }

        loopTask?.cancel()
        loopTask = Task { @MainActor in
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                let evt = (try? context.fetch(FetchDescriptor<AppEvent>()))?.first { $0.id == eventID }
                if let evt, evt.status == .done || evt.status == .failed {
                    finishFiled(since: sendStart)
                    return
                }
            }
            finishFiled(since: sendStart)   // timed out — surface whatever landed
        }
    }

    @MainActor private func finishFiled(since: Date) {
        // Pull the pending proposals created by this capture run.
        let pendingRaw = ProposalStatus.pending.rawValue
        let props = (try? context.fetch(FetchDescriptor<Proposal>(
            predicate: #Predicate { $0.createdAt >= since && $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        ))) ?? []
        liveExtracted = props.prefix(4).map { p in
            let tag: Tag = { switch p.type { case .todo: .todo; case .chapter, .chapterLink: .chapter; default: .decision } }()
            let title = proposalTitle(p)
            let meta = [p.sourceLabel, p.sourceMeta].compactMap { $0 }.joined(separator: " · ")
            return (tag, title, meta.isEmpty ? "just now" : meta)
        }
        halo.setState(.delivered)
        withAnimation(Theme.Motion.standard(0.4)) { phase = .filed }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { revealed = true }
    }

    private func proposalTitle(_ p: Proposal) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: p.proposedPayloadJSON) as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let t = dict["title"] as? String { return t }
            if let c = dict["content"] as? String { return c }
        }
        return p.summary ?? "Captured"
    }

    private func reset() {
        loopTask?.cancel()
        halo.setState(.idle)
        revealed = false
        liveExtracted = []
        withAnimation(Theme.Motion.standard(0.4)) { phase = .writing; draft = "" }
    }
    private func emitRing() {
        let item = EORingItem(point: CGPoint(x: 250, y: 760))
        rings.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { rings.removeAll { $0.id == item.id } }
    }
}
