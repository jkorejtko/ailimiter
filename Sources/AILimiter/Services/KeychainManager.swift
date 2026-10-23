import Foundation

public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()
    private let keyPrefix = "com.ailimiter.token."

    private init() {}

    public func save(token: String, for accountId: UUID) -> Bool {
        let key = keyPrefix + accountId.uuidString
        UserDefaults.standard.set(token, forKey: key)
        return true
    }

    public func get(for accountId: UUID) -> String? {
        let key = keyPrefix + accountId.uuidString
        if let token = UserDefaults.standard.string(forKey: key) {
            return token
        }
        // Fallback pro dříve uložená data ve starém fallback klíči
        return UserDefaults.standard.string(forKey: "sec_\(accountId.uuidString)")
    }

    public func delete(for accountId: UUID) {
        let key = keyPrefix + accountId.uuidString
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: "sec_\(accountId.uuidString)")
    }
}
