import Foundation
import Testing
@testable import AILimiter

@MainActor
private final class FetchGate {
    var requests: [CheckedContinuation<LimitStatus, Never>] = []
    var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func fetch(_ account: AccountCredential) async -> LimitStatus {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
            if let waiter, requests.count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }
}

private func sampleStatus(_ account: AccountCredential, percent: Double) -> LimitStatus {
    UsageResponseParser.status(for: account, windows: [UsageWindow(id: "primary", kind: .session,
        label: "5h Session", usedPercent: percent)], plan: "Fixture")
}

@Test @MainActor func deletingAccountDiscardsInFlightResultAndNotification() async throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let repository = AccountRepository(defaults: storage.defaults, credentials: MemoryCredentials())
    let account = AccountCredential(provider: .chatgpt, title: "Work", token: "fixture")
    try repository.save([account])
    let gate = FetchGate()
    var notifications = 0
    let monitor = LimitMonitor(repository: repository, startAutomatically: false,
                               fetch: { await gate.fetch($0) }, notify: { _, _ in notifications += 1 })
    let task = Task { await monitor.refreshAccount(account) }
    await gate.waitForRequests(1)
    monitor.deleteAccount(id: account.id)
    gate.requests[0].resume(returning: sampleStatus(account, percent: 100))
    await task.value
    #expect(monitor.accounts.isEmpty)
    #expect(monitor.statuses[account.id] == nil)
    #expect(notifications == 0)
}

@Test @MainActor func duplicateRefreshDoesNotStartAnotherRequest() async throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let repository = AccountRepository(defaults: storage.defaults, credentials: MemoryCredentials())
    let account = AccountCredential(provider: .chatgpt, title: "Work", token: "fixture")
    try repository.save([account])
    let gate = FetchGate()
    let monitor = LimitMonitor(repository: repository, startAutomatically: false,
                               fetch: { await gate.fetch($0) }, notify: { _, _ in })
    let first = Task { await monitor.refreshAccount(account) }
    await gate.waitForRequests(1)
    #expect(monitor.generations[account.id] != nil)
    await monitor.refreshAccount(account)
    #expect(gate.requests.count == 1)
    gate.requests[0].resume(returning: sampleStatus(account, percent: 85))
    await first.value
    #expect(monitor.statuses[account.id]?.usagePercentage == 85)
    #expect(monitor.generations[account.id] == nil)
}

@Test @MainActor func failedRefreshKeepsTimestampAndMarksCachedData() async throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let repository = AccountRepository(defaults: storage.defaults, credentials: MemoryCredentials())
    let account = AccountCredential(provider: .claude, title: "Work", token: "fixture")
    try repository.save([account])
    let known = sampleStatus(account, percent: 45)
    let monitor = LimitMonitor(repository: repository, startAutomatically: false,
                               fetch: { .unavailable(for: $0, "HTTP 429") }, notify: { _, _ in Issue.record("Stale data must not notify") })
    monitor.statuses[account.id] = known
    await monitor.refreshAccount(account)
    let cached = try #require(monitor.statuses[account.id])
    #expect(cached.windows == known.windows)
    #expect(cached.lastChecked == known.lastChecked)
    #expect(cached.refreshError == "HTTP 429")
    #expect(monitor.globalState == .error)
}

@Test @MainActor func autoDiscoveryPreservesManualAccountsAndSecrets() throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let credentials = MemoryCredentials()
    let repository = AccountRepository(defaults: storage.defaults, credentials: credentials)
    let account = AccountCredential(provider: .claude, title: "Manual work account", token: "manual-fixture")
    try repository.save([account])
    let monitor = LimitMonitor(repository: repository, startAutomatically: false,
                               fetch: { .unavailable(for: $0, "Fixture") }, notify: { _, _ in })
    monitor.resetToAutoDetect()
    #expect(monitor.accounts.contains(account))
    #expect(try credentials.get(for: account.id) == account.token)
    #expect(monitor.accounts.count == 4)
    monitor.resetToAutoDetect()
    #expect(monitor.accounts.count == 4)
}

@Test @MainActor func enablingThenDeletingAnAccountDoesNotUseStaleIndex() async throws {
    let storage = TestDefaults()
    defer { storage.clear() }
    let repository = AccountRepository(defaults: storage.defaults, credentials: MemoryCredentials())
    let account = AccountCredential(provider: .claude, title: "Work", token: "fixture", isEnabled: false)
    try repository.save([account])
    let monitor = LimitMonitor(repository: repository, startAutomatically: false,
        fetch: { account in Issue.record("Deleted account must not be refreshed"); return .failure(for: account, "Fixture") }, notify: { _, _ in })
    monitor.toggleAccount(id: account.id)
    monitor.deleteAccount(id: account.id)
    await Task.yield()
    #expect(monitor.accounts.isEmpty)
    #expect(monitor.statuses.isEmpty)
}
