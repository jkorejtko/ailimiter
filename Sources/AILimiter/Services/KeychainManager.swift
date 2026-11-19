import Foundation
import Security

protocol CredentialStore: Sendable {
    func save(token: String, for accountId: UUID) throws
    func get(for accountId: UUID) throws -> String?
    func delete(for accountId: UUID) throws
}

public final class KeychainManager: CredentialStore, Sendable {
    public static let shared = KeychainManager()
    private let service = "com.ailimiter.credentials"

    private init() {}

    private func query(for id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func save(token: String, for accountId: UUID) throws {
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let result = SecItemUpdate(query(for: accountId) as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query(for: accountId).merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(result)
        }
    }

    public func get(for accountId: UUID) throws -> String? {
        var item = query(for: accountId)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw CredentialError(status: errSecDecode)
        }
        return token
    }

    public func delete(for accountId: UUID) throws {
        let status = SecItemDelete(query(for: accountId) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw CredentialError(status: status) }
    }
}

struct CredentialError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Keychain není dostupný (\(status)). Odemkněte jej a zkuste akci znovu."
    }
}
