import Foundation
import Security

/// Stores small secrets (the GitHub read token) in the Keychain. If the Keychain refuses (it can on
/// re-signed sideloaded builds) it falls back to a protected file inside the app sandbox, excluded from
/// backups, so the feature keeps working.
enum SecretStore {
    private static let service = "com.studytrack.app.secrets"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        SecItemDelete(baseQuery(key) as CFDictionary)
        var add = baseQuery(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
            removeFallback(key)
        } else {
            writeFallback(data, key)
        }
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return readFallback(key)
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        removeFallback(key)
    }

    // MARK: Fallback file

    private static func fallbackURL(_ key: String) -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("secrets", isDirectory: true).appendingPathComponent("\(key).bin")
    }

    private static func writeFallback(_ data: Data, _ key: String) {
        var url = fallbackURL(key)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func readFallback(_ key: String) -> String? {
        guard let data = try? Data(contentsOf: fallbackURL(key)) else { return nil }
        let text = String(data: data, encoding: .utf8)
        return (text?.isEmpty ?? true) ? nil : text
    }

    private static func removeFallback(_ key: String) {
        try? FileManager.default.removeItem(at: fallbackURL(key))
    }
}
