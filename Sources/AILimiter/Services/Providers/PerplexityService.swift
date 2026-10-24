import Foundation

public final class PerplexityService: @unchecked Sendable {
    public static let shared = PerplexityService()
    private let session = URLSession.shared

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if token.isEmpty {
            return errorStatus(for: account, message: "Není zadán klíč ani cookie")
        }

        if token.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        // 1. Varianta: API Klíč (pplx-...)
        if token.hasPrefix("pplx-") {
            return await fetchPerplexityAPIStatus(for: account, apiKey: token)
        }

        // 2. Varianta: Session Cookie
        return await fetchPerplexityWebStatus(for: account, cookieString: token)
    }

    private func fetchPerplexityAPIStatus(for account: AccountCredential, apiKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://api.perplexity.ai/models") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 {
                return errorStatus(for: account, message: "Neplatný Perplexity API klíč")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .perplexity,
                    usagePercentage: 100.0,
                    planName: "Perplexity API",
                    statusDescription: "Rate limit vyčerpán (429)",
                    resetDate: Date().addingTimeInterval(3600),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .perplexity,
                    usagePercentage: 0.0,
                    planName: "Perplexity API",
                    statusDescription: "Aktivní API klíč (v pořádku)",
                    healthState: .normal
                )
            } else {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    private func fetchPerplexityWebStatus(for account: AccountCredential, cookieString: String) async -> LimitStatus {
        guard let url = URL(string: "https://www.perplexity.ai/rest/rate-limit/all") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var cookieHeader = cookieString
        if !cookieHeader.contains("=") {
            cookieHeader = "session-token=\(cookieString)"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return errorStatus(for: account, message: "Expirovaná session (přihlaste se znovu)")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .perplexity,
                    usagePercentage: 100.0,
                    planName: "Perplexity Pro",
                    statusDescription: "Denní Pro dotazy vyčerpány (429)",
                    resetDate: Date().addingTimeInterval(3600 * 4),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                // Pokus o rozparsování limitů z rate-limit/all
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Může obsahovat pro_search nebo default limit
                    if let proSearch = json["pro_search"] as? [String: Any] ?? json["copilot"] as? [String: Any] {
                        let remaining = proSearch["remaining"] as? Int
                        let limit = proSearch["limit"] as? Int ?? 300

                        if let rem = remaining {
                            let used = max(0, limit - rem)
                            let pct = min(100.0, max(0.0, Double(used) / Double(limit) * 100.0))
                            let health: LimitHealthState = pct >= 100.0 ? .exhausted : (pct >= 80.0 ? .warning : .normal)

                            return LimitStatus(
                                accountId: account.id,
                                provider: .perplexity,
                                usagePercentage: pct,
                                usedCount: used,
                                totalLimit: limit,
                                planName: "Perplexity Pro",
                                statusDescription: "\(rem) Pro dotazů zbývá dnes",
                                healthState: health
                            )
                        }
                    }
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .perplexity,
                    usagePercentage: 0.0,
                    planName: "Perplexity Pro",
                    statusDescription: "Aktivní session (v pořádku)",
                    healthState: .normal
                )
            } else {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    private func mockStatus(for account: AccountCredential) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .perplexity,
            usagePercentage: 15.0,
            usedCount: 45,
            totalLimit: 300,
            planName: "Perplexity Pro [DEMO]",
            statusDescription: "Simulace: zadejte reálný API klíč nebo cookie",
            healthState: .normal,
            isDemo: true
        )
    }

    private func errorStatus(for account: AccountCredential, message: String) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .perplexity,
            usagePercentage: 0.0,
            planName: "Perplexity",
            statusDescription: message,
            healthState: .error
        )
    }
}
