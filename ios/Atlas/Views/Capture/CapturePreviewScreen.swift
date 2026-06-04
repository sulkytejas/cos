import SwiftUI

#if DEBUG
// ════════════════════════════════════════════════════════════════════
//  CapturePreviewScreen.swift — DEBUG-only verification host for the Capture
//  system (the `--capture` launch arg). Mounts CaptureHost over a faithful
//  stand-in base (the Chapters list the proto captures "over") inside the
//  real Halo + page-surface shell, so a screenshot lands exactly on the well.
//
//  This exists ONLY to verify Capture in isolation before the integration
//  phase mounts the cue globally. It does not touch the live shell/nav/Today.
// ════════════════════════════════════════════════════════════════════

struct CapturePreviewScreen: View {
    @State private var halo = HaloController(rimInset: 11)

    var body: some View {
        ZStack {
            Theme.Palette.paperDeep.ignoresSafeArea()
            HaloView(controller: halo).ignoresSafeArea()

            CaptureHost(content: { base }, screenName: "Chapters", halo: halo,
                        avoidBottomInset: ProcessInfo.processInfo.arguments.contains("--capture-bottombar") ? 64 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous))
                .padding(Theme.Layout.haloInset)
                .shadow1()
        }
        .environment(halo)
    }

    // The base the proto captures over: "Five threads open." (a Chapters list).
    private var base: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink2)
                    Text("Today")
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Palette.ink2)
                }
                Spacer()
                HStack(spacing: 7) {
                    Text("A").font(Theme.Font.serifItalic(19)).foregroundStyle(Theme.Palette.ink)
                    Text("CHAPTERS")
                        .font(Theme.Font.mono(9)).tracking(1.6)
                        .foregroundStyle(Theme.Palette.ink3)
                }
            }
            .padding(.top, 30)

            Text("Five ").font(Theme.Font.serif(22)).foregroundStyle(Theme.Palette.ink)
                + Text("threads").font(Theme.Font.serifItalic(22)).foregroundStyle(Theme.Palette.ink)
                + Text(" open.").font(Theme.Font.serif(22)).foregroundStyle(Theme.Palette.ink)

            VStack(spacing: 0) {
                threadRow("Stratyfix seed round", "close $1.5M · 6 open")
                threadRow("Ireland MBA relocation", "Trinity over UCD · decided")
                threadRow("Varanasi + Parvati", "reset trip · 3 todos")
                threadRow("Health baseline", "recurring")
                threadRow("Portrait sitting — V.", "Thursday · time moved")
            }
            .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Theme.Layout.screenPad)
        .padding(.top, 6)
    }

    private func threadRow(_ title: String, _ meta: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Font.serifItalic(18))
                .foregroundStyle(Theme.Palette.ink)
            Text(meta)
                .font(Theme.Font.mono(9))
                .tracking(0.5)
                .foregroundStyle(Theme.Palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1)
        }
    }
}
#endif
