import Foundation
import SwiftData

/// DataSource — the one-way, kill-switch flag that decides where Ayumi's brain
/// runs (SERVER_ARCHITECTURE.md §4.d / §4.e).
///
/// - `.server` (the default, the shipping path): the brain lives on the server.
///   iOS is a thin client; `AtlasRepo` is the single SwiftData writer over the
///   `AtlasAPI` (tRPC-over-HTTP, Keychain bearer token, ATS-enforced).
/// - `.local` (developer-only fallback): a kill-switch that resurrects the
///   on-device path. Per §4.d this MUST write a **separate** store, never the
///   server mirror — two engines writing one store with two id spaces is
///   split-brain with no merge path. In this build the on-device brain has been
///   neutralized (no Anthropic key, no agent loop), so `.local` is a degraded,
///   offline-only seed view kept solely so a developer can A/B the pre-cut-over
///   UI against a throwaway store; it never points at the server cache.
///
/// The flag is read once at launch and is intentionally not a runtime toggle in
/// shipping Settings — flipping engines mid-session against a populated store is
/// exactly the split-brain the spec forbids.
enum DataSource: String {
    case server
    case local

    /// Default to `.server` (the security cut). A developer can override to
    /// `.local` via `UserDefaults["AtlasDataSource"] = "local"` or the
    /// `--data-source local` launch arg; only honored in DEBUG builds so a
    /// TestFlight/release build can never fall back off the server.
    static let current: DataSource = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--data-source"), i + 1 < args.count,
           let ds = DataSource(rawValue: args[i + 1].lowercased()) {
            return ds
        }
        if let raw = UserDefaults.standard.string(forKey: "AtlasDataSource"),
           let ds = DataSource(rawValue: raw.lowercased()) {
            return ds
        }
        #endif
        return .server
    }()

    var isServer: Bool { self == .server }
    var isLocal: Bool { self == .local }

    /// The SwiftData configuration name to use. The developer-only `.local`
    /// fallback uses a SEPARATE store ("atlas-local") so it can never alias the
    /// server cache mirror ("atlas") — the hard split-brain guard from §4.d.
    var storeName: String { isServer ? "atlas" : "atlas-local" }
}
