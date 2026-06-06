import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureSheet.swift — the co-completion "well" sheet (README §"The capture
//  sheet"). Replaces the old standalone-Capture compose sheet.
//
//  Tapping/swiping the cue dims the underlying screen (rgba(13,20,26,0.34))
//  and slides up a 28px-radius sheet (cubic-bezier(.34,1.10,.64,1), ~480ms)
//  containing: a context line, the well, the forming tag, the accept hint,
//  the one-question card, and a controls row (mic · source hint · Capture).
//
//  On capture: items "fly" to the cue, the halo goes thinking → delivered, a
//  "Kept." confirmation shows the filed structure, and the sheet auto-closes
//  after ~1.7s → halo idle → returns to the prior screen.
//
//  Everything binds to `CaptureController` (the scaffold state machine).
// ════════════════════════════════════════════════════════════════════

struct CaptureSheet: View {
    @Bindable var controller: CaptureController
    /// Dismiss back to the host screen (esc / swipe-down / tap-outside).
    var onClose: () -> Void
    /// DEBUG: open straight into the voice duet (for `--capture-voice`).
    var debugAutoVoice: Bool = false

    @FocusState private var fieldFocused: Bool
    @State private var voice = CaptureVoiceSession()
    /// Sheet slide-up progress (0 = off-screen, 1 = seated).
    @State private var presented = false
    /// Vertical drag offset while swiping the sheet down to dismiss.
    @State private var dragOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Dim — fades to rgba(13,20,26,0.34); tap to return.
            Color(hex: 0x0D141A)
                .opacity(presented ? 0.34 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // The sheet, pinned to the bottom.
            VStack {
                Spacer(minLength: 0)
                sheetBody
                    .offset(y: presented ? dragOffset : 900)
                    .animation(reduceMotion ? .easeOut(duration: 0.2)
                                            : .timingCurve(0.34, 1.10, 0.64, 1.0, duration: 0.48),
                               value: presented)
            }
        }
        .onAppear {
            presented = true
            if debugAutoVoice {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { toggleMic() }
            } else if controller.mode == .text {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { fieldFocused = true }
            }
            #if DEBUG
            // `--capture-filed`: lock the ghost, answer the question, land on "Kept."
            if ProcessInfo.processInfo.arguments.contains("--capture-filed") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    controller.commitGhost()
                    Task { _ = await controller.answerQuestion("Send ahead") }
                }
            }
            #endif
        }
    }

    // MARK: - Sheet body

    private var sheetBody: some View {
        VStack(spacing: 0) {
            grabHandle
            contextLine
                .padding(.bottom, 10)

            CaptureWell(
                controller: controller,
                fieldFocused: $fieldFocused,
                voiceRuns: voice.runs,
                isVoice: controller.mode == .voice
            )

            formingTag
            acceptHint

            if let q = controller.question {
                QuestionCard(question: q,
                             onAnswer: { reply in answer(q: q, reply) },
                             onIgnore: { controller.ignoreQuestion() })
                    .padding(.top, 13)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            controlsRow
                .padding(.top, 14)
        }
        .padding(.init(top: 15, leading: 16, bottom: 14, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.Palette.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.Palette.ruleSoft, lineWidth: 1)
        )
        .overlay {
            // "Kept." confirmation overlay — covers the sheet, then auto-closes.
            if let filed = controller.filed {
                FiledConfirmation(state: filed)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow2()
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .gesture(swipeToDismiss)
        .animation(Theme.Motion.overshoot(0.32), value: controller.question)
        .animation(Theme.Motion.standard(0.36), value: controller.filed)
    }

    private var grabHandle: some View {
        Capsule()
            .fill(Theme.Palette.ink4)
            .opacity(0.5)
            .frame(width: 38, height: 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    // ── Context line: "Capturing — over <Screen>" + "esc returns you here" ──
    private var contextLine: some View {
        HStack {
            Text("Capturing — over \(controller.overScreen)".uppercased())
                .font(Theme.Font.mono(9))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.ink3)
            Spacer()
            Text("esc returns you here".uppercased())
                .font(Theme.Font.mono(8.5))
                .tracking(0.9)
                .foregroundStyle(Theme.Palette.ink4)
        }
    }

    // MARK: - Forming tag

    @ViewBuilder
    private var formingTag: some View {
        let showReal = controller.match.map { !$0.generic && (controller.hasGhost || controller.locked) } ?? false
        let showGeneric = controller.match.map { $0.generic && controller.locked } ?? false
        if let match = controller.match, showReal || showGeneric {
            HStack(spacing: 8) {
                Text(controller.locked ? "kept as" : "forming")
                    .font(Theme.Font.mono(8))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(controller.locked ? Color(hex: 0x9FC4B0) : Theme.Palette.tealDeep)
                Text(match.formingLabel)
                    .font(Theme.Font.serifItalic(13))
                    .foregroundStyle(controller.locked ? Color(hex: 0xEAF3EE) : Theme.Palette.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(controller.locked ? AnyShapeStyle(Theme.Palette.forest)
                                            : AnyShapeStyle(Theme.Palette.tealSoft))
                    .overlay(controller.locked ? nil
                             : Capsule().strokeBorder(Theme.Palette.teal.opacity(0.15), lineWidth: 1))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 13)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
            .animation(Theme.Motion.overshootStrong(0.3), value: controller.locked)
        }
    }

    // MARK: - Accept hint

    @ViewBuilder
    private var acceptHint: some View {
        let text: String? = {
            if controller.mode == .text, controller.hasGhost { return "tap the grey completion to accept · keep typing to override" }
            if controller.locked { return "accepted · edit freely, then capture" }
            return nil
        }()
        HStack(spacing: 7) {
            if let text {
                Text(text.uppercased())
                    .font(Theme.Font.mono(8.5))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.ink4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .padding(.top, 13)
        .animation(Theme.Motion.standard(0.2), value: text)
    }

    // MARK: - Controls row (mic · source hint · Capture)

    private var controlsRow: some View {
        HStack(spacing: 10) {
            CaptureMicButton(live: controller.micLive) { toggleMic() }

            if controller.mode == .voice {
                // The behaviour toggle replaces the static source hint while live;
                // the elapsed/listening time shows beneath it.
                VStack(alignment: .leading, spacing: 3) {
                    VoiceBehaviorToggle(controller: controller)
                    Text(voice.sourceHint.uppercased())
                        .font(Theme.Font.mono(8))
                        .tracking(0.8)
                        .foregroundStyle(Theme.Palette.ink4)
                }
            } else {
                Text("type or speak".uppercased())
                    .font(Theme.Font.mono(8.5))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Palette.ink4)
            }

            Spacer(minLength: 0)

            Button { capture() } label: {
                Text("Capture")
                    .font(Theme.Font.serif(16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.Palette.ink))
                    .opacity(controller.canCapture ? 1 : 0.4)
            }
            .buttonStyle(.pressScale)
            .disabled(!controller.canCapture)
        }
    }

    // MARK: - Actions

    private func toggleMic() {
        if controller.mode == .voice {
            controller.stopVoice()
            voice.cancel()
            return
        }
        fieldFocused = false
        controller.toggleMic()
        voice.start(
            controller: controller,
            onForm: { match, question in
                controller.applyVoiceForm(match: match, transcript: voice.transcript)
                if let question { controller.askQuestion(question) }
            },
            onHandsfreeFile: { Task { await fileAndClose() } }
        )
    }

    private func capture() {
        Task {
            let filed = await controller.capturePressed()
            if filed { scheduleAutoClose() }
        }
    }

    private func answer(q: CaptureQuestion, _ answer: String) {
        Task {
            _ = await controller.answerQuestion(answer)
            scheduleAutoClose()
        }
    }

    private func fileAndClose() async {
        _ = await controller.file()
        scheduleAutoClose()
    }

    /// "Kept." shows for ~1.7s, then the sheet slides back and we return.
    private func scheduleAutoClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { dismiss() }
    }

    private func dismiss() {
        fieldFocused = false
        voice.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                                   : .timingCurve(0.34, 1.10, 0.64, 1.0, duration: 0.42)) {
            presented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onClose() }
    }

    // MARK: - Swipe-to-dismiss

    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard v.translation.height > 0 else { return }
                dragOffset = v.translation.height
            }
            .onEnded { v in
                if v.translation.height > 80 {
                    dismiss()
                } else {
                    withAnimation(Theme.Motion.overshoot(0.3)) { dragOffset = 0 }
                }
            }
    }
}

// MARK: - One-question card (README §"A one-question card")

/// Appears only when Ayumi can't complete confidently: Ayumi avatar + "Ayumi
/// asks", an italic question, 2 answer chips, and an `ignore`. Answering files
/// with that answer attached.
struct QuestionCard: View {
    let question: CaptureQuestion
    var onAnswer: (String) -> Void
    var onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AyumiAvatar(size: 16)
                Text("Ayumi asks".uppercased())
                    .font(Theme.Font.mono(8.5))
                    .tracking(1.3)
                    .foregroundStyle(Theme.Palette.ink3)
            }
            .padding(.bottom, 8)

            Text(question.text)
                .font(Theme.Font.serifItalic(16))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(Array(question.answers.enumerated()), id: \.offset) { idx, label in
                    Button { onAnswer(label) } label: {
                        Text(label)
                            .font(Theme.Font.serif(14))
                            .foregroundStyle(idx == 0 ? .white : Theme.Palette.ink2)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(idx == 0 ? AnyShapeStyle(Theme.Palette.ink) : AnyShapeStyle(Color.clear))
                                    .overlay(idx == 0 ? nil : Capsule().strokeBorder(Theme.Palette.rule, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.pressScale)
                }
                Spacer(minLength: 0)
                Button { onIgnore() } label: {
                    Text("ignore".uppercased())
                        .font(Theme.Font.mono(9))
                        .tracking(1.0)
                        .foregroundStyle(Theme.Palette.ink4)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(.init(top: 13, leading: 14, bottom: 13, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.paper))
        .shadow1()
    }
}

// MARK: - Filed confirmation ("Kept.")

/// The terminal "Kept." overlay showing the filed structure (README §"A filed
/// state"). Covers the sheet face while the halo blooms; the sheet auto-closes.
struct FiledConfirmation: View {
    let state: CaptureController.FiledState

    var body: some View {
        VStack(spacing: 10) {
            Text(state.headline)
                .font(Theme.Font.serifItalic(34))
                .foregroundStyle(Theme.Palette.ink)
            Text(state.sub)
                .font(Theme.Font.serifItalic(15))
                .foregroundStyle(Theme.Palette.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(Array(state.tags.enumerated()), id: \.offset) { _, tag in
                    Text(tag.uppercased())
                        .font(Theme.Font.mono(8.5))
                        .tracking(1.0)
                        .foregroundStyle(Theme.Palette.forest)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.forestSoft))
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.paper)
        .transition(.opacity)
    }
}
