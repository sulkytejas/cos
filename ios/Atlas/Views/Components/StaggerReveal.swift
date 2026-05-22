import SwiftUI

/// Cascading reveal — each child fades + drifts up over 480ms with `index * step`
/// delay. Apply to a child by wrapping its body and passing its position.
struct StaggerReveal: ViewModifier {
    let index: Int
    var step: Double = 0.07          // 70ms per item
    var duration: Double = 0.48

    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .onAppear {
                guard !visible else { return }
                withAnimation(.easeOut(duration: duration).delay(Double(index) * step)) {
                    visible = true
                }
            }
    }
}

extension View {
    /// Convenience: `.staggerReveal(index: i)`
    func staggerReveal(index: Int, step: Double = 0.07) -> some View {
        modifier(StaggerReveal(index: index, step: step))
    }
}
