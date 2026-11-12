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

        var accountId: String? = nil

        // 1. Zkusíme automaticky načíst token z lokálního Codex profilu (~/.codex/auth.json), pokud token chybí nebo je "auto"
        if token.isEmpty || token.lowercased() == "auto" || token.lowercased() == "demo" {
            if let localAuth = loadLocalCodexAuth() {
                token = localAuth.token
                accountId = localAuth.accountId
            }
        }

        if token.isEmpty {
            return errorStatus(for: account, message: "Není zadán token ani nalezen ~/.codex/auth.json")
        }

        if token.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        // 2. OpenAI Platform API Key (sk-...)
        if token.hasPrefix("sk-") && !token.hasPrefix("sk-ant-") {
            return await fetchOpenAIAPIStatus(for: account, apiKey: token)
        }

        // 3. ChatGPT / Codex backend endpoint (/backend-api/wham/usage)
        return await fetchChatGPTWebStatus(for: account, rawToken: token, explicitAccountId: accountId)
    }

    private func loadLocalCodexAuth() -> (token: String, accountId: String?)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authPath = home.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else {
            return nil
        }
        let accountId = tokens["account_id"] as? String
        return (token: accessToken, accountId: accountId)
    }

    private func fetchChatGPTWebStatus(for account: AccountCredential, rawToken: String, explicitAccountId: String?) async -> LimitStatus {
        var accessToken = rawToken

        // Pokud token nezačíná na eyJ (JWT access token), může jít o session cookie
        if !rawToken.hasPrefix("ey") {
            if let fetchedToken = await exchangeSessionTokenForAccessToken(rawToken) {
                accessToken = fetchedToken
            }
        }

        // 1. Primárně zkusíme oficiální T3 Code endpoint: /backend-api/wham/usage se zadaným tokenem
        if let liveStatus = await fetchWhamUsage(for: account, accessToken: accessToken, sessionCookie: rawToken, accountId: explicitAccountId) {
            return liveStatus
        }

        // 2. Pokud zadaný token selhal (např. expiroval), automaticky zkusíme živý lokální Codex auth (~/.codex/auth.json)!
        if let localAuth = loadLocalCodexAuth(), localAuth.token != accessToken {
            if let liveStatus = await fetchWhamUsage(for: account, accessToken: localAuth.token, sessionCookie: "", accountId: localAuth.accountId) {
                return liveStatus
            }
        }

        // 3. Fallback na /backend-api/me
        let meStatus = await fetchMeFallback(for: account, accessToken: accessToken)
        if meStatus.healthState != .error {
            return meStatus
        }

        // 4. Pokud i to selhalo, zkusíme ještě jednou lokální Codex jako záchranu
        if let localAuth = loadLocalCodexAuth() {
            if let liveStatus = await fetchWhamUsage(for: account, accessToken: localAuth.token, sessionCookie: "", accountId: localAuth.accountId) {
                return liveStatus
            }
        }

        return meStatus
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

    private func fetchWhamUsage(for account: AccountCredential, accessToken: String, sessionCookie: String, accountId: String?) async -> LimitStatus? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if sessionCookie.hasPrefix("__Secure") || !sessionCookie.hasPrefix("ey") {
            request.setValue("__Secure-next-auth.session-token=\(sessionCookie)", forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "Originator")
        if let accountId = accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "Chatgpt-Account-Id")
        }
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return nil
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 429 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let planType = (json["plan_type"] as? String)?.capitalized ?? "Plus"
            let email = json["email"] as? String
            let planName = (email != nil) ? "ChatGPT \(planType) (\(email!))" : "ChatGPT \(planType)"

            var windows: [UsageWindow] = []
            var isLimitReached = false

            if let rateLimit = json["rate_limit"] as? [String: Any] {
                if let reached = rateLimit["limit_reached"] as? Bool, reached {
                    isLimitReached = true
                }

                // 1. Primary window (5h Session nebo Monthly pro free)
                if let primary = rateLimit["primary_window"] as? [String: Any] {
                    var used = (primary["used_percent"] as? Double)
                        ?? Double(primary["used_percent"] as? Int ?? 0)
                    let resetSec = (primary["reset_at"] as? Double)
                        ?? (primary["resets_at"] as? Double)
                        ?? (primary["reset_at"] as? Int).map(Double.init)
                        ?? (primary["resets_at"] as? Int).map(Double.init)
                    let windowSec = (primary["limit_window_seconds"] as? Int) ?? 18000
                    let durationMins = windowSec / 60

                    var resetDate: Date? = nil
                    if let resetSec = resetSec, resetSec > 0 {
                        resetDate = Date(timeIntervalSince1970: resetSec)
                    }

                    if used <= 1.0 && used > 0.0 {
                        used *= 100.0
                    }

                    let kind: WindowKind = durationMins >= 43200 ? .monthly : (durationMins >= 10080 ? .weekly : .session)
                    let label = kind == .session ? "5h Session" : (kind == .weekly ? "Týdenní" : "Měsíční")

                    windows.append(UsageWindow(
                        id: "primary",
                        kind: kind,
                        label: label,
                        usedPercent: used,
                        resetsAt: resetDate,
                        windowDurationMins: durationMins
                    ))
                }

                // 2. Secondary window (týdenní limit 7d)
                if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                    var used = (secondary["used_percent"] as? Double)
                        ?? Double(secondary["used_percent"] as? Int ?? 0)
                    let resetSec = (secondary["reset_at"] as? Double)
                        ?? (secondary["resets_at"] as? Double)
                        ?? (secondary["reset_at"] as? Int).map(Double.init)
                        ?? (secondary["resets_at"] as? Int).map(Double.init)
                    let windowSec = (secondary["limit_window_seconds"] as? Int) ?? 604800
                    let durationMins = windowSec / 60

                    var resetDate: Date? = nil
                    if let resetSec = resetSec, resetSec > 0 {
                        resetDate = Date(timeIntervalSince1970: resetSec)
                    }

                    if used <= 1.0 && used > 0.0 {
                        used *= 100.0
                    }

                    windows.append(UsageWindow(
                        id: "secondary",
                        kind: .weekly,
                        label: "Týdenní limit",
                        usedPercent: used,
                        resetsAt: resetDate,
                        windowDurationMins: durationMins
                    ))
                }
            }

            // Načtení reset kreditů
            let credits = await fetchResetCredits(accessToken: accessToken, accountId: accountId)

            let highestUsed = windows.map { $0.usedPercent }.max() ?? 0.0
            let primaryWindow = windows.first(where: { $0.id == "primary" }) ?? windows.first
            let health: LimitHealthState
            if httpResponse.statusCode == 429 || isLimitReached || highestUsed >= 100.0 {
                health = .exhausted
            } else if highestUsed >= 80.0 {
                health = .warning
            } else {
                health = .normal
            }

            let desc: String
            if health == .exhausted {
                desc = "Limit zpráv vyčerpán"
            } else if let pace = primaryWindow?.pace {
                desc = pace.label
            } else {
                desc = "Aktivní okno zpráv"
            }

            return LimitStatus(
                accountId: account.id,
                provider: .chatgpt,
                usagePercentage: highestUsed,
                planName: planName,
                statusDescription: desc,
                resetDate: primaryWindow?.resetsAt,
                healthState: health,
                isDemo: false,
                windows: windows,
                resetCreditsCount: credits?.count,
                nextCreditExpiresAt: credits?.nextExpiry
            )
        } catch {
            return nil
        }
    }

    private func fetchResetCredits(accessToken: String, accountId: String?) async -> (count: Int, nextExpiry: Date?)? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "Originator")
        if let accountId = accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "Chatgpt-Account-Id")
        }
        request.timeoutInterval = 5.0

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["credits"] as? [[String: Any]] else {
            return nil
        }

        let now = Date()
        let available = list.filter { ($0["status"] as? String) == "available" }
        var minExpiry: Date? = nil
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for item in available {
            if let expStr = item["expires_at"] as? String,
               let date = isoFormatter.date(from: expStr) ?? ISO8601DateFormatter().date(from: expStr),
               date > now {
                if minExpiry == nil || date < minExpiry! {
                    minExpiry = date
                }
            }
        }

        return (count: available.count, nextExpiry: minExpiry)
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

    private func fetchOpenAIAPIStatus(for account: AccountCredential, apiKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď serveru")
            }

            if httpResponse.statusCode == 401 {
                return errorStatus(for: account, message: "Neplatný API klíč")
            } else if httpResponse.statusCode == 429 {
                var isBalanceExhausted = false
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any] {
                    let code = errorObj["code"] as? String ?? ""
                    let type = errorObj["type"] as? String ?? ""
                    let msg = errorObj["message"] as? String ?? ""
                    if code == "credit_balance_exhausted" || type == "insufficient_quota" || msg.lowercased().contains("credit") {
                        isBalanceExhausted = true
                    }
                }

                if isBalanceExhausted {
                    return LimitStatus(
                        accountId: account.id,
                        provider: .chatgpt,
                        usagePercentage: 100.0,
                        planName: "OpenAI Platform API",
                        statusDescription: "Kredit vyčerpán (0 $ zůstatek na účtu)",
                        healthState: .exhausted
                    )
                }

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
                    planName: "OpenAI Platform API",
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
                        planName: "OpenAI Platform API",
                        statusDescription: "\(used)/\(lim) req/min",
                        healthState: health
                    )
                }

                return LimitStatus(
                    accountId: account.id,
                    provider: .chatgpt,
                    usagePercentage: 0.0,
                    planName: "OpenAI Platform API",
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

    private func mockStatus(for account: AccountCredential) -> LimitStatus {
        let sessionWindow = UsageWindow(
            id: "primary",
            kind: .session,
            label: "5h Session",
            usedPercent: 45.0,
            resetsAt: Date().addingTimeInterval(4200),
            windowDurationMins: 300
        )
        let weeklyWindow = UsageWindow(
            id: "secondary",
            kind: .weekly,
            label: "Týdenní limit",
            usedPercent: 28.0,
            resetsAt: Date().addingTimeInterval(86400 * 3),
            windowDurationMins: 10080
        )
        return LimitStatus(
            accountId: account.id,
            provider: .chatgpt,
            usagePercentage: 45.0,
            planName: "ChatGPT Plus [DEMO]",
            statusDescription: "Simulace (přihlášeno v ~/.codex)",
            resetDate: Date().addingTimeInterval(4200),
            healthState: .normal,
            isDemo: true,
            windows: [sessionWindow, weeklyWindow]
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
