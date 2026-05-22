import SwiftUI

/// Reports a ScrollView's vertical top offset so the parent can implement
/// pull-to-action gestures. Positive value = overscroll downward (pulled).
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Place this view at the very top of a ScrollView's content. It emits
/// the current top-y in the named coordinate space as a ScrollOffsetKey.
struct ScrollOffsetReader: View {
    let coordinateSpace: String
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollOffsetKey.self,
                    value: geo.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
}
