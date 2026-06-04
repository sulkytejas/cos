import Foundation
import Security

/// Keychain storage for the device bearer token (SERVER_ARCHITECTURE.md §4.e).
///
/// The token is the device's only credential against the server's
/// `protectedProcedure`s. It MUST NOT live in `UserDefaults` (cleartext on disk,
/// trivially exfiltrated) — it lives in the Keychain with accessibility
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
///   - `AfterFirstUnlock` so a background `repo.sync()` / connector poll right
///     after a reboot can still read it (the user has unlocked once since boot).
///   - `ThisDeviceOnly` so the credential never rides an iCloud Keychain or an
///     encrypted-backup restore onto another device.
///
/// One generic-password item, account `device-token`, service `com.atlas.app`.
enum Keychain {
    /// Service + account that scope the single token item.
    private static let service = "com.atlas.app"
    private static let account = "device-token"

    /// The device bearer token, or nil if none is stored.
    static var deviceToken: String? {
        get { read() }
        set {
            if let newValue, !newValue.isEmpty { save(newValue) }
            else { delete() }
        }
    }

    /// True once a token has been provisioned (used by Settings / gating UI).
    static var hasDeviceToken: Bool { read()?.isEmpty == false }

    // MARK: - Primitives

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Upsert the token. Tries to update an existing item first; inserts if absent.
    private static func save(_ token: String) {
        let data = Data(token.utf8)

        // Attempt an in-place update (preserves the item's accessibility attr).
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }

        // Not present (or update failed) — delete any stale item and insert fresh
        // with the required accessibility class.
        delete()
        var insert = baseQuery()
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
