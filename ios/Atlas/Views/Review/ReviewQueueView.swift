import SwiftUI
import SwiftData

/// ReviewQueueView — the v0.2 brief's /review surface as an iOS screen.
/// Lists pending Proposals with filter chips by type, per-row approve / edit /
/// dismiss. Approve converts the proposal into a real Todo / Decision / Entry
/// and marks the proposal approved (so it shows up in "filed today" surfaces).
struct ReviewQueueView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Proposal.createdAt, order: .reverse) private var allProposals: [Proposal]
    @State private var filter: ProposalFilter = .all
    @State private var editing: Proposal? = nil

    enum ProposalFilter: String, CaseIterable, Identifiable {
        case all, todo, decision, journal, asked
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .todo: return "Todos"
            case .decision: return "Decisions"
            case .journal: return "Journal"
            case .asked: return "Asked"
            }
        }
    }

    private var pending: [Proposal] {
        allProposals.filter { $0.status == .pending }
    }

    private var filtered: [Proposal] {
        switch filter {
        case .all:      return pending
        case .todo:     return pending.filter { $0.type == .todo }
        case .decision: return pending.filter { $0.type == .decision }
        case .journal:  return pending.filter { $0.type == .journalEntry }
        case .asked:    return pending.filter { $0.question?.isEmpty == false }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                filterChips
                if filtered.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(filtered) { p in
                            ProposalRow(
                                proposal: p,
                                onApprove: { approve(p) },
                                onEdit: { editing = p },
                                onDismiss: { dismissProposal(p) }
                            )
                            if p.id != filtered.last?.id {
                                Hairline().opacity(0.5)
                            }
                        }
                    }
                }
                Spacer().frame(height: 90)
            }
            .padding(.top, 18)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .sheet(item: $editing) { p in
            ProposalEditSheet(proposal: p) {
                editing = nil
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.Palette.paper)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            MicroText(text: "Review · \(pending.count) pending")
            Text("What Atlas wants you to see")
                .font(Theme.Font.serifItalic(38))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(2)
            Text("Approve, edit, or dismiss. Nothing is filed until you say so.")
                .font(Theme.Font.serifItalic(14))
                .foregroundStyle(Theme.Palette.inkFaint)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .padding(.horizontal, 22)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProposalFilter.allCases) { f in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { filter = f }
                    } label: {
                        Text(f.label)
                            .font(Theme.Font.sans(13, weight: filter == f ? .semibold : .regular))
                            .foregroundStyle(filter == f ? .white : Theme.Palette.inkSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(filter == f ? Theme.Palette.ink : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(filter == f ? Theme.Palette.ink : Theme.Palette.hairline, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 18).padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing waiting.")
                .font(Theme.Font.serifItalic(18))
                .foregroundStyle(Theme.Palette.inkSecondary)
            Text("Ayumi will queue proposals here as it notices things in your captures and signals.")
                .font(Theme.Font.serifItalic(14))
                .foregroundStyle(Theme.Palette.inkFaint)
                .lineSpacing(3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func approve(_ p: Proposal) {
        // Materialise the proposal into a real record.
        let chapter = p.chapter
        switch p.type {
        case .todo:
            if let d = decode(p.proposedPayloadJSON), let text = d["text"] as? String {
                let t = Todo(text: text, chapter: chapter)
                t.source = .extracted
                if let due = d["due"] as? String, let date = ISO8601DateFormatter().date(from: due) {
                    t.dueDate = date
                }
                context.insert(t)
            }
        case .decision:
            if let d = decode(p.proposedPayloadJSON), let title = d["title"] as? String {
                let rationale = (d["rationale"] as? String) ?? ""
                context.insert(Decision(title: title, rationale: rationale, decidedAt: Date(), chapter: chapter))
            }
        case .journalEntry:
            if let d = decode(p.proposedPayloadJSON), let content = d["content"] as? String {
                context.insert(Entry(date: Date(), content: content, source: .manual, chapter: chapter))
            }
        case .chapter:
            if let d = decode(p.proposedPayloadJSON),
               let title = d["title"] as? String,
               let typeStr = d["type"] as? String,
               let ctype = ChapterType(rawValue: typeStr) {
                context.insert(Chapter(title: title, type: ctype, purpose: d["purpose"] as? String))
            }
        case .chapterLink:
            // Skip for now — link creation needs both chapter UUIDs.
            break
        }
        p.status = .approved
        p.decidedAt = Date()
        chapter?.touch()
        try? context.save()
    }

    private func dismissProposal(_ p: Proposal) {
        p.status = .dismissed
        p.decidedAt = Date()
        try? context.save()
    }

    private func decode(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Row

struct ProposalRow: View {
    let proposal: Proposal
    let onApprove: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TypeBadge(type: proposal.type)
                VStack(alignment: .leading, spacing: 4) {
                    if let q = proposal.question, !q.isEmpty {
                        Text(proposal.setup ?? "")
                            .font(Theme.Font.serifItalic(15))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineSpacing(3)
                        Text(q)
                            .font(Theme.Font.serifItalic(17))
                            .foregroundStyle(Theme.Palette.ink)
                    } else {
                        Text(proposal.summary ?? proposal.type.rawValue.capitalized)
                            .font(Theme.Font.serif(16))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineSpacing(3)
                    }
                    sourceLine
                }
                Spacer(minLength: 0)
            }
            if let r = proposal.reasoning, !r.isEmpty {
                Text(r)
                    .font(Theme.Font.sans(12.5))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .lineSpacing(2)
            }
            actions
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var sourceLine: some View {
        HStack(spacing: 6) {
            if let s = proposal.sourceLabel, !s.isEmpty {
                Text(s.uppercased())
                    .font(Theme.Font.mono(9))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            if let m = proposal.sourceMeta, !m.isEmpty {
                Text("·")
                    .foregroundStyle(Theme.Palette.inkFainter)
                Text(m)
                    .font(Theme.Font.mono(9))
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            if let ch = proposal.chapter {
                Text("·")
                    .foregroundStyle(Theme.Palette.inkFainter)
                Text(ch.title)
                    .font(Theme.Font.serifItalic(12))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.24)) { onApprove() }
            } label: {
                Text(proposal.question == nil ? "Approve" : "File it")
                    .font(Theme.Font.sans(13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.Palette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            Button {
                onEdit()
            } label: {
                Text("Edit")
                    .font(Theme.Font.serifItalic(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) { onDismiss() }
            } label: {
                Text("Dismiss")
                    .font(Theme.Font.serifItalic(12.5))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TypeBadge: View {
    let type: ProposalType
    var body: some View {
        let (label, color): (String, Color) = {
            switch type {
            case .todo:         return ("T", Theme.Palette.forest)
            case .decision:     return ("D", Theme.Palette.teal)
            case .journalEntry: return ("J", Theme.Palette.inkSecondary)
            case .chapter:      return ("C", Theme.Palette.ember)
            case .chapterLink:  return ("L", Theme.Palette.inkFaint)
            }
        }()
        return Text(label)
            .font(Theme.Font.mono(11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color)
            .clipShape(Circle())
    }
}

// MARK: - Edit sheet — minimal pass-through for text-shaped proposals

struct ProposalEditSheet: View {
    @Environment(\.modelContext) private var context
    let proposal: Proposal
    let onClose: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MicroText(text: "Edit before filing")
                Spacer()
                Button("Close") { onClose() }
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            .padding(.horizontal, 22).padding(.top, 18)
            Text("Adjust the text, then file.")
                .font(Theme.Font.serifItalic(15))
                .foregroundStyle(Theme.Palette.inkFaint)
                .padding(.horizontal, 22).padding(.top, 6)
            TextEditor(text: $draft)
                .focused($focused)
                .font(Theme.Font.serif(17))
                .foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(Theme.Palette.bgSunk)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 160)
                .padding(.horizontal, 22).padding(.top, 14)
            Button {
                save()
                onClose()
            } label: {
                Text("File")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.atlasPrimary)
            .padding(.horizontal, 22).padding(.top, 18)
            Spacer()
        }
        .onAppear {
            draft = initialDraft()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { focused = true }
        }
    }

    private func initialDraft() -> String {
        guard let dict = try? JSONSerialization.jsonObject(with: proposal.proposedPayloadJSON) as? [String: Any] else {
            return ""
        }
        switch proposal.type {
        case .todo:         return (dict["text"] as? String) ?? ""
        case .decision:     return (dict["rationale"] as? String) ?? (dict["title"] as? String) ?? ""
        case .journalEntry: return (dict["content"] as? String) ?? ""
        default:            return ""
        }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let chapter = proposal.chapter
        switch proposal.type {
        case .todo:
            let t = Todo(text: trimmed, chapter: chapter)
            t.source = .extracted
            context.insert(t)
        case .decision:
            context.insert(Decision(title: String(trimmed.prefix(120)), rationale: trimmed, decidedAt: Date(), chapter: chapter))
        case .journalEntry:
            context.insert(Entry(date: Date(), content: trimmed, source: .manual, chapter: chapter))
        default:
            break
        }
        proposal.status = .edited
        proposal.decidedAt = Date()
        proposal.decidedPayloadJSON = try? JSONSerialization.data(withJSONObject: ["text": trimmed])
        chapter?.touch()
        try? context.save()
    }
}
