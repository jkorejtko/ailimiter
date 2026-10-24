import Foundation

public final class ClaudeService: @unchecked Sendable {
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

        if token.isEmpty {
            return errorStatus(for: account, message: "Není zadán session klíč")
        }

        if token.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        // 1. Claude.ai session key (sk-ant-sid...)
        if token.hasPrefix("sk-ant-sid") {
            return await fetchClaudeWebStatus(for: account, sessionKey: token)
        }

        // 2. Jakýkoliv Anthropic API klíč (sk-ant-api..., sk-ant-...)
        if token.hasPrefix("sk-ant-") {
            return await fetchAnthropicAPIStatus(for: account, apiKey: token)
        }

        // 3. Fallback: zkusíme API volání a pak web
        let apiStatus = await fetchAnthropicAPIStatus(for: account, apiKey: token)
        if apiStatus.healthState != .error {
            return apiStatus
        }
        return await fetchClaudeWebStatus(for: account, sessionKey: token)
    }

    private func fetchAnthropicAPIStatus(for account: AccountCredential, apiKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 {
                return errorStatus(for: account, message: "Neplatný API klíč")
            } else if httpResponse.statusCode == 400 {
                // Zkontrolujeme, zda jde o nedostatek kreditu
                var isBalanceExhausted = false
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any] {
                    let msg = errorObj["message"] as? String ?? ""
                    if msg.lowercased().contains("credit balance is too low") || msg.lowercased().contains("purchase credits") {
                        isBalanceExhausted = true
                    }
                }

                if isBalanceExhausted {
                    return LimitStatus(
                        accountId: account.id,
                        provider: .claude,
                        usagePercentage: 100.0,
                        planName: "Anthropic Console API",
                        statusDescription: "Kredit vyčerpán (nulový zůstatek v Console)",
                        healthState: .exhausted
                    )
                }

                return errorStatus(for: account, message: "HTTP 400 (Chyba požadavku)")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 100.0,
                    planName: "Anthropic Console API",
                    statusDescription: "Rate limit vyčerpán (429)",
                    resetDate: Date().addingTimeInterval(1800),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                let remainingHeader = httpResponse.value(forHTTPHeaderField: "anthropic-ratelimit-requests-remaining")
                let limitHeader = httpResponse.value(forHTTPHeaderField: "anthropic-ratelimit-requests-limit")

                if let rem = remainingHeader.flatMap(Int.init), let lim = limitHeader.flatMap(Int.init), lim > 0 {
                    let used = max(0, lim - rem)
                    let pct = min(100.0, max(0.0, Double(used) / Double(lim) * 100.0))
                    let health: LimitHealthState = pct >= 100.0 ? .exhausted : (pct >= 80.0 ? .warning : .normal)

                    return LimitStatus(
                        accountId: account.id,
                        provider: .claude,
                        usagePercentage: pct,
                        usedCount: used,
                        totalLimit: lim,
                        planName: "Anthropic Console API",
                        statusDescription: "\(used)/\(lim) req/min (\(rem) zbývá)",
                        healthState: health
                    )
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 0.0,
                    planName: "Anthropic Console API",
                    statusDescription: "Klíč aktivní (kredit k dispozici)",
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
        guard let orgsUrl = URL(string: "https://claude.ai/api/organizations") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var orgsRequest = URLRequest(url: orgsUrl)
        orgsRequest.httpMethod = "GET"
        orgsRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        orgsRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        orgsRequest.timeoutInterval = 8.0

        do {
            let (orgsData, orgsResponse) = try await session.data(for: orgsRequest)
            guard let httpResponse = orgsResponse as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return errorStatus(for: account, message: "Expirovaný session key (401/403)")
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
            } else if httpResponse.statusCode != 200 {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }

            var plan = "Claude Pro"
            var orgId: String? = nil

            if let jsonArray = try? JSONSerialization.jsonObject(with: orgsData) as? [[String: Any]],
               let firstOrg = jsonArray.first {
                orgId = firstOrg["uuid"] as? String
                let capabilities = firstOrg["capabilities"] as? [String] ?? []
                if capabilities.contains("claude_max") {
                    plan = "Claude Max"
                } else if capabilities.contains("claude_pro") {
                    plan = "Claude Pro"
                } else {
                    plan = "Claude Free"
                }
            }

            // Krok 2: Pokud máme orgId, zavoláme reálný usage endpoint
            if let orgId = orgId,
               let usageUrl = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage?cedar_ember=1") {
                var usageRequest = URLRequest(url: usageUrl)
                usageRequest.httpMethod = "GET"
                usageRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
                usageRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                usageRequest.timeoutInterval = 8.0

                if let (usageData, usageResponse) = try? await session.data(for: usageRequest),
                   let usageHttp = usageResponse as? HTTPURLResponse, usageHttp.statusCode == 200 {
                    if let usageJson = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any] {
                        if let fiveHour = usageJson["five_hour"] as? [String: Any] {
                            var util = fiveHour["utilization"] as? Double ?? 0.0
                            if util <= 1.0 && util > 0.0 {
                                util *= 100.0
                            }
                            util = min(100.0, max(0.0, util))

                            var resetDate: Date? = nil
                            if let resetStr = fiveHour["resets_at"] as? String {
                                let iso = ISO8601DateFormatter()
                                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                resetDate = iso.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
                            }

                            let health: LimitHealthState = util >= 100.0 ? .exhausted : (util >= 80.0 ? .warning : .normal)
                            let desc: String
                            if util >= 100.0 {
                                desc = "Limit zpráv 5h okna vyčerpán"
                            } else {
                                desc = "5h okno: \(Int(util))% vyčerpáno (zbývá \(100 - Int(util))%)"
                            }

                            return LimitStatus(
                                accountId: account.id,
                                provider: .claude,
                                usagePercentage: util,
                                planName: plan,
                                statusDescription: desc,
                                resetDate: resetDate,
                                healthState: health
                            )
                        }
                    }
                }
            }

            // Fallback pokud usage endpoint nevrátil five_hour
            return LimitStatus(
                accountId: account.id,
                provider: .claude,
                usagePercentage: 0.0,
                planName: plan,
                statusDescription: "Aktivní session (v pořádku)",
                healthState: .normal
            )

        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    private func mockStatus(for account: AccountCredential) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .claude,
            usagePercentage: 82.0,
            usedCount: 37,
            totalLimit: 45,
            planName: "Claude Pro [DEMO]",
            statusDescription: "Simulace: zadejte reálný sessionKey",
            resetDate: Date().addingTimeInterval(2700),
            healthState: .warning,
            isDemo: true
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
