import Foundation
import Security

public final class ClaudeService: Sendable {
    public static let shared = ClaudeService()
    private let session: URLSession
    private let localToken: @Sendable () -> String?

    init(session: URLSession = ProviderHTTP.session(), localToken: @escaping @Sendable () -> String? = ClaudeService.loadLocalToken) {
        self.session = session
        self.localToken = localToken
    }

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        var token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") { token = String(token.dropFirst("Bearer ".count)) }
        if token.hasPrefix("sessionKey=") { token = String(token.dropFirst("sessionKey=".count)) }
        if token.lowercased() == "demo" {
            var status = UsageResponseParser.status(for: account, windows: [UsageWindow(id: "demo", kind: .session, label: "5h Session", usedPercent: 82)], plan: "Claude [DEMO]")
            status.isDemo = true
            status.statusDescription = "Simulovaná data"
            return status
        }
        if token.lowercased() == "auto" {
            let local: String?
            do {
                if let file = try LocalProfile.selectedFile(for: account) {
                    let json = try LocalProfile.json(at: file)
                    local = (json["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
                } else {
                    local = localToken()
                }
            } catch {
                return .failure(for: account, "Vybraný profil Claude nelze načíst. Vyberte dostupný credentials JSON soubor.")
            }
            guard let local, !local.isEmpty else {
                return .failure(for: account, "Nenalezen Claude OAuth token. Vyberte credentials JSON soubor nebo se přihlaste pomocí claude auth login.")
            }
            token = local
        }
        guard !token.isEmpty else { return .failure(for: account, "Zadejte token nebo auto pro lokální Claude Code profil.") }
        if token.hasPrefix("sk-ant-api") {
            return .unavailable(for: account, "Anthropic API klíč neposkytuje kvótu předplatného Claude. Použijte auto nebo OAuth token. Žádné generování nebylo odesláno.")
        }
        do {
            if token.hasPrefix("sk-ant-sid") { return try await webStatus(for: account, token: token) }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(ProviderClientIdentity.claudeBeta, forHTTPHeaderField: "anthropic-beta")
            request.setValue(ProviderClientIdentity.claudeUserAgent, forHTTPHeaderField: "User-Agent")
            return try await usage(for: account, request: request, plan: "Claude Subscription")
        } catch {
            return .failure(for: account, "Kvótu Claude se nepodařilo načíst. Zkontrolujte připojení a přihlášení.")
        }
    }

    private func usage(for account: AccountCredential, request: URLRequest, plan: String) async throws -> LimitStatus {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď serveru.") }
        guard http.statusCode == 200 else { return UsageResponseParser.httpFailure(for: account, code: http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable(for: account, "Nerozpoznaný formát kvóty Claude.")
        }
        return UsageResponseParser.status(for: account, windows: UsageResponseParser.claude(json), plan: plan)
    }

    private func webStatus(for account: AccountCredential, token: String) async throws -> LimitStatus {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        request.setValue("sessionKey=\(token)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď serveru.") }
        guard http.statusCode == 200 else { return UsageResponseParser.httpFailure(for: account, code: http.statusCode) }
        guard let organizations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              organizations.count == 1, let id = organizations[0]["uuid"] as? String,
              UUID(uuidString: id) != nil else {
            return .unavailable(for: account, "Webová session nemá jednoznačnou organizaci. Použijte Claude Code OAuth token nebo auto.")
        }
        request.url = URL(string: "https://claude.ai/api/organizations/\(id)/usage")!
        return try await usage(for: account, request: request, plan: "Claude Web")
    }

    private static func loadLocalToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "Claude Code-credentials",
                                  kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let data: Data?
        if status == errSecSuccess {
            data = item as? Data
        } else if status == errSecItemNotFound {
            data = try? Data(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json"))
        } else {
            return nil
        }
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }
}
