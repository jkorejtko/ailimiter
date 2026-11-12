import Foundation
import Security

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

        // 1. Zkusíme automaticky načíst Claude Code OAuth token z Keychain nebo lokální konfigurace
        if token.isEmpty || token.lowercased() == "auto" || token.lowercased() == "demo" {
            if let localToken = loadLocalClaudeToken() {
                token = localToken
            }
        }

        if token.isEmpty {
            return errorStatus(for: account, message: "Není zadán token ani nalezen Claude Code v Keychain")
        }

        if token.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        // 2. Claude OAuth token (začíná např. sk-ant-oat... nebo načtený z Claude Code)
        if token.hasPrefix("sk-ant-oat") || token.count > 60 && !token.hasPrefix("sk-ant-sid") && !token.hasPrefix("sk-ant-api") {
            let oauthStatus = await fetchClaudeOAuthStatus(for: account, token: token)
            if oauthStatus.healthState != .error {
                return oauthStatus
            }
        }

        // 3. Claude.ai session key (sk-ant-sid...)
        if token.hasPrefix("sk-ant-sid") {
            return await fetchClaudeWebStatus(for: account, sessionKey: token)
        }

        // 4. Anthropic API klíč (sk-ant-api...)
        if token.hasPrefix("sk-ant-") {
            return await fetchAnthropicAPIStatus(for: account, apiKey: token)
        }

        // 5. Fallback: zkusíme nejdřív OAuth, pak Web, pak API
        let oauthAttempt = await fetchClaudeOAuthStatus(for: account, token: token)
        if oauthAttempt.healthState != .error {
            return oauthAttempt
        }

        let webAttempt = await fetchClaudeWebStatus(for: account, sessionKey: token)
        if webAttempt.healthState != .error {
            return webAttempt
        }

        let apiAttempt = await fetchAnthropicAPIStatus(for: account, apiKey: token)
        if apiAttempt.healthState != .error {
            return apiAttempt
        }

        // 6. Pokud manuální token selhal, zkusíme ještě načíst lokální Claude Code z Keychain/config
        if let localToken = loadLocalClaudeToken(), localToken != token {
            let localOauth = await fetchClaudeOAuthStatus(for: account, token: localToken)
            if localOauth.healthState != .error {
                return localOauth
            }
        }

        return webAttempt.healthState == .error ? webAttempt : apiAttempt
    }

    private func loadLocalClaudeToken() -> String? {
        // A) Zkusíme načíst z macOS Keychain ("Claude Code-credentials")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let secStatus = SecItemCopyMatching(query as CFDictionary, &item)
        if secStatus == errSecSuccess, let data = item as? Data {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let claudeAiOauth = json["claudeAiOauth"] as? [String: Any],
                   let tok = claudeAiOauth["accessToken"] as? String, !tok.isEmpty {
                    return tok
                }
                if let tok = json["accessToken"] as? String, !tok.isEmpty {
                    return tok
                }
            } else if let tokenStr = String(data: data, encoding: .utf8), !tokenStr.isEmpty {
                return tokenStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // B) Zkusíme ~/.claude/.credentials.json
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credsUrl = home.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: credsUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let claudeAiOauth = json["claudeAiOauth"] as? [String: Any],
           let tok = claudeAiOauth["accessToken"] as? String, !tok.isEmpty {
            return tok
        }

        return nil
    }

    // MARK: - T3 Code Official OAuth Usage Endpoint

    private func fetchClaudeOAuthStatus(for account: AccountCredential, token: String) async -> LimitStatus {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // Kritické: bez tohoto User-Agentu vrací Anthropic 429!
        request.setValue("claude-code/2.1.273", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď serveru")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return errorStatus(for: account, message: "Neplatný nebo expirovaný Claude OAuth token")
            } else if httpResponse.statusCode != 200 && httpResponse.statusCode != 429 {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return errorStatus(for: account, message: "Chyba parsování JSON z Anthropic")
            }

            var windows: [UsageWindow] = []
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // 1. 5h Session Window
            if let fiveHour = json["five_hour"] as? [String: Any],
               let util = (fiveHour["utilization"] as? Double) ?? (fiveHour["utilization"] as? Int).map(Double.init) {
                var resetDate: Date? = nil
                if let resetStr = fiveHour["resets_at"] as? String {
                    resetDate = isoFormatter.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
                }
                windows.append(UsageWindow(
                    id: "five_hour",
                    kind: .session,
                    label: "5h Session",
                    usedPercent: util,
                    resetsAt: resetDate,
                    windowDurationMins: 300
                ))
            }

            // 2. 7-Day Weekly Window
            if let sevenDay = json["seven_day"] as? [String: Any],
               let util = (sevenDay["utilization"] as? Double) ?? (sevenDay["utilization"] as? Int).map(Double.init) {
                var resetDate: Date? = nil
                if let resetStr = sevenDay["resets_at"] as? String {
                    resetDate = isoFormatter.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
                }
                windows.append(UsageWindow(
                    id: "seven_day",
                    kind: .weekly,
                    label: "Týdenní limit",
                    usedPercent: util,
                    resetsAt: resetDate,
                    windowDurationMins: 10080
                ))
            }

            // 3. Model-scoped limits (např. Weekly · Claude 3.5 Sonnet)
            if let limitsArray = json["limits"] as? [[String: Any]] {
                for limit in limitsArray {
                    if let kindStr = limit["kind"] as? String, kindStr == "weekly_scoped",
                       let percent = (limit["percent"] as? Double) ?? (limit["percent"] as? Int).map(Double.init),
                       let scope = limit["scope"] as? [String: Any],
                       let model = scope["model"] as? [String: Any],
                       let displayName = model["display_name"] as? String {
                        var resetDate: Date? = nil
                        if let resetStr = limit["resets_at"] as? String {
                            resetDate = isoFormatter.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
                        }
                        windows.append(UsageWindow(
                            id: "scoped_\(displayName.lowercased())",
                            kind: .weekly,
                            label: "Týdenní · \(displayName)",
                            usedPercent: percent,
                            resetsAt: resetDate,
                            windowDurationMins: 10080
                        ))
                    }
                }
            }

            let highestUsed = windows.map { $0.usedPercent }.max() ?? 0.0
            let sessionWindow = windows.first(where: { $0.kind == .session }) ?? windows.first

            let health: LimitHealthState
            if httpResponse.statusCode == 429 || highestUsed >= 100.0 {
                health = .exhausted
            } else if highestUsed >= 80.0 {
                health = .warning
            } else {
                health = .normal
            }

            let desc: String
            if health == .exhausted {
                desc = "Limit zpráv vyčerpán"
            } else if let pace = sessionWindow?.pace {
                desc = pace.label
            } else {
                desc = "Aktivní v normě"
            }

            return LimitStatus(
                accountId: account.id,
                provider: .claude,
                usagePercentage: highestUsed,
                planName: "Claude Subscription",
                statusDescription: desc,
                resetDate: sessionWindow?.resetsAt,
                healthState: health,
                isDemo: false,
                windows: windows
            )
        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    // MARK: - Claude.ai Web Scraping Fallback

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
                        var windows: [UsageWindow] = []

                        if let fiveHour = usageJson["five_hour"] as? [String: Any],
                           let rawUtil = (fiveHour["utilization"] as? Double) ?? (fiveHour["utilization"] as? Int).map(Double.init) {
                            let util = min(100.0, max(0.0, rawUtil))
                            var resetDate: Date? = nil
                            if let resetStr = fiveHour["resets_at"] as? String {
                                let iso = ISO8601DateFormatter()
                                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                resetDate = iso.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
                            }

                            windows.append(UsageWindow(
                                id: "five_hour",
                                kind: .session,
                                label: "5h Session",
                                usedPercent: util,
                                resetsAt: resetDate,
                                windowDurationMins: 300
                            ))

                            let health: LimitHealthState = util >= 100.0 ? .exhausted : (util >= 80.0 ? .warning : .normal)
                            return LimitStatus(
                                accountId: account.id,
                                provider: .claude,
                                usagePercentage: util,
                                planName: plan,
                                statusDescription: util >= 100.0 ? "Limit 5h okna vyčerpán" : "5h plovoucí okno zpráv",
                                resetDate: resetDate,
                                healthState: health,
                                windows: windows
                            )
                        }
                    }
                }
            }

            return LimitStatus(
                accountId: account.id,
                provider: .claude,
                usagePercentage: 0.0,
                planName: plan,
                statusDescription: "Údaje o limitu nedostupné",
                healthState: .normal
            )

        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    // MARK: - Anthropic Console API Key Fallback

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
                        statusDescription: "\(used)/\(lim) req/min",
                        healthState: health
                    )
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .claude,
                    usagePercentage: 0.0,
                    planName: "Anthropic Console API",
                    statusDescription: "Klíč aktivní (v pořádku)",
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
        let sessionWindow = UsageWindow(
            id: "five_hour",
            kind: .session,
            label: "5h Session",
            usedPercent: 82.0,
            resetsAt: Date().addingTimeInterval(2700),
            windowDurationMins: 300
        )
        let weeklyWindow = UsageWindow(
            id: "seven_day",
            kind: .weekly,
            label: "Týdenní limit",
            usedPercent: 44.0,
            resetsAt: Date().addingTimeInterval(86400 * 2),
            windowDurationMins: 10080
        )
        return LimitStatus(
            accountId: account.id,
            provider: .claude,
            usagePercentage: 82.0,
            planName: "Claude Pro [DEMO]",
            statusDescription: "Simulace: přihlašte se v Claude Code CLI",
            resetDate: Date().addingTimeInterval(2700),
            healthState: .warning,
            isDemo: true,
            windows: [sessionWindow, weeklyWindow]
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
