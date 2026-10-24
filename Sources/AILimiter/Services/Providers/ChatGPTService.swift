import Foundation

public final class ChatGPTService: @unchecked Sendable {
    public static let shared = ChatGPTService()
    private let session = URLSession.shared

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        var token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if token.hasPrefix("__Secure-next-auth.session-token=") {
            token = String(token.dropFirst(33)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if token.isEmpty {
            return errorStatus(for: account, message: "Není zadán token")
        }

        if token.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        // 1. Varianta: OpenAI API Key (sk-...)
        if token.hasPrefix("sk-") && !token.hasPrefix("sk-ant-") {
            return await fetchOpenAIAPIStatus(for: account, apiKey: token)
        }

        // 2. Varianta: ChatGPT Session Token nebo Access Token (Web)
        return await fetchChatGPTWebStatus(for: account, rawToken: token)
    }

    private func fetchOpenAIAPIStatus(for account: AccountCredential, apiKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď serveru")
            }

            if httpResponse.statusCode == 401 {
                return errorStatus(for: account, message: "Neplatný API klíč")
            } else if httpResponse.statusCode == 429 {
                let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset-requests")
                var resetDate: Date? = nil
                if let resetSec = resetHeader.flatMap(Double.init) {
                    resetDate = Date().addingTimeInterval(resetSec)
                } else {
                    resetDate = Date().addingTimeInterval(3600)
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .chatgpt,
                    usagePercentage: 100.0,
                    planName: "OpenAI API",
                    statusDescription: "Rate limit vyčerpán (429)",
                    resetDate: resetDate,
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                let remainingHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining-requests")
                let limitHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-limit-requests")

                if let rem = remainingHeader.flatMap(Int.init), let lim = limitHeader.flatMap(Int.init), lim > 0 {
                    let used = max(0, lim - rem)
                    let percentage = min(100.0, max(0.0, Double(used) / Double(lim) * 100.0))
                    let health: LimitHealthState = percentage >= 100.0 ? .exhausted : (percentage >= 80.0 ? .warning : .normal)

                    return LimitStatus(
                        accountId: account.id,
                        provider: .chatgpt,
                        usagePercentage: percentage,
                        usedCount: used,
                        totalLimit: lim,
                        planName: "OpenAI API",
                        statusDescription: "\(used)/\(lim) req/min (\(rem) zbývá)",
                        healthState: health
                    )
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .chatgpt,
                    usagePercentage: 0.0,
                    planName: "OpenAI API",
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

    private func fetchChatGPTWebStatus(for account: AccountCredential, rawToken: String) async -> LimitStatus {
        var accessToken = rawToken

        // Pokud token nezačíná na eyJ (JWT access token), jde pravděpodobně o session token.
        // Zkusíme vyměnit session token za access token přes /api/auth/session.
        if !rawToken.hasPrefix("ey") {
            if let fetchedToken = await exchangeSessionTokenForAccessToken(rawToken) {
                accessToken = fetchedToken
            }
        }

        // 1. Zkusíme oficiální interní /backend-api/wham/usage endpoint, který vrací reálnou kvótu
        if let liveStatus = await fetchWhamUsage(for: account, accessToken: accessToken, sessionCookie: rawToken) {
            return liveStatus
        }

        // 2. Fallback na /backend-api/me pro ověření platnosti session
        return await fetchMeFallback(for: account, accessToken: accessToken)
    }

    private func exchangeSessionTokenForAccessToken(_ sessionToken: String) async -> String? {
        guard let url = URL(string: "https://chatgpt.com/api/auth/session") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("__Secure-next-auth.session-token=\(sessionToken)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 7.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["accessToken"] as? String, !token.isEmpty {
                return token
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fetchWhamUsage(for account: AccountCredential, accessToken: String, sessionCookie: String) async -> LimitStatus? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("__Secure-next-auth.session-token=\(sessionCookie)", forHTTPHeaderField: "Cookie")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .chatgpt,
                    usagePercentage: 100.0,
                    planName: "ChatGPT Plus",
                    statusDescription: "Rate limit vyčerpán (429)",
                    resetDate: Date().addingTimeInterval(3 * 3600),
                    healthState: .exhausted
                )
            }

            guard httpResponse.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let planType = (json["plan_type"] as? String)?.capitalized ?? "Plus"
                let planName = "ChatGPT \(planType)"

                if let rateLimit = json["rate_limit"] as? [String: Any],
                   let primaryWindow = rateLimit["primary_window"] as? [String: Any] {
                    var usedPercent = primaryWindow["used_percent"] as? Double ?? 0.0
                    let remainingPercent = primaryWindow["remaining_percent"] as? Double
                    let resetsAtSec = primaryWindow["resets_at"] as? Double

                    var resetDate: Date? = nil
                    if let resetsAtSec = resetsAtSec, resetsAtSec > 0 {
                        resetDate = Date(timeIntervalSince1970: resetsAtSec)
                    }

                    if usedPercent <= 1.0 && usedPercent > 0.0 && (remainingPercent ?? 0) <= 1.0 {
                        usedPercent *= 100.0
                    }

                    let health: LimitHealthState = usedPercent >= 100.0 ? .exhausted : (usedPercent >= 80.0 ? .warning : .normal)
                    let desc: String
                    if usedPercent >= 100.0 {
                        desc = "Limit zpráv vyčerpán"
                    } else if let rem = remainingPercent {
                        let remVal = rem <= 1.0 ? Int(rem * 100.0) : Int(rem)
                        desc = "Zbývá \(remVal)% kapacity okna"
                    } else {
                        desc = "Využito \(Int(usedPercent))% okna"
                    }

                    return LimitStatus(
                        accountId: account.id,
                        provider: .chatgpt,
                        usagePercentage: usedPercent,
                        planName: planName,
                        statusDescription: desc,
                        resetDate: resetDate,
                        healthState: health
                    )
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func fetchMeFallback(for account: AccountCredential, accessToken: String) async -> LimitStatus {
        guard let url = URL(string: "https://chatgpt.com/backend-api/me") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return errorStatus(for: account, message: "Expirovaný token / neplatná session")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .chatgpt,
                    usagePercentage: 100.0,
                    planName: "ChatGPT Plus",
                    statusDescription: "Zprávy vyčerpány. Obnovení za ~3 hodiny.",
                    resetDate: Date().addingTimeInterval(3 * 3600),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                var plan = "ChatGPT Plus"
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let email = json["email"] as? String {
                    plan = "ChatGPT (\(email))"
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .chatgpt,
                    usagePercentage: 0.0,
                    planName: plan,
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
            provider: .chatgpt,
            usagePercentage: 45.0,
            usedCount: 18,
            totalLimit: 40,
            planName: "ChatGPT Plus [DEMO]",
            statusDescription: "Simulace: zadejte reálný token pro živá data",
            resetDate: Date().addingTimeInterval(4200),
            healthState: .normal,
            isDemo: true
        )
    }

    private func errorStatus(for account: AccountCredential, message: String) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .chatgpt,
            usagePercentage: 0.0,
            planName: "ChatGPT",
            statusDescription: message,
            healthState: .error
        )
    }
}
