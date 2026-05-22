import SwiftUI

/// Reveals a string character-by-character, then fires onDone.
/// Italicises any phrase in `italic` (using teal serif italic).
struct Typewriter: View {
    let text: String
    var speed: Double = 0.011 // seconds per char
    var startDelay: Double = 0.1
    var italic: [String] = []
    var onDone: () -> Void = {}

    @State private var revealed: Int = 0
    @State private var didFire = false

    var body: some View {
        Text(attributed(prefix: text.prefix(revealed)))
            .lineSpacing(4)
            .onAppear { start() }
            .onChange(of: text) { _, _ in restart() }
    }

    private func start() {
        guard revealed == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            tick()
        }
    }

    private func restart() {
        revealed = 0
        didFire = false
        start()
    }

    private func tick() {
        if revealed >= text.count {
            if !didFire { didFire = true; onDone() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + speed) {
            revealed += 1
            tick()
        }
    }

    private func attributed(prefix: Substring) -> AttributedString {
        var s = AttributedString(String(prefix))
        s.font = Theme.Font.serif(21)
        s.foregroundColor = Theme.Palette.ink
        for phrase in italic {
            if let range = s.range(of: phrase) {
                s[range].font = Theme.Font.serifItalic(22)
                s[range].foregroundColor = Theme.Palette.teal
            }
        }
        return s
    }
}
