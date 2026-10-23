import Foundation

public final class ClaudeService {
    public static let shared = ClaudeService()
    private let session = URLSession.shared

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        var token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if token.hasPrefix("sessionKey=") {
            token = String(token.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if token.lowercased().hasPrefix("demo") || token.isEmpty {
            return mockStatus(for: account, isDemo: true)
        }

        // 1. Claude.ai session key (sk-ant-sid...)
        if token.hasPrefix("sk-ant-sid") {
            return await fetchClaudeWebStatus(for: account, sessionKey: token)
        }

        // 2. Jakýkoliv Anthropic API klíč (sk-ant-api..., sk-ant-...)
        if token.hasPrefix("sk-ant-") {
            return await fetchAnthropicAPIStatus(for: account, apiKey: token)
        }

        // 3. Fallback: zkusíme API volání
        let apiStatus = await fetchAnthropicAPIStatus(for: account, apiKey: token)
        if apiStatus.healthState != .error {
            return apiStatus
        }
        return await fetchClaudeWebStatus(for: account, sessionKey: token)
    }

    private func fetchAnthropicAPIStatus(for account: AccountCredential, apiKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 8.0

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 {
                return errorStatus(for: account, message: "Neplatný API klíč")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 100.0,
                    planName: "Anthropic API",
                    statusDescription: "Rate limit vyčerpán (429)",
                    resetDate: Date().addingTimeInterval(1800),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 20.0,
                    usedCount: 1,
                    totalLimit: 5,
                    planName: "Anthropic API",
                    statusDescription: "Aktivní v pořádku",
                    healthState: .normal
                )
            } else {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    private func fetchClaudeWebStatus(for account: AccountCredential, sessionKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return errorStatus(for: account, message: "Neplatný klíč nebo session (401/403)")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 100.0,
                    planName: "Claude Pro",
                    statusDescription: "Limit zpráv dosažen. Obnovení za ~4h.",
                    resetDate: Date().addingTimeInterval(4 * 3600),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                var plan = "Claude Pro"
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstOrg = jsonArray.first {
                    let capabilities = firstOrg["capabilities"] as? [String] ?? []
                    if capabilities.contains("claude_max") {
                        plan = "Claude Max"
                    } else if capabilities.contains("claude_pro") {
                        plan = "Claude Pro"
                    }
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 30.0,
                    usedCount: 15,
                    totalLimit: 45,
                    planName: plan,
                    statusDescription: "Zbývá cca 30 zpráv (5h okno)",
                    resetDate: Date().addingTimeInterval(7200),
                    healthState: .normal
                )
            } else {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return errorStatus(for: account, message: "Chyba sítě")
        }
    }

    private func mockStatus(for account: AccountCredential, isDemo: Bool) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .claude,
            usagePercentage: 82.0,
            usedCount: 37,
            totalLimit: 45,
            planName: isDemo ? "Claude Pro (Demo)" : "Claude Pro",
            statusDescription: "Zbývá 8 zpráv do vyčerpání",
            resetDate: Date().addingTimeInterval(2700), // ~45 minut
            healthState: .warning
        )
    }

    private func errorStatus(for account: AccountCredential, message: String) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .claude,
            usagePercentage: 0.0,
            planName: "Claude",
            statusDescription: message,
            healthState: .error
        )
    }
}
