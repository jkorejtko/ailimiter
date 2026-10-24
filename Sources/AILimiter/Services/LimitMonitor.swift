import SwiftUI
import Combine

@MainActor
public final class LimitMonitor: ObservableObject {
    public static let shared = LimitMonitor()

    @Published public var accounts: [AccountCredential] = []
    @Published public var statuses: [UUID: LimitStatus] = [:]
    @Published public var isRefreshing: Bool = false
    @Published public var lastRefreshTime: Date? = nil
    @Published public var refreshIntervalMinutes: Int = 10

    private var timer: AnyCancellable?
    private let accountsKey = "com.ailimiter.saved_accounts"
    private let intervalKey = "com.ailimiter.refresh_interval"

    public var globalState: LimitHealthState {
        let activeStatuses = accounts.filter { $0.isEnabled }.compactMap { statuses[$0.id] }
        if activeStatuses.contains(where: { $0.healthState == .exhausted }) {
            return .exhausted
        }
        if activeStatuses.contains(where: { $0.healthState == .warning }) {
            return .warning
        }
        if activeStatuses.contains(where: { $0.healthState == .error }) {
            return .error
        }
        return .normal
    }

    private init() {
        loadSettings()
        loadAccounts()
        setupTimer()
    }

    public func setupTimer() {
        timer?.cancel()
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.refreshAll()
                }
            }
    }

    public func setRefreshInterval(_ minutes: Int) {
        refreshIntervalMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: intervalKey)
        setupTimer()
    }

    private func loadSettings() {
        let savedInterval = UserDefaults.standard.integer(forKey: intervalKey)
        if savedInterval > 0 {
            refreshIntervalMinutes = savedInterval
        }
    }

    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([AccountCredential].self, from: data) {
            self.accounts = decoded.map { acc in
                var loaded = acc
                if let secToken = KeychainManager.shared.get(for: acc.id), !secToken.isEmpty {
                    loaded.token = secToken
                }
                return loaded
            }
        }

        // Pokud je seznam prázdný při prvním spuštění, vytvoříme ukázkové účty (demo)
        if accounts.isEmpty {
            createInitialDemoAccounts()
        }

        Task {
            await refreshAll()
        }
    }

    private func saveAccounts() {
        for acc in accounts {
            _ = KeychainManager.shared.save(token: acc.token, for: acc.id)
        }
        // Ukládáme metadata (bezpečný token je v Keychain)
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: accountsKey)
        }
    }

    private func createInitialDemoAccounts() {
        let demoChatGPT = AccountCredential(
            provider: .chatgpt,
            title: "Osobní ChatGPT Plus",
            token: "demo"
        )
        let demoClaude = AccountCredential(
            provider: .claude,
            title: "Claude Pro",
            token: "demo"
        )
        let demoGemini = AccountCredential(
            provider: .gemini,
            title: "Google AI Studio",
            token: "demo"
        )

        accounts = [demoChatGPT, demoClaude, demoGemini]
        saveAccounts()
    }

    public func addAccount(_ account: AccountCredential) {
        accounts.append(account)
        saveAccounts()
        Task {
            await refreshAccount(account)
        }
    }

    public func updateAccount(_ account: AccountCredential) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            saveAccounts()
            Task {
                await refreshAccount(account)
            }
        }
    }

    public func deleteAccount(id: UUID) {
        accounts.removeAll(where: { $0.id == id })
        statuses.removeValue(forKey: id)
        KeychainManager.shared.delete(for: id)
        saveAccounts()
    }

    public func toggleAccount(id: UUID) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            accounts[index].isEnabled.toggle()
            saveAccounts()
            if accounts[index].isEnabled {
                Task {
                    await refreshAccount(accounts[index])
                }
            }
        }
    }

    public func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        for account in accounts where account.isEnabled {
            await refreshAccount(account)
        }

        lastRefreshTime = Date()
        isRefreshing = false
    }

    public func refreshAccount(_ account: AccountCredential) async {
        let previousStatus = statuses[account.id]
        let newStatus: LimitStatus

        switch account.provider {
        case .chatgpt:
            newStatus = await ChatGPTService.shared.fetchLimitStatus(for: account)
        case .claude:
            newStatus = await ClaudeService.shared.fetchLimitStatus(for: account)
        case .gemini:
            newStatus = await GeminiService.shared.fetchLimitStatus(for: account)
        case .perplexity:
            newStatus = await PerplexityService.shared.fetchLimitStatus(for: account)
        }

        statuses[account.id] = newStatus

        // Pokud se reálný účet úspěšně spojí s API, automaticky odpojíme demo účty
        if !account.isDemo && newStatus.healthState != .error && !newStatus.isDemo {
            purgeDemoAccounts()
        }

        // Kontrola notifikací při přechodu stavů
        checkNotifications(oldStatus: previousStatus, newStatus: newStatus)
    }

    public func purgeDemoAccounts() {
        let demoAccounts = accounts.filter { $0.isDemo }
        guard !demoAccounts.isEmpty else { return }

        for demo in demoAccounts {
            statuses.removeValue(forKey: demo.id)
            KeychainManager.shared.delete(for: demo.id)
        }
        accounts.removeAll(where: { $0.isDemo })
        saveAccounts()
    }

    private func checkNotifications(oldStatus: LimitStatus?, newStatus: LimitStatus) {
        let oldState = oldStatus?.healthState ?? .normal

        if newStatus.healthState == .warning && oldState != .warning && oldState != .exhausted {
            NotificationService.shared.sendWarningNotification(
                provider: newStatus.provider,
                usagePercent: newStatus.usagePercentage
            )
        } else if newStatus.healthState == .exhausted && oldState != .exhausted {
            NotificationService.shared.sendExhaustedNotification(
                provider: newStatus.provider,
                resetInString: newStatus.resetCountdownString
            )
        } else if oldState == .exhausted && newStatus.healthState == .normal {
            NotificationService.shared.sendRestoredNotification(provider: newStatus.provider)
        }
    }
}
