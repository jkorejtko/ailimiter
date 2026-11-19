import SwiftUI
import Combine

@MainActor
public final class LimitMonitor: ObservableObject {
    public static let shared = LimitMonitor()

    @Published public var accounts: [AccountCredential] = []
    @Published public var statuses: [UUID: LimitStatus] = [:]
    @Published public var isRefreshing = false
    @Published public var lastRefreshTime: Date?
    @Published public var refreshIntervalMinutes = 10
    @Published public var storageError: String?

    private let repository: AccountRepository
    private let fetch: @MainActor (AccountCredential) async -> LimitStatus
    private let notify: @MainActor (LimitStatus?, LimitStatus) -> Void
    private var timer: AnyCancellable?
    @Published private(set) var generations: [UUID: UUID] = [:]
    private var storageAvailable = true
    private let intervalKey = "com.ailimiter.refresh_interval"

    init(repository: AccountRepository = AccountRepository(), startAutomatically: Bool = true,
         fetch: @escaping @MainActor (AccountCredential) async -> LimitStatus = LimitMonitor.fetchProvider,
         notify: @escaping @MainActor (LimitStatus?, LimitStatus) -> Void = LimitMonitor.sendNotifications) {
        self.repository = repository
        self.fetch = fetch
        self.notify = notify
        let saved = repository.defaults.integer(forKey: intervalKey)
        if [2, 5, 10, 30].contains(saved) { refreshIntervalMinutes = saved }
        loadAccounts()
        if startAutomatically {
            setupTimer()
            Task { await refreshAll() }
        }
    }

    public var globalState: LimitHealthState {
        if storageError != nil { return .error }
        let active = accounts.filter(\.isEnabled)
        if active.isEmpty { return .unavailable }
        let values = active.compactMap { statuses[$0.id] }
        if values.contains(where: { $0.healthState == .exhausted }) { return .exhausted }
        if values.contains(where: { $0.healthState == .warning }) { return .warning }
        if values.contains(where: { $0.healthState == .error || $0.refreshError != nil }) { return .error }
        if values.count < active.count || values.contains(where: { $0.healthState == .unavailable }) { return .unavailable }
        return .normal
    }

    private func loadAccounts() {
        do {
            if let saved = try repository.load() {
                accounts = saved
            } else {
                let initial = autoAccounts()
                try repository.save(initial)
                accounts = initial
            }
            storageAvailable = true
            storageError = nil
        } catch {
            storageAvailable = false
            storageError = "Účty nelze bezpečně načíst. Původní data zůstala zachována. \(error.localizedDescription)"
        }
    }

    public func retryStorage() {
        loadAccounts()
        if storageAvailable { Task { await refreshAll() } }
    }

    public func setupTimer() {
        timer?.cancel()
        timer = Timer.publish(every: TimeInterval(refreshIntervalMinutes * 60), on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in Task { await self?.refreshAll() } }
    }

    public func setRefreshInterval(_ minutes: Int) {
        guard [2, 5, 10, 30].contains(minutes) else { return }
        refreshIntervalMinutes = minutes
        repository.defaults.set(minutes, forKey: intervalKey)
        setupTimer()
    }

    private func autoAccounts() -> [AccountCredential] {
        [.chatgpt, .claude, .gemini].map {
            AccountCredential(provider: $0, title: $0.displayName, token: "auto")
        }
    }

    private func save(_ updated: [AccountCredential]) -> Bool {
        guard storageAvailable else { return false }
        do {
            try repository.save(updated)
            accounts = updated
            storageError = nil
            return true
        } catch {
            storageError = "Účet nebyl uložen. \(error.localizedDescription)"
            return false
        }
    }

    public func resetToAutoDetect() {
        // Add explicit local profiles without replacing manually configured accounts.
        let missing = autoAccounts().filter { candidate in
            !accounts.contains { $0.provider == candidate.provider && $0.token.lowercased() == "auto" && $0.profilePath == nil }
        }
        if save(accounts + missing) { Task { await refreshAll() } }
    }

    @discardableResult
    public func addAccount(_ account: AccountCredential) -> Bool {
        guard save(accounts + [account]) else { return false }
        Task { await refreshAccount(account) }
        return true
    }

    @discardableResult
    public func updateAccount(_ account: AccountCredential) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return false }
        var updated = accounts
        updated[index] = account
        guard save(updated) else { return false }
        generations.removeValue(forKey: account.id)
        statuses.removeValue(forKey: account.id)
        Task { await refreshAccount(account) }
        return true
    }

    public func deleteAccount(id: UUID) {
        guard storageAvailable else { return }
        do {
            let updated = accounts.filter { $0.id != id }
            try repository.remove(id, remainingAccounts: updated)
            accounts = updated
            generations.removeValue(forKey: id)
            statuses.removeValue(forKey: id)
            storageError = nil
        } catch {
            storageError = "Účet nebyl odebrán. \(error.localizedDescription)"
        }
    }

    public func toggleAccount(id: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = accounts
        updated[index].isEnabled.toggle()
        guard save(updated) else { return }
        generations.removeValue(forKey: id)
        let account = updated[index]
        if account.isEnabled { Task { await refreshAccount(account) } }
    }

    public func refreshAll() async {
        guard !isRefreshing, storageAvailable else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for account in accounts where account.isEnabled { await refreshAccount(account) }
        lastRefreshTime = Date()
    }

    public func refreshAccount(_ account: AccountCredential) async {
        guard storageAvailable, account.isEnabled, accounts.contains(account), generations[account.id] == nil else { return }
        let generation = UUID()
        generations[account.id] = generation
        defer {
            if generations[account.id] == generation { generations.removeValue(forKey: account.id) }
        }
        var result = await fetch(account)
        guard generations[account.id] == generation, accounts.contains(account), account.isEnabled else { return }
        let previous = statuses[account.id]
        if !result.hasUsageData, var cached = previous, cached.hasUsageData, !cached.isDemo {
            cached.refreshError = result.statusDescription
            result = cached
        }
        statuses[account.id] = result
        if result.hasUsageData, result.refreshError == nil, !result.isDemo { notify(previous, result) }
    }

    private static func fetchProvider(_ account: AccountCredential) async -> LimitStatus {
        switch account.provider {
        case .chatgpt: return await ChatGPTService.shared.fetchLimitStatus(for: account)
        case .claude: return await ClaudeService.shared.fetchLimitStatus(for: account)
        case .gemini: return await GeminiService.shared.fetchLimitStatus(for: account)
        case .perplexity: return await PerplexityService.shared.fetchLimitStatus(for: account)
        }
    }

    private static func sendNotifications(_ previous: LimitStatus?, _ current: LimitStatus) {
        let oldState = previous?.healthState
        if current.healthState == .warning && oldState != .warning && oldState != .exhausted {
            NotificationService.shared.sendWarningNotification(provider: current.provider, usagePercent: current.usagePercentage)
        } else if current.healthState == .exhausted && oldState != .exhausted {
            NotificationService.shared.sendExhaustedNotification(provider: current.provider, detail: current.statusDescription, resetInString: current.resetCountdownString)
        } else if oldState == .exhausted && current.healthState == .normal {
            NotificationService.shared.sendRestoredNotification(provider: current.provider)
        }
    }
}
