import SwiftUI
import SwiftData
import LocalAuthentication
import os

@main
struct AtlasApp: App {
    let container: ModelContainer
    /// The single SwiftData writer (SERVER_ARCHITECTURE.md §4.e). The brain runs
    /// on the server; this thin client only swaps imperative calls onto the repo
    /// and mirrors server rows into the cache for the `@Query` reads.
    @State private var repo: AtlasRepo
    @Environment(\.scenePhase) private var scenePhase

    // ─── App lock (Face ID) ───────────────────────────────────────
    /// Opt-in (Settings → FACE ID). The lock is a LOCAL privacy cover — someone
    /// holding the unlocked phone can't read the thread. It does NOT replace
    /// server auth: the bearer token stays in the Keychain regardless.
    @AppStorage(Self.lockDefaultsKey) private var requireBiometricLock = false
    /// Whether the paper cover is down. Cold-launches locked when the toggle is
    /// on (read via UserDefaults — `@AppStorage` isn't available in `init`).
    @State private var locked: Bool
    /// When the app last left the foreground — re-lock only past the grace
    /// window, so flipping to Mail and back doesn't re-scan the user's face.
    @State private var backgroundedAt: Date? = nil
    /// The recognition ceremony, matching the designer's standalone handout
    /// (designs/Atlas Lock Screen (standalone).html) state-for-state:
    ///   locked     — seal at rest, halo dimmed (sat .4 / op .34), "Closed. …"
    ///   scanning   — jade ring sweeps closed (1.3s), halo stirs (`thinking`),
    ///                "Looking…" / SCANNING
    ///   recognized — ring recedes, halo blooms gold (`delivered`),
    ///                "Welcome back." / RECOGNIZED  (held 850ms)
    ///   opened     — seal grows jade-deep (1.12), the paper card scales 1.06
    ///                and fades (760ms) — the door opens through
    enum LockPhase { case locked, scanning, recognized, opened }
    @State private var lockPhase: LockPhase = .locked
    /// Quick re-entry (re-lock after backgrounding) skips the scan-frame
    /// ceremony — no track circle, no sweep, no brackets. Just the seal,
    /// turning jade on recognition. Cold launches get the full ceremony.
    @State private var lockIsQuick = false

    private static let lockDefaultsKey = "requireBiometricLock"
    private static let relockGraceSeconds: TimeInterval = 30
    /// DEBUG `--locked`: force the cover for screenshots WITHOUT firing the
    /// system Face ID sheet over it (same convention as `--today-bottom`).
    static var lockDebug: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--locked") || lockDemo
        #else
        false
        #endif
    }
    /// DEBUG `--lock-demo`: loop the recognition ceremony on the handout's
    /// exact clock (no LAContext) — for sim verification of the motion.
    static var lockDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--lock-demo")
        #else
        false
        #endif
    }

    init() {
        #if DEBUG
        // Dev-only pairing hook — configure the server + device token from a
        // launch arg, so the SIMULATOR can pair with the local dev server
        // without driving the Settings UI (idb gestures unavailable):
        //   xcrun simctl launch <udid> com.atlas.app --pair http://localhost:3000 <token>
        // Writes the same stores the Settings pairing flow writes (UserDefaults
        // URL + Keychain token) BEFORE AtlasAPI first reads them. Compiled out
        // of release builds; the https-only rule still governs non-loopback URLs.
        if let i = CommandLine.arguments.firstIndex(of: "--pair"),
           i + 2 < CommandLine.arguments.count {
            let url = CommandLine.arguments[i + 1]
            let token = CommandLine.arguments[i + 2]
            let log = Logger(subsystem: "com.atlas.app", category: "Pair")
            if AtlasAPI.validatedHTTPS(url) != nil {
                UserDefaults.standard.set(url, forKey: AtlasAPI.baseURLDefaultsKey)
                Keychain.deviceToken = token
                log.info("paired via launch arg: \(url, privacy: .public), token stored: \(Keychain.hasDeviceToken)")
            } else {
                log.error("--pair URL rejected: \(url, privacy: .public)")
            }
        } else if CommandLine.arguments.contains("--pair") {
            Logger(subsystem: "com.atlas.app", category: "Pair")
                .error("--pair present but missing <url> <token>; argv: \(CommandLine.arguments.joined(separator: " "), privacy: .public)")
        }
        #endif
        let container = AppContainer.make()
        self.container = container
        // Build the repo on the container's main context (it is `@MainActor`).
        _repo = State(initialValue: AtlasRepo(context: ModelContext(container)))
        // Cold launches start covered when the lock is enabled (or forced by
        // the DEBUG `--locked` screenshot hook).
        _locked = State(initialValue:
            UserDefaults.standard.bool(forKey: Self.lockDefaultsKey) || Self.lockDebug)
        configureAppearance()
        dumpFontRegistry()
        // Dev-only band override via launch arg. Run with:
        //   xcrun simctl launch <udid> com.atlas.app --AYUMI_BAND afternoon
        if let i = CommandLine.arguments.firstIndex(of: "--AYUMI_BAND"),
           i + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[i + 1].lowercased() {
            case "morning":   TimeBand.debugOverride = .morning
            case "afternoon": TimeBand.debugOverride = .afternoon
            case "evening":   TimeBand.debugOverride = .evening
            case "night":     TimeBand.debugOverride = .night
            default: break
            }
        }
        // Ask for calendar access so EventKit can be pushed to the server as
        // `calendar` signals (the device-only push source, §4.e).
        //
        // SKIP this eager request during screenshot / dev launches: when any
        // pixel-match capture arg is present (`--page`, `--chapter`, `--query`,
        // `--seed-calendar`, `--capture`) the OS would otherwise present the
        // full-access calendar permission alert ("'Ayumi' Would Like Full Access
        // to Your Calendar") immediately on launch, centered over whatever screen
        // is being captured, with a dimming scrim that occludes/desaturates the
        // frame. The permission isn't part of any screen's UI — gate it so the
        // alert never renders during capture. (For real runs the request still
        // fires; for a granted capture, pre-authorize the sim:
        // `xcrun simctl privacy <udid> grant calendar com.atlas.app`.)
        let captureArgs: Set<String> = ["--page", "--chapter", "--query", "--seed-calendar", "--capture", "--locked", "--lock-demo"]
        if !CommandLine.arguments.contains(where: captureArgs.contains) {
            Task { await EventKitCalendarSource.requestAccess() }
        }
    }

    /// One-time print of every bundled font family + PostScript names so we
    /// can confirm `Font.custom(...)` references resolve. Filter to our families.
    private func dumpFontRegistry() {
        let log = Logger(subsystem: "com.atlas.app", category: "Fonts")
        let interesting = ["Instrument", "Manrope", "JetBrains"]
        for family in UIFont.familyNames.sorted() where interesting.contains(where: family.contains) {
            let names = UIFont.fontNames(forFamilyName: family)
            log.info("\(family, privacy: .public) → \(names.joined(separator: ", "), privacy: .public)")
        }
    }

    @State private var splashDone: Bool = false

    /// While `true`, the app launches into the Ayumi v0.6 redesign (the new
    /// shell + screens). Flip to `false` to restore the legacy v0.3 UI.
    private static let showAyumi = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--capture") {
                    // DEBUG-only: verify the Capture system (cue + well) in isolation.
                    CapturePreviewScreen()
                        .environment(repo)
                        .preferredColorScheme(.light)
                } else if Self.showAyumi {
                    AyumiRoot()
                        .environment(repo)
                        .preferredColorScheme(.light)
                } else {
                    legacyRoot
                }
                #else
                if Self.showAyumi {
                    AyumiRoot()
                        .environment(repo)
                        .preferredColorScheme(.light)
                } else {
                    legacyRoot
                }
                #endif

                // The paper cover sits over everything while locked — and also
                // whenever the lock is on and the scene isn't active, so the
                // app-switcher snapshot shows paper, not the user's life.
                if locked || (requireBiometricLock && scenePhase != .active) {
                    AppLockCover(phase: lockPhase, quick: lockIsQuick) {
                        Task { Self.lockDemo ? await demoUnlock() : await unlock() }
                    }
                    .task {
                        // Face ID is automatic (the handout auto-runs at 1.4s; the
                        // app scans as soon as the cover lands). `--locked` holds
                        // the static cover for screenshots; `--lock-demo` walks
                        // the fake ceremony on the handout's exact clock.
                        guard locked else { return }
                        if Self.lockDemo { await demoUnlock() }
                        else if !Self.lockDebug { await unlock() }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .animation(.easeOut(duration: 0.25), value: locked)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Start the re-lock clock. (`.inactive` alone — system sheets,
                // notification pulls, the Face ID dialog itself — never re-locks.)
                backgroundedAt = Date()
            case .active:
                if requireBiometricLock, let away = backgroundedAt,
                   Date().timeIntervalSince(away) > Self.relockGraceSeconds {
                    locked = true
                    lockPhase = .locked   // fresh cover, seal at rest
                    lockIsQuick = true    // re-entry: seal-only, no scan frame
                }
                backgroundedAt = nil
                // The brain is server-side (§4.e). On foreground: pull server rows
                // into the cache mirror, then push the device calendar as signals
                // (idempotent — the server upserts on `(source, externalId)`).
                // `.local` is the developer-only offline fallback — no server I/O.
                if DataSource.current.isServer {
                    Task {
                        await repo.sync()
                        await repo.pushCalendarSignals()
                    }
                }
            default:
                break
            }
        }
    }

    /// Verify the owner and walk the recognition ceremony.
    /// `.deviceOwnerAuthentication` = Face ID with automatic passcode fallback
    /// (the USE PASSCODE foot link rides the same call — after a biometric
    /// cancel/failure the system sheet offers the passcode itself). We never
    /// see biometric data — only the system's yes/no.
    ///
    /// Cadence honors the handout's clock: the jade sweep needs its 1.3s before
    /// recognition lands (a fast real scan WAITS for the sweep — recognition is
    /// a moment, not a loading bar), then 850ms of "Welcome back.", then the
    /// 760ms open-through, then the cover lifts.
    @MainActor private func unlock() async {
        guard lockPhase == .locked else { return }   // a scan is already in flight
        let ctx = LAContext()
        var unavailable: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &unavailable) else {
            // No passcode/biometrics enrolled on this device — there is nothing
            // to verify against, so the cover would be a lock-out, not a lock.
            locked = false
            return
        }
        lockPhase = .scanning
        let scanStart = Date()
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "Unlock Ayumi")
            guard ok else { lockPhase = .locked; return }
            // Let the sweep finish (handout: scanning holds 1.45s) — but never
            // wait longer than the sweep still owes. Quick re-entry has no
            // sweep to honor: recognition lands the moment Ayumi knows you.
            if !lockIsQuick {
                let owed = 1.45 - Date().timeIntervalSince(scanStart)
                if owed > 0 { try? await Task.sleep(for: .seconds(owed)) }
            }
            lockPhase = .recognized
            try? await Task.sleep(for: .seconds(0.85))   // "Welcome back." beat
            lockPhase = .opened
            try? await Task.sleep(for: .seconds(0.9))    // the 760ms door + a breath
            locked = false
            lockPhase = .locked                          // reset for the next cover
            lockIsQuick = false
        } catch {
            // Cancelled / failed — seal returns to rest; tap (or the system's
            // passcode offer on the next attempt) retries.
            lockPhase = .locked
        }
    }

    /// DEBUG `--lock-demo`: the handout's standalone loop, byte-for-time —
    /// scanning at +0, recognized +1.45s, opened +0.85s, reset +0.9s, replay
    /// after a 1.4s rest. No LAContext anywhere near it.
    @MainActor private func demoUnlock() async {
        guard lockPhase == .locked else { return }
        while locked {
            lockPhase = .scanning
            try? await Task.sleep(for: .seconds(1.45))
            lockPhase = .recognized
            try? await Task.sleep(for: .seconds(0.85))
            lockPhase = .opened
            try? await Task.sleep(for: .seconds(0.9))
            lockPhase = .locked
            try? await Task.sleep(for: .seconds(1.4))
        }
    }

    /// The legacy v0.3 root (splash → RootView), extracted so both the DEBUG and
    /// release `WindowGroup` branches can reuse it.
    @ViewBuilder private var legacyRoot: some View {
        ZStack {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.Palette.moss)
                .opacity(splashDone ? 1 : 0)

            if !splashDone {
                SplashView(onComplete: { splashDone = true })
                    .transition(.opacity)
            }
        }
    }

    // ─── The lock cover (designs/Atlas Lock Screen (standalone).html) ──
    /// The designer's "Lock × Halo": the app's halo breathes dimly behind a
    /// paper card (same 22pt inset / 32pt radius geometry as PageShell), the
    /// seal 歩 sits inside a scan frame — a hairline track circle, a jade
    /// progress ring, four corner brackets — over a crossfading caption.
    /// Recognition is a ceremony, not a spinner: the ring sweeps closed while
    /// Ayumi looks, the halo blooms gold on recognition, and the paper card
    /// itself opens through (scale 1.06, fade 760ms) like a door.
    private struct AppLockCover: View {
        let phase: LockPhase
        /// Re-entry covers drop the scan frame — the seal alone carries the
        /// recognition (it turns jade once Ayumi knows you).
        let quick: Bool
        let onUnlock: () -> Void
        /// The cover's own halo (idle → thinking → delivered across the phases).
        /// Same rim geometry as PageShell's, so the halo reads continuous when
        /// the card opens through to the app.
        @State private var halo = HaloController(rimInset: 11)
        /// TAP TO UNLOCK fades in 1.4s after the cover lands (CSS `hintIn`).
        @State private var hintShown = false

        private var scanning: Bool   { phase == .scanning }
        private var recognized: Bool { phase == .recognized || phase == .opened }
        private var opened: Bool     { phase == .opened }

        var body: some View {
            ZStack {
                // The desk + halo behind the card. Locked, the halo is almost
                // asleep (CSS: saturate(.4) opacity(.34)); scanning stirs it;
                // recognition blooms it gold (the `delivered` state).
                Theme.Palette.desk.ignoresSafeArea()
                HaloView(controller: halo)
                    .ignoresSafeArea()
                    .saturation(scanning ? 0.9 : (recognized ? 1.0 : 0.4))
                    .opacity(scanning ? 0.92 : (recognized ? 1.0 : 0.34))
                    .animation(.easeInOut(duration: 0.9), value: phase)

                // The paper card — the page geometry, opening through on unlock
                // (CSS: body.opened .page { transform: scale(1.06); opacity: 0 }
                //  over 760ms cubic-bezier(.5,0,.2,1)).
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Layout.pageRadius, style: .continuous)
                        .fill(Theme.Palette.paper)
                        .shadow(color: Color(hex: 0x141820).opacity(0.04), radius: 1, y: 1)

                    VStack(spacing: 0) {
                        // ── The scan frame (188×188: track r89 + jade sweep + brackets).
                        //    Quick re-entry hides the whole frame — the seal alone
                        //    carries recognition. ──
                        ZStack {
                            if !quick {
                            Circle()
                                .stroke(Theme.Palette.rule, lineWidth: 1.4)
                                .frame(width: 178, height: 178)
                            // The jade sweep, on the handout's exact clock:
                            //   scanning   — trim 0→1 over 1300ms, fade IN 300ms
                            //   recognized — trim retreats 1→0 (same 1300ms curve)
                            //                but the ring fades OUT in 300ms, so
                            //                the retreat itself is unseen
                            //   opened     — opacity returns (300ms), jade-deep
                            //                (500ms): the still-unwinding tail
                            //                flicks past as the door opens
                            Circle()
                                .trim(from: 0, to: scanning ? 1 : 0)
                                .stroke(opened ? Theme.Palette.jadeDeep : Theme.Palette.jade,
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .animation(.timingCurve(0.45, 0, 0.25, 1, duration: 1.3), value: scanning)
                                .animation(.easeInOut(duration: 0.5), value: opened)
                                .frame(width: 178, height: 178)
                                .rotationEffect(.degrees(-90))
                                .opacity(scanning || opened ? 1 : 0)
                                .animation(.easeInOut(duration: 0.3), value: scanning || opened)
                            CornerBrackets()
                                .stroke(scanning ? Theme.Palette.jade : Theme.Palette.ink4,
                                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                                .opacity(opened ? 0 : (scanning ? 0.9 : 0.5))
                                .animation(.easeInOut(duration: 0.5), value: phase)
                            }
                            // The seal: rest 1.0 → scanning 1.04 → opened 1.12,
                            // turning jade-deep AT RECOGNITION (the green IS the
                            // success signal, in both ceremonies) — 700ms
                            // cubic-bezier(.34,1.1,.64,1), a slight overshoot.
                            // Quick re-entry: the green flip carries the whole
                            // moment, with a small 1.08 swell.
                            Text("歩")
                                .font(Theme.Font.kanji(88))
                                .foregroundStyle(recognized ? Theme.Palette.jadeDeep : Theme.Palette.ink)
                                .scaleEffect(opened ? 1.12 : (quick ? (recognized ? 1.08 : 1.0)
                                                                    : (scanning ? 1.04 : 1.0)))
                                .animation(.timingCurve(0.34, 1.1, 0.64, 1, duration: 0.7), value: phase)
                        }
                        .frame(width: 188, height: 188)
                        .contentShape(Rectangle())
                        .onTapGesture { if phase == .locked { onUnlock() } }

                        // ── Caption (crossfade 400ms, fixed 24pt slot) ──
                        ZStack {
                            captionText("Closed. Your life stays yours.", shown: phase == .locked)
                            captionText("Looking…", shown: scanning)
                            captionText("Welcome back.", shown: recognized)
                        }
                        .frame(height: 24)
                        .padding(.top, 30)

                        // ── Sub (mono 9, 0.2em, uppercase) ──
                        Text(subText)
                            .font(Theme.Font.mono(9)).tracking(1.8)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.Palette.ink4)
                            .padding(.top, 10)

                        // ── TAP TO UNLOCK hint (locked only, 1.4s late, op .7) ──
                        Text("TAP TO UNLOCK")
                            .font(Theme.Font.mono(8.5)).tracking(1.36)
                            .foregroundStyle(Theme.Palette.ink4)
                            .opacity(phase == .locked && hintShown ? 0.7 : 0)
                            .animation(.easeOut(duration: 0.6), value: hintShown)
                            .padding(.top, 2)
                    }

                    // (The handout's USE PASSCODE foot link was dropped by
                    // product call: it fired the same system flow — Apple's
                    // sheet offers the passcode itself after a failed scan, so
                    // the seal tap already covers every road in.)
                }
                .padding(Theme.Layout.haloInset)
                .scaleEffect(opened ? 1.06 : 1.0)
                .opacity(opened ? 0 : 1)
                .animation(.timingCurve(0.5, 0, 0.2, 1, duration: 0.76), value: opened)
            }
            .task {
                try? await Task.sleep(for: .seconds(1.4))
                hintShown = true
            }
            .onChange(of: phase) { _, p in
                switch p {
                case .locked:     halo.setState(.idle)
                case .scanning:   halo.setState(.thinking)
                case .recognized, .opened: halo.setState(.delivered)
                }
            }
        }

        private func captionText(_ s: String, shown: Bool) -> some View {
            Text(s)
                .font(Theme.Font.serifItalic(18))
                .foregroundStyle(Theme.Palette.ink2)
                .opacity(shown ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: shown)
        }

        private var subText: String {
            switch phase {
            case .locked:    return "Face ID"
            case .scanning:  return "Scanning"
            case .recognized, .opened: return "Recognized"
            }
        }
    }

    /// The handout's four corner brackets, exact path coords in the 188 box:
    /// 12pt arms, corners at (18,14) (170,14) (18,174) (170,174).
    private struct CornerBrackets: Shape {
        func path(in rect: CGRect) -> Path {
            let sx = rect.width / 188, sy = rect.height / 188
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
            }
            var p = Path()
            p.move(to: pt(30, 14));  p.addLine(to: pt(18, 14));  p.addLine(to: pt(18, 26))
            p.move(to: pt(158, 14)); p.addLine(to: pt(170, 14)); p.addLine(to: pt(170, 26))
            p.move(to: pt(30, 174)); p.addLine(to: pt(18, 174)); p.addLine(to: pt(18, 162))
            p.move(to: pt(158, 174)); p.addLine(to: pt(170, 174)); p.addLine(to: pt(170, 162))
            return p
        }
    }

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "ColorPaper")
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(named: "ColorInk") ?? .black
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(named: "ColorInk") ?? .black
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(named: "ColorPaper")
        tabAppearance.shadowColor = UIColor(named: "ColorBorderWarm")
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
