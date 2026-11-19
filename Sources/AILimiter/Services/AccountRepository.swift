import Foundation

@MainActor
final class AccountRepository {
    static let accountsKey = "com.ailimiter.saved_accounts"
    let defaults: UserDefaults
    private let credentials: any CredentialStore

    init(defaults: UserDefaults = .standard, credentials: any CredentialStore = KeychainManager.shared) {
        self.defaults = defaults
        self.credentials = credentials
    }

    func load() throws -> [AccountCredential]? {
        guard let data = defaults.data(forKey: Self.accountsKey) else { return nil }
        var accounts = try JSONDecoder().decode([AccountCredential].self, from: data)
        for index in accounts.indices {
            let id = accounts[index].id
            let legacy = defaults.string(forKey: "com.ailimiter.token.\(id.uuidString)")
                ?? defaults.string(forKey: "sec_\(id.uuidString)")
                ?? accounts[index].token
            if let saved = try credentials.get(for: id) {
                accounts[index].token = saved
            } else if !legacy.isEmpty {
                try credentials.save(token: legacy, for: id)
                accounts[index].token = legacy
            }
        }
        // Remove old copies only after all credentials were stored successfully.
        defaults.set(try JSONEncoder().encode(accounts), forKey: Self.accountsKey)
        for account in accounts { removeLegacy(for: account.id) }
        return accounts
    }

    func save(_ accounts: [AccountCredential]) throws {
        let metadata = try JSONEncoder().encode(accounts)
        for account in accounts { try credentials.save(token: account.token, for: account.id) }
        defaults.set(metadata, forKey: Self.accountsKey)
        for account in accounts { removeLegacy(for: account.id) }
    }

    func remove(_ id: UUID, remainingAccounts: [AccountCredential]) throws {
        let metadata = try JSONEncoder().encode(remainingAccounts)
        try credentials.delete(for: id)
        defaults.set(metadata, forKey: Self.accountsKey)
        removeLegacy(for: id)
    }

    private func removeLegacy(for id: UUID) {
        defaults.removeObject(forKey: "com.ailimiter.token.\(id.uuidString)")
        defaults.removeObject(forKey: "sec_\(id.uuidString)")
    }
}
