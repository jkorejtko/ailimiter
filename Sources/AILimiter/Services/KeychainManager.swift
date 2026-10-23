import Foundation
import Security

public final class KeychainManager {
    public static let shared = KeychainManager()
    private let serviceName = "com.ailimiter.mac"

    private init() {}

    public func save(token: String, for accountId: UUID) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let accountKey = accountId.uuidString

        // Smažeme případný předchozí záznam
        delete(for: accountId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        } else {
            // Fallback pro lokální storage v případě nepodepsaného běhu v CLI
            UserDefaults.standard.set(token, forKey: "sec_\(accountKey)")
            return true
        }
    }

    public func get(for accountId: UUID) -> String? {
        let accountKey = accountId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return string
        }

        // Fallback
        return UserDefaults.standard.string(forKey: "sec_\(accountKey)")
    }

    public func delete(for accountId: UUID) {
        let accountKey = accountId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "sec_\(accountKey)")
    }
}
