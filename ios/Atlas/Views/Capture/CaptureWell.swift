import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureWell.swift — the "well" + the co-completion subview.
//
//  The well is the `--paper-deep` rounded field where the fragment appears
//  in Instrument Serif 18px (README §"The well"). As the user types, Ayumi's
//  ghost completion renders inline in `--ink-4` italic; Tab / tapping the
//  ghost commits it to solid ink and locks the forming tag; backspacing past
//  a match clears it (README §"Co-completion model").
//
//  In voice mode the field shows the streaming transcript (forest = your ink,
//  teal = Ayumi's interjections) and the PenLine ink stroke is drawn along the
//  base of the well. Both modes share this one field, exactly as the proto's
//  `#field` is reused for typing + the scripted voice transcript.
//
//  Everything binds to `CaptureController` (the scaffold state machine).
// ════════════════════════════════════════════════════════════════════

struct CaptureWell: View {
    @Bindable var controller: CaptureController
    /// A hidden text field is the keyboard surface for text mode; this binding
    /// mirrors `controller.draft` and drives `onType`.
    @FocusState.Binding var fieldFocused: Bool
    /// The live transcript runs for voice mode (forest user ink + teal Ayumi ink).
    var voiceRuns: [CaptureVoiceRun]
    /// Whether the well is in voice mode (shows PenLine, hides the keyboard field).
    var isVoice: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Field content — either the typed draft+ghost or the voice transcript.
            Group {
                if isVoice {
                    voiceField
                } else {
                    textField
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)

            // The invisible keyboard surface for text mode. It carries the real
            // editable text; the visible field above is a styled render of it so
            // the ghost can sit inline. (TextEditor can't interleave runs.)
            if !isVoice {
                CaptureKeyboardField(
                    text: Binding(
                        get: { controller.draft },
                        set: { newValue in
                            Task { await controller.onType(newValue) }
                        }
                    ),
                    focused: $fieldFocused,
                    onCommitGhost: { controller.commitGhost() }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 120)       // a bounded editable surface (no scroll-grow)
                .opacity(0.02)            // present for input, visually deferred to the render
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(.init(top: 15, leading: 15, bottom: 14, trailing: 15))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Palette.paperDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottom) {
            // PenLine — the animated fountain-pen ink stroke, only in voice.
            if isVoice {
                PenLineView(reduceMotion: reduceMotion)
                    .frame(height: 46)
                    .allowsHitTesting(false)
            }
        }
        .animation(Theme.Motion.standard(0.36), value: isVoice)
    }

    // MARK: - Text field (draft + inline ghost)

    @ViewBuilder
    private var textField: some View {
        if controller.draft.isEmpty && controller.ghost.isEmpty {
            // Italic ink-3 placeholder (README §"The well").
            (Text("Begin anywhere — a word is enough.")
                .font(Theme.Font.serifItalic(18))
                .foregroundColor(Theme.Palette.ink3))
                .lineSpacing(5)
        } else {
            // Solid ink draft + (if not locked) the italic ink-4 ghost remainder.
            // Tapping the ghost commits it (the iOS-native accept, no keyboard).
            ghostComposite
                .onTapGesture { controller.commitGhost() }
        }
    }

    /// The composed `draft` (ink) + `ghost` (ink-4 italic) as one wrapping Text.
    private var ghostComposite: some View {
        var s = AttributedString(controller.draft)
        s.font = .custom(Theme.Typeface.serifRegular, size: 18)
        s.foregroundColor = Theme.Palette.ink

        if controller.hasGhost {
            var g = AttributedString(controller.ghost)
            g.font = .custom(Theme.Typeface.serifItalic, size: 18)
            g.foregroundColor = Theme.Palette.ink4
            s += g
        }
        return Text(s)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Voice field (streaming transcript)

    @ViewBuilder
    private var voiceField: some View {
        if voiceRuns.isEmpty {
            (Text("listening…")
                .font(Theme.Font.serifItalic(18))
                .foregroundColor(Theme.Palette.ink3))
        } else {
            voiceComposite
        }
    }

    /// Forest = your ink, teal = Ayumi's interjections (prefixed with an em-dash,
    /// matching `.field .int::before { content:'— ' }`).
    private var voiceComposite: some View {
        var out = AttributedString()
        for run in voiceRuns {
            var a = AttributedString(run.kind == .ayumi ? "— \(run.text) " : run.text)
            a.font = .custom(Theme.Typeface.serifRegular, size: 18)
            switch run.kind {
            case .you: a.foregroundColor = Theme.Palette.ink     // your ink reads as primary
            case .ayumi: a.foregroundColor = Theme.Palette.tealDeep
            }
            out += a
        }
        return Text(out)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Voice transcript run

/// One run of the voice transcript: your ink (forest) or Ayumi's interjection (teal).
struct CaptureVoiceRun: Identifiable, Hashable {
    enum Kind { case you, ayumi }
    let id = UUID()
    var text: String
    var kind: Kind
}

// MARK: - PenLine (animated fountain-pen ink stroke)

/// The PenLine — an animated fountain-pen ink stroke drawn along the base of
/// the well in voice mode (README §"Voice duet"; ports the canvas RAF loop in
/// `atlas-capture.js startPen`). A forest stroke (your ink) swells with the
/// speech envelope; a teal stroke (Ayumi's ink) flares during interjections.
/// Honours Reduce Motion by drawing a static settled stroke.
struct PenLineView: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                draw(&ctx, size: size, time: now)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let W = size.width, H = size.height
        guard W > 1 else { return }

        if reduceMotion {
            // A calm settled forest stroke — no roaming.
            strokeLine(&ctx, W: W, y: H * 0.40, a: 0.5, rgb: (13, 51, 36))
            return
        }

        // Speech envelope (forest) + interjection envelope (teal), ported from
        // the JS `env` / `tg` math so the stroke breathes like the proto.
        let s = time
        let env = max(0, min(1, max(0, sin(s * 3.1) * 0.6 + sin(s * 7.7) * 0.3)
                                 * (0.4 + 0.6 * (sin(s * 0.45) * 0.5 + 0.5))))
        let c = s.truncatingRemainder(dividingBy: 5)
        let tg = (c > 3.6 && c < 4.4) ? sin((c - 3.6) / 0.8 * .pi) : 0

        strokeLine(&ctx, W: W, y: H * 0.40, a: env * (1 - tg * 0.6), rgb: (13, 51, 36))
        if tg > 0.02 {
            strokeLine(&ctx, W: W, y: H * 0.66, a: tg, rgb: (0, 137, 168))
        }
    }

    /// One ink stroke: three stacked round-cap passes tapering inward, with the
    /// length + opacity + width keyed off the amplitude `a` (JS `drawLine`).
    private func strokeLine(_ ctx: inout GraphicsContext, W: CGFloat, y: CGFloat,
                            a: Double, rgb: (Double, Double, Double)) {
        let amp = max(0, min(1, a))
        let minL = W * 0.46, maxL = W * 0.84
        let len = minL + (maxL - minL) * amp
        let x1 = (W - len) / 2, x2 = x1 + len
        let op = 0.10 + 0.64 * amp
        let color = Color(.sRGB, red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, opacity: op)

        for (wm, inset) in [(1.0, 0.0), (0.66, 0.4), (0.34, 0.85)] {
            let ix = (x2 - x1) * inset * 0.5
            var path = Path()
            path.move(to: CGPoint(x: x1 + ix, y: y))
            path.addLine(to: CGPoint(x: x2 - ix, y: y))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: (0.85 + 1.05 * amp) * wm, lineCap: .round))
        }
    }
}

// MARK: - Keyboard field (UIKit bridge for inline ghost + Tab/return)

/// A thin `UITextView` bridge that supplies the keyboard for text mode. The
/// visible field above renders the styled draft+ghost; this view owns the real
/// editable string + a hardware-`Tab` key command that commits the ghost (the
/// `Tab ↹ accept` affordance for users on an external keyboard). On touch, the
/// ghost is committed by tapping it (handled in `CaptureWell`).
struct CaptureKeyboardField: UIViewRepresentable {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onCommitGhost: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textColor = .clear                // invisible; the SwiftUI render shows text
        tv.tintColor = UIColor(Theme.Palette.ink)   // a real caret
        tv.font = UIFont(name: Theme.Typeface.serifRegular, size: 18) ?? .systemFont(ofSize: 18)
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.delegate = context.coordinator
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        if focused.wrappedValue, !tv.isFirstResponder {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CaptureKeyboardField
        init(_ parent: CaptureKeyboardField) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }

        // Hardware Tab → commit the ghost (the `tab ↹ accept` hint).
        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\t" {
                parent.onCommitGhost()
                return false
            }
            return true
        }
    }
}
