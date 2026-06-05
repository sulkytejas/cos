import SwiftUI
import Observation
import QuartzCore

/// Ayumi — the Halo engine, ported faithfully from `ayumi-halo.js` (the
/// canonical vanilla Canvas-2D engine in the design handoff). Ayumi's presence
/// as a single luminous "thought" that lives in the rim around the screen.
///
/// One material, four states:
///   • `.idle`      — nothing; the line decays to rest and the trail fades (~2.6s).
///   • `.thinking`  — a jade inhale bloom, then a wandering luminous line (a journey).
///   • `.delivered` — the whole rim blooms gold at once, then exhales (~2.1s) → idle.
///   • `.settled`   — Ayumi's resting PRESENCE while an answer is on screen: a
///                    steady, NON-pulsing uniform warm-gold rim on all four edges
///                    (no envelope, no bloom). It does not auto-decay; it holds
///                    until the screen explicitly calls `.idle` (answer dismissed).
///                    The Search reference measures this rim ≈ #F1EADC uniformly
///                    around the 22pt rim while a RAG answer is present.
///
/// Public API mirrors the JS exactly: `halo.setState(.idle | .thinking | .delivered)`,
/// plus `.settled` for the persistent answer-present presence.
/// `.delivered` auto-settles back to `.idle` after ~2.1s; `.settled` persists.
///
/// FAITHFULNESS NOTES — do not "optimize" these away; they preserve the tuned feel:
///   • The engine advances at a FIXED ~32ms timestep (driven by `HaloView`). Every
///     smoothing/decay constant here (0.05 / 0.06) is per-tick, tuned to that rate.
///   • The organic wander reads an ABSOLUTE wall clock (`CACurrentMediaTime`),
///     never the integrated position `rimT`.
///   • Path inset is 11pt (the reference's running config); the page surface that
///     masks the centre is inset 22pt, so the line is only visible in the rim. The
///     line's ±22pt perpendicular wander makes it breathe in and out of that rim.
@MainActor
@Observable
final class HaloController {
    enum HaloState: Hashable { case idle, thinking, delivered, settled }

    /// Observed — drives `HaloView`'s pause/resume gating (the resume trigger).
    private(set) var stateName: HaloState = .idle

    /// Observed "wake" token: bumped exactly once when the engine newly reaches
    /// rest, so `HaloView` re-evaluates `paused` and parks the timeline. The sim
    /// fields that define rest (`trail`, `deliveredAt`, `thinkingAt`) are
    /// @ObservationIgnored, so they can't trigger that re-evaluation themselves.
    private(set) var restGeneration: Int = 0

    // ── Integrated simulation state (advanced once per tick). Marked
    //    @ObservationIgnored so mutating it ~30×/sec never churns the view graph. ──
    @ObservationIgnored private var rimT: Double = .random(in: 0..<1)
    @ObservationIgnored private var rimSpeed: Double = 0
    @ObservationIgnored private var wanderAmp: Double = 1
    @ObservationIgnored private var tip: CGPoint = .zero
    @ObservationIgnored private var trail: [TrailPoint] = []

    // ── Event timestamps, wall-clock ms (0 == none). ──
    @ObservationIgnored private var deliveredAt: Double = 0
    @ObservationIgnored private var thinkingAt: Double = 0

    /// Last canvas size seen by the renderer; `advance` integrates against it.
    @ObservationIgnored private var lastSize: CGSize = .zero

    /// Tracks the rest transition so `restGeneration` bumps only on entry to rest.
    @ObservationIgnored private var wasAtRest = true

    // Deferred observed-state flips. The sim advances inside the Canvas draw, so
    // it must NOT mutate observed state (stateName / restGeneration) there — it
    // sets these pending flags instead and flushes them on the next runloop hop.
    @ObservationIgnored private var pendingIdle = false
    @ObservationIgnored private var pendingWake = false
    @ObservationIgnored private var flushScheduled = false

    // ── TEMP diagnostics (remove once rendering is confirmed) ──────────────
    /// When true, `render` strokes a bright teal rim every frame regardless of
    /// state — proves the Canvas is rendering, sized, and positioned.
    static var debugRim = false
    @ObservationIgnored private(set) var renderCount = 0
    @ObservationIgnored private(set) var advanceCount = 0
    var debugLine: String {
        "state=\(stateName)  renders=\(renderCount)  advances=\(advanceCount)  size=\(Int(lastSize.width))×\(Int(lastSize.height))  rest=\(isAtRest)"
    }

    /// Path inset from the canvas edge — the rail the thought travels on.
    let rimInset: Double

    /// Corner radius of the rail (and rim hairlines). The JS reference runs in a
    /// square-cornered browser rect, but the device display rounds its corners
    /// (~55pt), which clips anything parked in a square corner into a visible
    /// warm wedge. Concentric with the page card (radius 32 @ inset 22) so the
    /// rim band reads uniform around the corner curve: 32 + (22 − rimInset).
    var rimCornerRadius: Double {
        Double(Theme.Layout.pageRadius) + (Double(Theme.Layout.haloInset) - rimInset)
    }

    init(rimInset: Double = 11) {
        self.rimInset = rimInset
        trail.reserveCapacity(128)
    }

    // MARK: - Tuning constants (verbatim from ayumi-halo.js)
    private static let trailLifeMS: Double = 2600
    private static let thinkTarget: Double = 0.00100      // thinking lap speed
    private static let smooth: Double = 0.05              // rimSpeed + wander ease (idle/think)
    private static let deliverWanderSmooth: Double = 0.06 // wander ease toward 0.12 on delivered
    private static let trailPushThreshold: Double = 0.00015
    private static let deliveredDurMS: Double = 2100
    private static let thinkingInhaleMS: Double = 700

    private func clockMS() -> Double { CACurrentMediaTime() * 1000 }

    // MARK: - Public API (mirrors halo.setState)
    func setState(_ s: HaloState) {
        let prev = stateName
        stateName = s
        pendingIdle = false              // a user/agent override cancels a pending settle
        let now = clockMS()
        deliveredAt = (s == .delivered) ? now : 0
        if s == .thinking && prev != .thinking { thinkingAt = now }
        else if s != .thinking { thinkingAt = 0 }
        wasAtRest = isAtRest             // re-arm rest-transition detection
    }

    /// True when there is nothing left to animate — `HaloView` parks the timeline.
    /// `.settled` is NOT at rest: it must keep painting its steady gold presence
    /// rim every tick (the rim is static, so this reads as a held glow), exactly as
    /// `.delivered` keeps rendering until it auto-settles. Only `.idle` (with no
    /// residual trail/bloom) parks the GPU.
    var isAtRest: Bool {
        stateName == .idle && trail.isEmpty && deliveredAt == 0 && thinkingAt == 0
    }

    // MARK: - Organic multi-frequency noise — JS smoothNoise(t, phase)
    private func smoothNoise(_ t: Double, _ phase: Double) -> Double {
        sin(t * 0.00041 + phase)        * 0.42 +
        sin(t * 0.00097 + phase * 1.7)  * 0.28 +
        sin(t * 0.00211 + phase * 2.3)  * 0.18 +
        sin(t * 0.00373 + phase * 3.1)  * 0.12
    }

    // MARK: - Perimeter path + perturbation — JS rimPath(t)
    // Unlike the square-cornered JS rail, the rail arcs around the corners
    // (radius `rimCornerRadius`) so the thought never parks inside the device's
    // clipped corner curve (which rendered as a stray warm wedge at each corner).
    private func rimPoint(_ t: Double, size: CGSize, now: Double) -> CGPoint {
        let W = Double(size.width), H = Double(size.height)
        let w = W - 2 * rimInset
        let h = H - 2 * rimInset
        let R = min(rimCornerRadius, min(w, h) / 2)
        let sw = w - 2 * R                           // straight run, top/bottom
        let sh = h - 2 * R                           // straight run, left/right
        let arc = .pi * R / 2                        // quarter-corner length
        let perim = 2 * (sw + sh) + 4 * arc
        let u = (t.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * perim
        var x = 0.0, y = 0.0, nx = 0.0, ny = 0.0
        // Inward normal on an arc points from the rail at angle `a` toward the
        // corner's center, matching the straight edges' inward normals.
        func corner(_ cx: Double, _ cy: Double, _ a0: Double, _ s: Double) {
            let a = a0 + s / R
            x = cx + cos(a) * R; y = cy + sin(a) * R
            nx = -cos(a);        ny = -sin(a)
        }
        // Cumulative segment boundaries, clockwise from the top-left arc's end:
        // top → TR arc → right → BR arc → bottom → BL arc → left → TL arc.
        let b1 = sw, b2 = b1 + arc, b3 = b2 + sh, b4 = b3 + arc
        let b5 = b4 + sw, b6 = b5 + arc, b7 = b6 + sh
        if u < b1 {                                  // top edge, L→R
            x = rimInset + R + u;            y = rimInset;                     nx = 0;  ny = 1
        } else if u < b2 {                           // top-right corner
            corner(W - rimInset - R, rimInset + R, -.pi / 2, u - b1)
        } else if u < b3 {                           // right edge, T→B
            x = W - rimInset;                y = rimInset + R + (u - b2);      nx = -1; ny = 0
        } else if u < b4 {                           // bottom-right corner
            corner(W - rimInset - R, H - rimInset - R, 0, u - b3)
        } else if u < b5 {                           // bottom edge, R→L
            x = W - rimInset - R - (u - b4); y = H - rimInset;                 nx = 0;  ny = -1
        } else if u < b6 {                           // bottom-left corner
            corner(rimInset + R, H - rimInset - R, .pi / 2, u - b5)
        } else if u < b7 {                           // left edge, B→T
            x = rimInset;                    y = H - rimInset - R - (u - b6);  nx = 1;  ny = 0
        } else {                                     // top-left corner
            corner(rimInset + R, rimInset + R, .pi, u - b7)
        }
        let perp = smoothNoise(now, 0.0) * 22 * wanderAmp     // along the outward normal
        let tang = smoothNoise(now, 5.7) * 18 * wanderAmp     // along the tangent
        let tx = -ny, ty = nx
        return CGPoint(x: x + nx * perp + tx * tang, y: y + ny * perp + ty * tang)
    }

    // MARK: - Advance one fixed ~32ms tick (mutation only; no drawing) — JS step()
    func advance(size: CGSize, reduceMotion: Bool) {
        lastSize = size
        guard size.width > 1, size.height > 1 else { return }
        advanceCount &+= 1
        let now = clockMS()
        let speedJitter = 1 + smoothNoise(now, 4.2) * 0.55
        var target = 0.0
        switch stateName {
        case .thinking:
            // Reduce Motion: keep the inhale + presence, suppress the roaming.
            target = reduceMotion ? 0 : Self.thinkTarget * speedJitter
            let ampTarget = reduceMotion ? 0.0 : 1.0
            wanderAmp += (ampTarget - wanderAmp) * Self.smooth
            if thinkingAt != 0, now - thinkingAt >= Self.thinkingInhaleMS { thinkingAt = 0 }
        case .delivered:
            target = 0
            wanderAmp += (0.12 - wanderAmp) * Self.deliverWanderSmooth
            // Settle flips the observed stateName — defer it off the Canvas draw.
            if deliveredAt != 0, now - deliveredAt > Self.deliveredDurMS {
                deliveredAt = 0
                pendingIdle = true
            }
        case .settled:
            // Steady presence: no roaming, no bloom envelope. Just hold the rim
            // quiet so the trail decays and only the static gold rim (painted in
            // `render`) remains.
            target = 0
            wanderAmp += (0.12 - wanderAmp) * Self.deliverWanderSmooth
        case .idle:
            target = 0
            wanderAmp += (1 - wanderAmp) * Self.smooth
        }
        rimSpeed += (target - rimSpeed) * Self.smooth
        rimT += rimSpeed
        tip = rimPoint(rimT, size: size, now: now)
        if rimSpeed > Self.trailPushThreshold {
            trail.append(TrailPoint(x: tip.x, y: tip.y, born: now))
        }
        while let first = trail.first, now - first.born > Self.trailLifeMS {
            trail.removeFirst()
        }

        // Newly at rest → wake the view once so HaloView can park the timeline.
        let atRest = isAtRest
        if atRest && !wasAtRest { pendingWake = true }
        wasAtRest = atRest

        scheduleFlushIfNeeded()
    }

    /// Applies deferred observed-state changes on the next main-actor hop, so the
    /// observed mutations never happen during the Canvas render.
    private func scheduleFlushIfNeeded() {
        guard pendingIdle || pendingWake, !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in self.flushPending() }
    }

    private func flushPending() {
        flushScheduled = false
        if pendingIdle { stateName = .idle; pendingIdle = false }
        if pendingWake { restGeneration &+= 1; pendingWake = false }
    }

    // MARK: - Render (read-only; called from the Canvas) — JS render block
    func render(into ctx: inout GraphicsContext, size: CGSize) {
        lastSize = size
        renderCount &+= 1
        let now = clockMS()

        // TEMP: always-on rim so we can confirm the Canvas draws & is sized.
        if Self.debugRim {
            let r = CGRect(x: rimInset, y: rimInset,
                           width: Double(size.width) - 2 * rimInset,
                           height: Double(size.height) - 2 * rimInset)
            ctx.stroke(Path(roundedRect: r, cornerRadius: rimCornerRadius, style: .continuous),
                       with: .color(Color(.sRGB, red: 0, green: 0.537, blue: 0.659, opacity: 0.85)), lineWidth: 2)
        }

        // The wandering thought: three stacked strokes over the aging trail.
        // Each segment's effective alpha = strokeColor.alpha × per-segment factor,
        // exactly mirroring JS strokeStyle-alpha × globalAlpha.
        if trail.count > 1 {
            let fam = (stateName == .delivered) ? Self.gold : Self.jade
            strokeTrail(&ctx, now: now, color: fam.aura, width: 18) { a in a * a * 0.55 }
            strokeTrail(&ctx, now: now, color: fam.mid,  width: 5)  { a in a * 0.70 }
            strokeTrail(&ctx, now: now, color: fam.core, width: 1.4) { a in a * 0.55 }
        }

        // Delivered bloom (gold, fire-and-settle) + pale rim hairline.
        if stateName == .delivered, deliveredAt != 0 {
            drawBloom(&ctx, size: size, now: now,
                      since: deliveredAt, dur: Self.deliveredDurMS,
                      attack: 0.22, eScale: 1.0, bandBase: 10, bandGrow: 26,
                      stripColor: Self.goldBloom, stripAlpha: 0.55, hairline: true)
        }

        // Thinking onset inhale (jade, short, gentler — no hairline).
        if stateName == .thinking, thinkingAt != 0 {
            drawBloom(&ctx, size: size, now: now,
                      since: thinkingAt, dur: Self.thinkingInhaleMS,
                      attack: 0.35, eScale: 0.7, bandBase: 8, bandGrow: 20,
                      stripColor: Self.jadeBloom, stripAlpha: 0.5, hairline: false)
        }

        // Settled presence: a STEADY uniform warm-gold rim (no envelope, no
        // breathing) on all four edges while an Ayumi answer is on screen. Search's
        // reference measures the rim ≈ #F1EADC uniformly around the 22pt rim. Paint
        // a constant-alpha gold band over the full rim width + the pale gold rim
        // hairline, so the composited rim over paper-deep (#F7F7F5) reads warm-gold.
        if stateName == .settled {
            drawSettledRim(&ctx, size: size)
        }
    }

    /// The steady gold presence rim for `.settled`: a uniform constant-alpha gold
    /// fill across the full rim width on all four edges + the pale gold hairline.
    /// No envelope — it does not breathe; it holds until `.idle`.
    private func drawSettledRim(_ ctx: inout GraphicsContext, size: CGSize) {
        let W = Double(size.width), H = Double(size.height)
        // The page card masks everything inboard of `haloInset` (22pt); fill the
        // full rim so the band reads uniform right up to the card edge.
        let band = Double(22)
        // Tuned so goldBloom (212,172,96) over paper-deep (#F7F7F5) composites to
        // ≈ #F1EADC (the soft cream the design reference measures, ~#F2EDE1). A flat
        // fill (location 0→1 same alpha) keeps it uniform, unlike the bloom strips
        // which fade inward. At the previous a=0.30 the composite read #ECE0C8 — a
        // deeper, over-saturated gold (sim measured #EEE3C9) than the reference.
        let a = 0.17
        // One even-odd ring fill (full canvas minus the page card's rounded rect)
        // instead of four overlapping edge strips: the strips double-composited at
        // the corners (0.17 → ~0.31), and the display's rounded corner clipped the
        // darker square into a visible warm wedge. The ring hugs the card's exact
        // corner curve so the band reads uniform everywhere.
        var ring = Path()
        ring.addRect(CGRect(x: 0, y: 0, width: W, height: H))
        ring.addRoundedRect(in: CGRect(x: band, y: band, width: W - 2 * band, height: H - 2 * band),
                            cornerSize: CGSize(width: Double(Theme.Layout.pageRadius),
                                               height: Double(Theme.Layout.pageRadius)),
                            style: .continuous)
        ctx.fill(ring, with: .color(Self.goldBloom.opacity(a)), style: FillStyle(eoFill: true))
        // Pale gold rim hairline, low constant alpha — rounded concentric with the card.
        let rimRect = CGRect(x: rimInset, y: rimInset, width: W - 2 * rimInset, height: H - 2 * rimInset)
        ctx.stroke(Path(roundedRect: rimRect, cornerRadius: rimCornerRadius, style: .continuous),
                   with: .color(Self.goldHair.opacity(0.28)), lineWidth: 1.4)
    }

    private func strokeTrail(_ ctx: inout GraphicsContext, now: Double,
                             color: Color, width: Double, factor: (Double) -> Double) {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        for i in 1..<trail.count {
            let a = 1 - (now - trail[i].born) / Self.trailLifeMS
            if a <= 0 { continue }
            var seg = ctx                       // copy shares the canvas; opacity is local
            seg.opacity = factor(a)
            var path = Path()
            path.move(to: CGPoint(x: trail[i - 1].x, y: trail[i - 1].y))
            path.addLine(to: CGPoint(x: trail[i].x, y: trail[i].y))
            seg.stroke(path, with: .color(color), style: style)
        }
    }

    /// One bloom gesture: four inward edge-gradient strips (+ optional rim
    /// hairline). `attack` is the rise fraction; release = 1 − attack. Used for
    /// both the gold `delivered` bloom and the jade `thinking` inhale.
    private func drawBloom(_ ctx: inout GraphicsContext, size: CGSize, now: Double,
                           since: Double, dur: Double, attack: Double, eScale: Double,
                           bandBase: Double, bandGrow: Double,
                           stripColor: Color, stripAlpha: Double, hairline: Bool) {
        let W = Double(size.width), H = Double(size.height)
        let t = min(1, (now - since) / dur)
        let env = t < attack ? (t / attack) : 1 - ((t - attack) / (1 - attack))
        let e = max(0, min(1, env)) * eScale
        if e <= 0 { return }
        let band = bandBase + (1 - e) * bandGrow

        func strip(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                   _ gx0: Double, _ gy0: Double, _ gx1: Double, _ gy1: Double) {
            let grad = Gradient(stops: [
                .init(color: stripColor.opacity(stripAlpha * e), location: 0),
                .init(color: stripColor.opacity(0),              location: 1),
            ])
            let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            ctx.fill(Path(rect), with: .linearGradient(
                grad, startPoint: CGPoint(x: gx0, y: gy0), endPoint: CGPoint(x: gx1, y: gy1)))
        }
        // Side strips stop short of the top/bottom bands so the corners are
        // painted exactly once (overlap doubled the alpha into a warm corner
        // wedge under the device's rounded corner clip).
        strip(0, 0, W, band, 0, 0, 0, band)             // top  — bright at edge, fading inward
        strip(0, H - band, W, H, 0, H, 0, H - band)     // bottom
        strip(0, band, band, H - band, 0, 0, band, 0)   // left
        strip(W - band, band, W, H - band, W, 0, W - band, 0)  // right

        if hairline {
            // JS applies globalAlpha=e to this rim stroke (strips already baked e),
            // so the effective alpha is 0.7·e². Rounded concentric with the card.
            let rimRect = CGRect(x: rimInset, y: rimInset, width: W - 2 * rimInset, height: H - 2 * rimInset)
            ctx.stroke(Path(roundedRect: rimRect, cornerRadius: rimCornerRadius, style: .continuous),
                       with: .color(Self.goldHair.opacity(0.7 * e * e)), lineWidth: 1.4)
        }
    }

    // MARK: - Colour families (verbatim RGB from ayumi-halo.js)
    private struct Family { let aura: Color; let mid: Color; let core: Color }
    private static let jade = Family(
        aura: Color(.sRGB, red:  70/255, green: 165/255, blue: 130/255, opacity: 0.40),
        mid:  Color(.sRGB, red:  80/255, green: 180/255, blue: 142/255, opacity: 0.72),
        core: Color(.sRGB, red: 190/255, green: 230/255, blue: 208/255, opacity: 0.85))
    private static let gold = Family(
        aura: Color(.sRGB, red: 208/255, green: 168/255, blue:  92/255, opacity: 0.40),
        mid:  Color(.sRGB, red: 216/255, green: 180/255, blue: 108/255, opacity: 0.72),
        core: Color(.sRGB, red: 250/255, green: 240/255, blue: 214/255, opacity: 0.85))
    private static let goldBloom = Color(.sRGB, red: 212/255, green: 172/255, blue:  96/255, opacity: 1)
    private static let goldHair  = Color(.sRGB, red: 250/255, green: 240/255, blue: 214/255, opacity: 1)
    private static let jadeBloom = Color(.sRGB, red:  70/255, green: 165/255, blue: 130/255, opacity: 1)
}

private struct TrailPoint {
    var x: CGFloat
    var y: CGFloat
    var born: Double
}
