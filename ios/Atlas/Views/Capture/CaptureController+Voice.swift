import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureController+Voice.swift — view-layer affordances over the scaffold
//  controller, owned by Views/Capture/.
//
//  The CaptureController state machine (Agent/Capture/CaptureTypes.swift) is
//  the source of truth; these are thin, UI-facing actions the sheet needs:
//  applying the voice-formed structure, switching the behaviour toggle, and a
//  DEBUG auto-open used by the `--capture` launch arg.
// ════════════════════════════════════════════════════════════════════

extension CaptureController {

    /// Apply the structure Ayumi forms at the end of the voice duet: the match
    /// becomes the forming tag and the spoken transcript becomes the draft so
    /// filing carries the user's words (README §"Voice duet").
    func applyVoiceForm(match: CaptureMatch, transcript: String) {
        setMatch(match)
        setDraft(transcript)
    }

    /// Switch the voice behaviour (Settle ↔ Hands-free) from the toggle.
    func setVoiceBehavior(_ behavior: VoiceBehavior) {
        voiceBehavior = behavior
    }
}
