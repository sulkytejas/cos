import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  Ayumi v0.6 design tokens — the exact values from the design handoff
//  (designs temp/_unzipped/design_handoff_ayumi/README.md "Design Tokens").
//
//  Added as an additive layer on top of the existing Theme so the legacy
//  v0.3 screens keep compiling. New shell/screen code reads these tokens by
//  their real names (teal == teal, not the legacy `ColorEmber` alias).
// ════════════════════════════════════════════════════════════════════

extension Color {
    /// 0xRRGGBB literal → sRGB Color.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Theme.Palette {
    // ── Surfaces / ink (additive aliases to the correctly-valued tokens) ──
    static let paperDeep = Color(hex: 0xF7F7F5)   // --paper-deep (sunk wells, inputs)
    static let desk = Color(hex: 0xEDEDEA)        // --desk ("the room around the phone" — the rim behind the page card; the Halo tints it warm in renders)
    static let ink2 = Color(hex: 0x2C3942)        // --ink-2
    static let ink3 = Color(hex: 0x6A7480)        // --ink-3 (mono meta)
    static let ink4 = Color(hex: 0xAAB2BB)        // --ink-4 (faint, hairline dots)

    // ── Hairlines (exact: base rgb 40,44,52) ──
    static let rule = Color(hex: 0x282C34, opacity: 0.10)       // --rule
    static let ruleSoft = Color(hex: 0x282C34, opacity: 0.05)   // --rule-soft

    // ── Accents the legacy palette lacks or mis-maps ──
    static let jade = Color(hex: 0x5A8F74)   // --jade (thinking UI dots)
    static let warn = Color(hex: 0xB8431E)   // --ember (low-confidence / warning); note Palette.ember is hijacked to teal
    static let pulseTeal = Color(hex: 0x7AD6C6)  // EO ring / thinking pulse (rgb 122,214,198)

    // ── Confidence pills (Brief predictions) ──
    static let confHighBg  = Color(hex: 0xD9E7D8)
    static let confHighInk = Color(hex: 0x16321E)
    static let confLowBg   = Color(hex: 0xFBE3D9)
    static let confLowInk  = Color(hex: 0x6C2310)

    // ── Card materials ──
    static let jadeCardTop = Color(hex: 0xDCEAE0)
    static let jadeCardBot = Color(hex: 0xCFE2D6)
    static let jadeCardInk = Color(hex: 0x16321E)
    static let obsidianTop = Color(hex: 0x14181C)
    static let obsidianBot = Color(hex: 0x0C1218)
    static let obsidianInk = Color(hex: 0xF2F7FB)
    static let avatarInk   = Color(hex: 0xFFFCEB)

    static let jadeCard = LinearGradient(colors: [jadeCardTop, jadeCardBot], startPoint: .top, endPoint: .bottom)
    static let obsidian = LinearGradient(colors: [obsidianTop, obsidianBot], startPoint: .top, endPoint: .bottom)
}

extension Theme {
    /// Shell geometry.
    enum Layout {
        static let haloInset: CGFloat = 22    // rim width (--halo-inset)
        static let pageRadius: CGFloat = 32   // page-surface inner corner (--halo-radius)
        static let screenPad: CGFloat = 22    // horizontal screen padding
    }

    /// Motion — the handoff's cubic-beziers, as SwiftUI timing curves.
    enum Motion {
        /// cubic-bezier(.34,1.12,.64,1) — sheet slides / morphs (overshoot).
        static func overshoot(_ d: Double = 0.42) -> Animation { .timingCurve(0.34, 1.12, 0.64, 1.0, duration: d) }
        /// cubic-bezier(.34,1.16,.64,1) — card morph / receipt slide (stronger).
        static func overshootStrong(_ d: Double = 0.60) -> Animation { .timingCurve(0.34, 1.16, 0.64, 1.0, duration: d) }
        /// cubic-bezier(.4,0,.2,1) — standard fades.
        static func standard(_ d: Double = 0.30) -> Animation { .timingCurve(0.4, 0, 0.2, 1.0, duration: d) }
        /// cubic-bezier(.2,.7,.2,1) — EO ring expand.
        static func eoRing(_ d: Double = 0.95) -> Animation { .timingCurve(0.2, 0.7, 0.2, 1.0, duration: d) }
    }
}

extension Theme.Radii {
    static let card: CGFloat = 13
    static let pill: CGFloat = 999
    static let sheetTop: CGFloat = 32
    static let sheetBottom: CGFloat = 22
    static let receiptTop: CGFloat = 28
}

extension View {
    /// --shadow-1 (cards). Cool-neutral, never warm. SwiftUI has no negative
    /// spread, so each CSS layer `x y blur s` maps to radius = blur/2 + s/2
    /// (the inset shape blurs to a visibly tighter halo) with alpha scaled by
    /// ~(1 + s/(2·blur)) for the light lost to the inset. Raw blur/2 with the
    /// spread ignored read far too wide/heavy under chips and buttons.
    /// CSS: 0 0.5 1/.04, 2 4 10 -4/.06, 4 12 28 -14/.10
    func shadow1() -> some View {
        let c = Color(hex: 0x141820)   // rgb 20,24,32
        return self
            .shadow(color: c.opacity(0.04), radius: 0.5, x: 0, y: 0.5)
            .shadow(color: c.opacity(0.05), radius: 3,   x: 2, y: 4)
            .shadow(color: c.opacity(0.07), radius: 7,   x: 4, y: 12)
    }
    /// --shadow-2 (lifted / dark surfaces).
    /// CSS: 0 1 1/.05, 3 6 14 -4/.09, 6 16 32 -10/.14 — same spread mapping.
    func shadow2() -> some View {
        let c = Color(hex: 0x141820)
        return self
            .shadow(color: c.opacity(0.05), radius: 0.5, x: 0, y: 1)
            .shadow(color: c.opacity(0.08), radius: 5,   x: 3, y: 6)
            .shadow(color: c.opacity(0.12), radius: 11,  x: 6, y: 16)
    }
}
