import SwiftUI

/// Minimal settings for the v0.6 shell — set the API key on-device (so the app
/// works off the simulator), tune the daily token budget, and see what's
/// connected. Presented from the logo-menu index sheet.
struct AyumiSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = UserDefaults.standard.string(forKey: "AnthropicAPIKey") ?? ""
    @State private var capText = String(LLMBudget.dailyCap)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Settings").font(Theme.Font.serifItalic(30)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button { dismiss() } label: {
                    Text("DONE").font(Theme.Font.mono(10)).tracking(1.2).foregroundStyle(Theme.Palette.tealDeep)
                }.buttonStyle(.plain)
            }
            .padding(.top, 8)

            field("Claude (Anthropic) API key") {
                SecureField("sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: key) { _, v in
                        UserDefaults.standard.set(v.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "AnthropicAPIKey")
                        AtlasLLM.resetBreaker()   // a fresh key clears any prior account error
                    }
            }
            Text("The agent runs on Claude. The key stays on this device.")
                .font(Theme.Font.sans(12)).foregroundStyle(Theme.Palette.ink3)

            field("Daily token budget") {
                TextField("300000", text: $capText)
                    .keyboardType(.numberPad)
                    .onChange(of: capText) { _, v in
                        if let n = Int(v.filter(\.isNumber)), n > 0 {
                            UserDefaults.standard.set(n, forKey: "AtlasDailyTokenCap")
                        }
                    }
            }
            Text("Spent today: \(LLMBudget.spentToday.formatted()) / \(LLMBudget.dailyCap.formatted()) tokens")
                .font(Theme.Font.mono(10)).foregroundStyle(Theme.Palette.ink3)

            HStack {
                Text("CALENDAR").font(Theme.Font.mono(9)).tracking(1.4).foregroundStyle(Theme.Palette.ink3)
                Spacer()
                Text(EventKitCalendarSource.isAuthorized ? "CONNECTED" : "NOT CONNECTED")
                    .font(Theme.Font.mono(9)).tracking(1.0)
                    .foregroundStyle(EventKitCalendarSource.isAuthorized ? Theme.Palette.forest : Theme.Palette.ink4)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.paper.ignoresSafeArea())
    }

    @ViewBuilder private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Font.mono(9)).tracking(1.4).foregroundStyle(Theme.Palette.ink3)
            content()
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Palette.paperDeep)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.Palette.rule, lineWidth: 1))
                )
        }
    }
}
