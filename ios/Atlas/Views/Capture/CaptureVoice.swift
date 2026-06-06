import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureVoice.swift — the voice duet (README §"Voice duet").
//
//  Tapping the mic switches the well to voice: the mic pulses `--forest`, the
//  PenLine ink stroke is drawn along the base of the well (in CaptureWell),
//  and a transcript streams in. Ayumi can interject inline in teal ("how
//  tight?", "logged"). When the user stops, Ayumi forms the structure and may
//  ask the one question. A toggle exposes the behaviour choice:
//  Settle-to-text (transcript becomes editable, user taps Send) vs Hands-free
//  (auto-sends on stop). Forest = your ink, teal = Ayumi's ink.
//
//  Scripted against the seed for now (real = speech-to-text). This object owns
//  ONLY the voice script + the streamed runs; it drives the shared
//  `CaptureController` (forms the match + asks the question) so the duet shares
//  the same brain as typing.
// ════════════════════════════════════════════════════════════════════

/// Drives the scripted voice duet. Observable so the sheet re-renders as runs
/// stream in and the source-hint timer ticks. Mirrors the proto's `mic` click
/// handler: three transcript beats, then Ayumi forms the structure + asks.
@MainActor
@Observable
final class CaptureVoiceSession {
    /// The streamed transcript runs (forest you-ink + teal Ayumi-ink).
    private(set) var runs: [CaptureVoiceRun] = []
    /// The source hint shown in the controls row ("0:24 · paused").
    private(set) var sourceHint = "type or speak"
    /// True once Ayumi has finished forming + (in Settle) is waiting for Send.
    private(set) var settled = false

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// Start the scripted duet over `controller`. On the final beat Ayumi forms a
    /// `note · Stratyfix · journal` match and asks the one runway question
    /// (Settle), or files hands-free.
    func start(controller: CaptureController,
               onForm: @escaping (CaptureMatch, CaptureQuestion?) -> Void,
               onHandsfreeFile: @escaping () -> Void) {
        cancel()
        runs = []
        settled = false
        sourceHint = "0:00 · listening"

        // The scripted transcript, ported from atlas-capture.js `seq`.
        schedule(after: 0.30) {
            self.runs = [.init(text: "I’m worried the runway math is", kind: .you)]
        }
        schedule(after: 1.30) {
            self.runs = [
                .init(text: "I’m worried the runway math is tighter than we’re saying", kind: .you),
                .init(text: "how tight?", kind: .ayumi),
            ]
        }
        schedule(after: 2.60) {
            self.runs = [
                .init(text: "I’m worried the runway math is tighter than we’re saying — maybe nine months, not twelve", kind: .you),
                .init(text: "logged", kind: .ayumi),
            ]
        }
        // Ayumi forms the structure, then either asks (Settle) or files (Hands-free).
        schedule(after: 3.80) {
            let match = CaptureMatch(kind: .note, chapterId: "stratyfix", tag: "Stratyfix · journal")
            self.sourceHint = "0:24 · paused"
            self.settled = true
            switch controller.voiceBehavior {
            case .settle:
                onForm(match, CaptureQuestion(
                    text: "Want the real runway number worked out and put in the brief?",
                    answers: ["Yes, add it", "Not now"]))
            case .handsfree:
                onForm(match, nil)
                onHandsfreeFile()
            }
        }
    }

    /// The committed transcript text (your ink only), for the controller to file.
    /// Joins EVERY you-run, not just the last: the current script re-sends the
    /// full cumulative string per beat, but a real STT that streams incremental
    /// you-runs would otherwise file only the final fragment.
    var transcript: String {
        runs.filter { $0.kind == .you }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func schedule(after seconds: Double, _ body: @escaping () -> Void) {
        let t = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            body()
        }
        tasks.append(t)
    }
}

// MARK: - Voice behaviour toggle (Settle ↔ Hands-free)

/// The small segmented toggle exposing the voice behaviour choice (README
/// §"Voice duet"). Forest = your ink (Settle, you finish in text); teal accents
/// the active segment. Lives in the controls row only while in voice mode.
struct VoiceBehaviorToggle: View {
    @Bindable var controller: CaptureController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VoiceBehavior.allCases) { behavior in
                let active = controller.voiceBehavior == behavior
                Button {
                    withAnimation(Theme.Motion.standard(0.22)) {
                        controller.setVoiceBehavior(behavior)
                    }
                } label: {
                    Text(behavior.label)
                        .font(Theme.Font.mono(8.5, weight: active ? .medium : .regular))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(active ? .white : Theme.Palette.ink3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(active ? Theme.Palette.forest : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Theme.Palette.paperDeep)
                .overlay(Capsule().strokeBorder(Theme.Palette.rule, lineWidth: 1))
        )
    }
}

// MARK: - Mic toggle button

/// The mic toggle on the left of the controls row. Idle = paper-deep inset;
/// live = pulsing `--forest` (CSS `.ac-mic.live` `@keyframes ac-mic`).
struct CaptureMicButton: View {
    var live: Bool
    var action: () -> Void

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(live ? AnyShapeStyle(Theme.Palette.forest)
                               : AnyShapeStyle(Theme.Palette.paperDeep))
                    .overlay(
                        live ? nil
                             : Circle().strokeBorder(Theme.Palette.rule, lineWidth: 1)
                    )
                    .frame(width: 42, height: 42)
                // Pulsing ring while live.
                if live {
                    Circle()
                        .stroke(Theme.Palette.forest.opacity(0.26), lineWidth: 2)
                        .frame(width: 42, height: 42)
                        .scaleEffect(pulse ? 1.42 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                MicGlyph(tint: live ? Color.white : Theme.Palette.ink2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(live ? "Stop voice" : "Speak")
        .onChange(of: live) { _, isLive in
            guard !reduceMotion else { return }
            if isLive {
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }

}

// MARK: - Mic glyph

/// The mic glyph — ported pixel-for-pixel from the proto SVG (an 18×18 viewBox).
/// Drawn in one `Canvas` so the capsule, listening arc, and stem share a single
/// coordinate space and stay concentric (separate SwiftUI shapes get centred by
/// their own bounding boxes, which pulls them apart). Proto paths, untranslated:
///   rect  x6.6 y2.2 w4.8 h9.2 rx2.4  — the capsule mic body
///   arc   M3.6 8.6 C3.6 12.4 6 14.4 9 14.4 C12 14.4 14.4 12.4 14.4 8.6  — listening arc
///   line  x9 y14.4→16.4  — the stem hanging off the arc's base
private struct MicGlyph: View {
    var tint: Color

    var body: some View {
        Canvas { ctx, _ in
            let shade = GraphicsContext.Shading.color(tint)

            // Capsule mic body.
            let body = Path(roundedRect: CGRect(x: 6.6, y: 2.2, width: 4.8, height: 9.2),
                            cornerRadius: 2.4)
            ctx.fill(body, with: shade)

            // Listening arc.
            var arc = Path()
            arc.move(to: CGPoint(x: 3.6, y: 8.6))
            arc.addCurve(to: CGPoint(x: 9, y: 14.4),
                         control1: CGPoint(x: 3.6, y: 12.4),
                         control2: CGPoint(x: 6, y: 14.4))
            arc.addCurve(to: CGPoint(x: 14.4, y: 8.6),
                         control1: CGPoint(x: 12, y: 14.4),
                         control2: CGPoint(x: 14.4, y: 12.4))
            ctx.stroke(arc, with: shade, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

            // Stem.
            var stem = Path()
            stem.move(to: CGPoint(x: 9, y: 14.4))
            stem.addLine(to: CGPoint(x: 9, y: 16.4))
            ctx.stroke(stem, with: shade, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        .frame(width: 18, height: 18)
    }
}
