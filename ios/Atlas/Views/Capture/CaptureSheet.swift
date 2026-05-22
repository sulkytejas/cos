import SwiftUI
import SwiftData

struct CaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Chapter.updatedAt, order: .reverse) private var chapters: [Chapter]
    @FocusState private var textFocused: Bool

    @State private var text: String = ""
    @State private var kind: CaptureKind = .todo
    @State private var chapterID: UUID?
    /// When non-nil, the sheet is in "Atlas is thinking" mode, waiting for
    /// the agent to mark this AppEvent done (or fall back to a manual file).
    @State private var pendingEventID: UUID? = nil
    @State private var pollTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if pendingEventID != nil {
                thinkingState
            } else {
                composeState
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Atlas-is-thinking state

    private var thinkingState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 60)
            MicroText(text: "Ayumi is thinking")
            Text("Reading your capture, looking around your chapters, and drafting proposals.")
                .font(Theme.Font.serifItalic(20))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(4)
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.Palette.teal)
                .padding(.top, 12)
            Spacer()
            Button("Stop waiting — keep it for me to file later") {
                pollTask?.cancel()
                dismiss()
            }
            .font(Theme.Font.serifItalic(13))
            .foregroundStyle(Theme.Palette.inkFaint)
            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .background(Theme.Palette.paper)
    }

    // MARK: - Compose state (original UI)

    private var composeState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag handle
            HStack { Spacer()
                Capsule()
                    .fill(Theme.Palette.hairline)
                    .frame(width: 38, height: 3)
                Spacer()
            }
            .padding(.top, 10).padding(.bottom, 16)

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    MicroText(text: "Capture")
                    Text("What is it?")
                        .font(Theme.Font.serifItalic(32))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(0)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)

            // Textarea with char-count footer
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        // Italic placeholder — editorial cue
                        Text("Type or paste anything. Ayumi will figure out what kind of thing it is.")
                            .font(Theme.Font.serifItalic(18))
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .lineSpacing(3)
                            .padding(.top, 14)
                            .padding(.horizontal, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .focused($textFocused)
                        .font(Theme.Font.serif(18))
                        .foregroundStyle(Theme.Palette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(minHeight: 110)
                }
                // Char count footer
                HStack {
                    Spacer()
                    Text(text.isEmpty ? "—" : "\(text.count) char")
                        .font(Theme.Font.mono(9.5))
                        .tracking(0.8)
                        .foregroundStyle(Theme.Palette.inkFainter)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .background(Theme.Palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Kind selector
            KindSelector(value: $kind)
                .padding(.horizontal, 22)
                .padding(.top, 14)

            // Chapter chips
            VStack(alignment: .leading, spacing: 8) {
                MicroText(text: "Chapter")
                FlowLayout(spacing: 8) {
                    ForEach(chapters) { c in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                chapterID = c.id
                            }
                        } label: {
                            Text(c.title)
                                .font(Theme.Font.serifItalic(15))
                                .foregroundStyle(chapterID == c.id ? .white : Theme.Palette.inkSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(chapterID == c.id ? Theme.Palette.ink : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(chapterID == c.id ? Theme.Palette.ink : Theme.Palette.hairline, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Save
            Button {
                save()
            } label: {
                Text("Save as \(kind.label.lowercased())")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.atlasPrimary)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Spacer()
        }
        .background(Theme.Palette.paper)
        .onAppear {
            if chapterID == nil {
                chapterID = (chapters.first(where: { $0.status == .active }) ?? chapters.first)?.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { textFocused = true }
        }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chapterID != nil
    }

    /// Save flow — writes an AppEvent for the agent to process, then enters
    /// the thinking state and polls until the event is marked done. Falls
    /// back to the original direct-insert path if no API key is configured
    /// (so captures still feel instant when the engine is dormant).
    private func save() {
        guard let cid = chapterID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let payload = CapturePayload(
            text: trimmed,
            kind: kind.rawValue,
            chapterID: cid
        )
        let event = AppEvent(type: .captureReceived, payload: payload)
        context.insert(event)
        try? context.save()

        pendingEventID = event.id
        // Nudge the agent to wake up right away rather than waiting on its
        // 30s sleep timer.
        Task { await AtlasAgent.shared.tickOnce() }
        startPolling(eventID: event.id)
    }

    private func startPolling(eventID: UUID) {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            for _ in 0..<90 {   // ~90s max — agent timeouts at ~90s too
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if let evt = (try? context.fetch(FetchDescriptor<AppEvent>()))?
                    .first(where: { $0.id == eventID }) {
                    if evt.status == .done || evt.status == .failed {
                        await MainActor.run { dismiss() }
                        return
                    }
                }
            }
            // Timed out — give up but leave the event in flight; the agent
            // will still process it.
            await MainActor.run { dismiss() }
        }
    }
}

// Simple flow layout for chapter chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width {
                x = 0; y += rowH + spacing; rowH = 0
            }
            rowH = max(rowH, s.height)
            x += s.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            rowH = max(rowH, s.height)
            x += s.width + spacing
        }
    }
}
