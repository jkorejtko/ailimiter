import Foundation

public final class ChatGPTService: Sendable {
    public static let shared = ChatGPTService()
    private let session: URLSession
    private let home: URL

    init(session: URLSession = ProviderHTTP.session(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.session = session
        self.home = home
    }

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        var token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") { token = String(token.dropFirst("Bearer ".count)) }
        let cookiePrefix = "__Secure-next-auth.session-token="
        if token.hasPrefix(cookiePrefix) { token = String(token.dropFirst(cookiePrefix.count)) }
        if token.lowercased() == "demo" {
            var status = UsageResponseParser.status(for: account, windows: [UsageWindow(id: "demo", kind: .session, label: "5h Session", usedPercent: 45)], plan: "Codex [DEMO]")
            status.isDemo = true
            status.statusDescription = "Simulovaná data"
            return status
        }
        var accountID: String?
        if token.lowercased() == "auto" {
            do {
                let file = try LocalProfile.selectedFile(for: account) ?? home.appendingPathComponent(".codex/auth.json")
                let json = try LocalProfile.json(at: file)
                guard let tokens = json["tokens"] as? [String: Any],
                      let access = tokens["access_token"] as? String, !access.isEmpty else {
                    return .failure(for: account, "Profil Codex neobsahuje OAuth access token. Vyberte auth.json přihlášeného účtu.")
                }
                token = access
                accountID = tokens["account_id"] as? String
            } catch {
                return .failure(for: account, "Profil Codex nelze načíst. Vyberte dostupný auth.json nebo se přihlaste pomocí codex login.")
            }
        }
        guard !token.isEmpty else { return .failure(for: account, "Zadejte token nebo auto pro lokální Codex profil.") }
        if token.hasPrefix("sk-") {
            return .unavailable(for: account, "OpenAI API klíč neposkytuje kvótu předplatného Codex. Použijte auto nebo OAuth token. Žádné generování nebylo odesláno.")
        }
        do {
            if !token.hasPrefix("ey") {
                var request = URLRequest(url: URL(string: "https://chatgpt.com/api/auth/session")!)
                request.setValue("\(cookiePrefix)\(token)", forHTTPHeaderField: "Cookie")
                request.timeoutInterval = 8
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď serveru.") }
                guard http.statusCode == 200 else { return UsageResponseParser.httpFailure(for: account, code: http.statusCode) }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let access = json["accessToken"] as? String, !access.isEmpty else {
                    return .failure(for: account, "Session neposkytla přístupový token.")
                }
                token = access
            }
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(ProviderClientIdentity.codexBeta, forHTTPHeaderField: "OpenAI-Beta")
            request.setValue(ProviderClientIdentity.codexOriginator, forHTTPHeaderField: "originator")
            if let accountID { request.setValue(accountID, forHTTPHeaderField: "Chatgpt-Account-Id") }
            request.timeoutInterval = 8
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď serveru.") }
            guard http.statusCode == 200 else { return UsageResponseParser.httpFailure(for: account, code: http.statusCode) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unavailable(for: account, "Nerozpoznaný formát kvóty Codex.")
            }
            let limits = json["rate_limit"] as? [String: Any]
            var status = UsageResponseParser.status(for: account, windows: UsageResponseParser.codex(json),
                                              plan: "Codex · \(json["plan_type"] as? String ?? "předplatné")",
                                              limitReached: limits?["limit_reached"] as? Bool == true)
            if status.hasUsageData {
                var creditsRequest = request
                creditsRequest.url = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
                creditsRequest.timeoutInterval = 5
                if let (creditsData, creditsResponse) = try? await session.data(for: creditsRequest),
                   (creditsResponse as? HTTPURLResponse)?.statusCode == 200,
                   let creditsJSON = try? JSONSerialization.jsonObject(with: creditsData) as? [String: Any],
                   let credits = creditsJSON["credits"] as? [[String: Any]] {
                    let available = credits.filter {
                        guard $0["status"] as? String == "available" else { return false }
                        if let expiry = UsageResponseParser.date($0["expires_at"]) { return expiry > Date() }
                        return $0["expires_at"] == nil || $0["expires_at"] is NSNull
                    }
                    status.resetCreditsCount = available.count
                    status.nextCreditExpiresAt = available.compactMap { UsageResponseParser.date($0["expires_at"]) }.min()
                }
            }
            return status
        } catch {
            return .failure(for: account, "Kvótu Codex se nepodařilo načíst. Zkontrolujte připojení a přihlášení.")
        }
    }
}
