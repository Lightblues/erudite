import Foundation
import Security

// MARK: - KeychainStore
//
// Thin wrapper around Security framework for storing secrets (API keys) in
// the macOS login keychain. Local-only — we don't set kSecAttrSynchronizable,
// so values stay on this Mac and are not pushed to iCloud.
//
// Why Keychain over UserDefaults for keys:
//   - encrypted at rest (UserDefaults is plain plist)
//   - survives app reinstall (UserDefaults is wiped)
//   - Time Machine / `defaults read` can't expose plaintext keys
//
// All values are stored as UTF-8 String. Service is the bundle id, account
// is the per-key name (e.g. "aiApiKey"). One item per (service, account).
enum KeychainStore {
    static let service = Bundle.main.bundleIdentifier ?? "site.easonsi.erudite"

    /// Read a string for `account`. Returns nil if not found or unreadable.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Set or update the value for `account`. Empty string deletes the item
    /// so callers don't need a separate code path for "clear this key".
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        if value.isEmpty {
            return delete(account)
        }
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Try update first, fall back to add. Avoids the "duplicate item" error.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound {
            print("[Keychain] update failed for \(account): \(updateStatus)")
            return false
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("[Keychain] add failed for \(account): \(addStatus)")
            return false
        }
        return true
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
