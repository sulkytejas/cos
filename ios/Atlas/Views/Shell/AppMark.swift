import SwiftUI

/// The top-left brand mark + logo-menu trigger: serif-italic "A", a mono crumb,
/// and (on Today only) a teal date crumb. Tap → opens the index sheet.
///
/// The brand is "ATLAS". Per the design's in-page `.app-mark` markup the mark is
/// glyph + crumb + (Today only) the `.when` date — "A  Atlas · Today ▾  May 20".
/// Every other screen drops the prefix and the date, reading just "A  <SCREEN> ▾"
/// (e.g. "A  CHAPTERS ▾"). Today is signalled by a non-empty `date` crumb.
///
/// There is deliberately NO trailing teal dot: the breathing teal `.dot` lives
/// exclusively in the outer `.page-meta` desktop chrome ("Atlas v0.6 · Halo · …"),
/// which is hidden in frameless/app mode and is a separate element from the
/// in-page topbar app-mark.
struct AppMark: View {
    let screen: String
    var date: String = ""
    /// Compact topbar variant: the back-affordance screens (Chapters, Review)
    /// render the mark trailing-aligned in the shared `.topbar` row at a slightly
    /// smaller scale — CSS `.app-mark .glyph{font-size:19px}` / `.crumb{font-size:9px}`
    /// versus Today's standalone `22px / 9.5px`.
    var compact: Bool = false
    let onTap: () -> Void

    /// Today is the only screen that carries a date crumb; it alone shows the
    /// "ATLAS · " brand prefix + the trailing date.
    private var isToday: Bool { !date.isEmpty }

    private var glyphSize: CGFloat { compact ? 19 : 22 }
    private var crumbSize: CGFloat { compact ? 9 : 9.5 }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: compact ? 7 : 8) {
                Text("A")
                    .font(Theme.Font.serifItalic(glyphSize))
                    .foregroundStyle(Theme.Palette.ink)
                    .tracking(-0.44)

                Text(isToday ? "ATLAS · \(screen.uppercased()) ▾" : "\(screen.uppercased()) ▾")
                    .font(Theme.Font.mono(crumbSize))
                    .tracking(1.5)
                    .foregroundStyle(Theme.Palette.ink3)

                if isToday {
                    // `.app-mark .when`: mono 9.5, --teal-deep, letter-spacing 0.04em,
                    // margin-left 6px. (No trailing dot — see type doc.)
                    Text(date)
                        .font(Theme.Font.mono(9.5))
                        .tracking(0.38)
                        .foregroundStyle(Theme.Palette.tealDeep)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The shared back affordance for the topbar's leading slot, matching CSS
/// `.back { display:inline-flex; align-items:center; gap:6px; color:var(--ink-2);
/// font-family:var(--sans); font-size:14px }` with the chevron SVG
/// `M9 2 L4 7 L9 12` (stroke-width 1.4, round caps). The label defaults to
/// "Today" — every back-affordance screen in the prototype routes home to Today.
struct BackControl: View {
    var label: String = "Today"
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // chevron.left at 14pt, 1.4-stroke round caps ≈ regular SF weight.
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.Palette.ink2)
                Text(label)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
