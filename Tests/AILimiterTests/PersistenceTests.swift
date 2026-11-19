import Foundation
import Testing
@testable import AILimiter

final class MemoryCredentials: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    let failWrites: Bool
    init(failWrites: Bool = false) { self.failWrites = failWrites }
    func save(token: String, for id: UUID) throws {
        if failWrites { throw CredentialError(status: -1) }
        lock.withLock { values[id] = token }
    }
    func get(for id: UUID) throws -> String? { lock.withLock { values[id] } }
    func delete(for id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }
}

@MainActor
struct TestDefaults {
    let name = "AILimiterTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: name)! }
    func clear() { defaults.removePersistentDomain(forName: name) }
}

@Test @MainActor func metadataNeverEncodesCredentials() throws {
    let account = AccountCredential(provider: .chatgpt, title: "Work", token: "secret-fixture")
    let data = try JSONEncoder().encode([account])
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(json[0]["token"] == nil)
    #expect(!String(decoding: data, as: UTF8.self).contains("secret-fixture"))
}

@Test @MainActor func migratesLegacyCopiesAndKeepsAccountIdentity() throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let defaults = storage.defaults
    let credentials = MemoryCredentials()
    let account = AccountCredential(provider: .claude, title: "Work", token: "manual-fixture")
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([account])) as? [[String: Any]])
    json[0]["token"] = account.token
    defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: AccountRepository.accountsKey)
    defaults.set(account.token, forKey: "com.ailimiter.token.\(account.id.uuidString)")
    defaults.set(account.token, forKey: "sec_\(account.id.uuidString)")
    let repository = AccountRepository(defaults: defaults, credentials: credentials)
    let loaded = try #require(try repository.load())
    #expect(loaded == [account])
    #expect(try credentials.get(for: account.id) == account.token)
    #expect(defaults.string(forKey: "com.ailimiter.token.\(account.id.uuidString)") == nil)
    #expect(defaults.string(forKey: "sec_\(account.id.uuidString)") == nil)
    let cleaned = try #require(defaults.data(forKey: AccountRepository.accountsKey))
    #expect(!String(decoding: cleaned, as: UTF8.self).contains(account.token))
    #expect(try repository.load() == loaded)
}

@Test @MainActor func failedMigrationPreservesRecoverableLegacyData() throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let defaults = storage.defaults
    let account = AccountCredential(provider: .chatgpt, title: "Work", token: "fixture")
    let original = try JSONEncoder().encode([account])
    defaults.set(original, forKey: AccountRepository.accountsKey)
    let key = "sec_\(account.id.uuidString)"
    defaults.set(account.token, forKey: key)
    let repository = AccountRepository(defaults: defaults, credentials: MemoryCredentials(failWrites: true))
    #expect(throws: CredentialError.self) { try repository.load() }
    #expect(defaults.data(forKey: AccountRepository.accountsKey) == original)
    #expect(defaults.string(forKey: key) == account.token)
}

@Test @MainActor func repositoryPersistsAndDeletesSecretsSeparately() throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let defaults = storage.defaults
    let credentials = MemoryCredentials()
    let repository = AccountRepository(defaults: defaults, credentials: credentials)
    let account = AccountCredential(provider: .perplexity, title: "Personal", token: "fixture")
    try repository.save([account])
    #expect(try repository.load() == [account])
    try repository.remove(account.id, remainingAccounts: [])
    #expect(try credentials.get(for: account.id) == nil)
    #expect(try repository.load() == [])
}

@Test @MainActor func persistenceFailureIsVisibleAndDoesNotReplaceAccounts() {
    let storage = TestDefaults()
    defer { storage.clear() }
    let repository = AccountRepository(defaults: storage.defaults, credentials: MemoryCredentials(failWrites: true))
    let monitor = LimitMonitor(repository: repository, startAutomatically: false, notify: { _, _ in })
    #expect(monitor.storageError != nil)
    #expect(monitor.accounts.isEmpty)
    #expect(monitor.globalState == .error)
    #expect(!monitor.addAccount(AccountCredential(provider: .chatgpt, title: "Work", token: "fixture")))
}

@Test @MainActor func profileSelectionPersistsWithoutCopyingCredentialsIntoMetadata() throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let repository = AccountRepository(defaults: storage.defaults, credentials: MemoryCredentials())
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("selected-profile.json").path
    let account = AccountCredential(provider: .gemini, title: "Selected account", token: "auto", profilePath: path)
    try repository.save([account])
    #expect(try repository.load() == [account])
    let data = try #require(storage.defaults.data(forKey: AccountRepository.accountsKey))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(json[0]["profilePath"] as? String == path)
    #expect(json[0]["token"] == nil)
}

@Test func legacyAccountMetadataStillLoadsAndCustomTitlesStayIntact() throws {
    let account = AccountCredential(provider: .chatgpt, title: "ChatGPT", token: "auto")
    let data = try JSONEncoder().encode(account)
    let decoded = try JSONDecoder().decode(AccountCredential.self, from: data)
    #expect(decoded.profilePath == nil)
    #expect(decoded.displayTitle == "Codex")
    #expect(AIProvider.chatgpt.rawValue == "chatgpt")
    #expect(AIProvider.gemini.rawValue == "gemini")
    #expect(AIProvider.gemini.displayName == "Antigravity")
    let custom = AccountCredential(provider: .gemini, title: "Selected account", token: "auto")
    #expect(custom.displayTitle == "Selected account")
}
