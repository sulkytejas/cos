import SwiftUI

/// Standalone harness to verify the Halo's three states in isolation — the
/// SwiftUI equivalent of the on-screen state toggle in the design prototype.
///
/// NOTE: currently in DIAGNOSTIC mode — the page mask is removed (so the whole
/// Halo canvas is visible), a teal rim is drawn every frame (HaloController
/// `debugRim`), and a HUD shows render/advance counts. Once rendering is
/// confirmed, this reverts to the masked 22pt-rim presentation.
struct HaloDemoView: View {
    @State private var halo = HaloController()

    private let states: [(HaloController.HaloState, String)] = [
        (.idle, "idle"), (.thinking, "thinking"), (.delivered, "delivered"),
    ]

    var body: some View {
        ZStack {
            // Paper white behind everything.
            Color.white

            // The Halo, full-bleed. (Page mask removed for diagnosis.)
            HaloView(controller: halo)

            VStack(spacing: 0) {
                hud
                Spacer()
                stateToggle
            }
            .padding(.top, 60)
            .padding(.horizontal, 28)
            .padding(.bottom, 44)
        }
        .ignoresSafeArea()
        .task {
            // TEMP: lets a screenshot harness boot straight into a state, e.g.
            //   simctl launch booted com.atlas.app --halo-state thinking
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--halo-state"), i + 1 < args.count {
                switch args[i + 1] {
                case "thinking":  halo.setState(.thinking)
                case "delivered": halo.setState(.delivered)
                default:          break
                }
            }
        }
    }

    /// Refreshes ~4×/sec (its own clock) so we can watch the engine's counters
    /// move even though they're un-observed.
    private var hud: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            Text(halo.debugLine)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.black)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var stateToggle: some View {
        HStack(spacing: 4) {
            ForEach(states, id: \.0) { state, label in
                let active = halo.stateName == state
                Button { halo.setState(state) } label: {
                    Text(label.uppercased())
                        .font(Theme.Font.mono(10, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(active ? Color.white : Theme.Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(active ? Theme.Palette.ink : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color(.sRGB, red: 70/255, green: 50/255, blue: 28/255, opacity: 0.05))
        )
        .animation(.easeInOut(duration: 0.2), value: halo.stateName)
    }
}

#Preview {
    HaloDemoView()
}
