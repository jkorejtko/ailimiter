import Foundation

public final class PerplexityService: Sendable {
    public static let shared = PerplexityService()
    private let session: URLSession
    init(session: URLSession = ProviderHTTP.session()) { self.session = session }

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .failure(for: account, "Zadejte session cookie.") }
        if token.lowercased() == "demo" {
            var status = LimitStatus(accountId: account.id, provider: .perplexity, usagePercentage: 15,
                                     planName: "Perplexity [DEMO]", statusDescription: "Simulovaná data")
            status.isDemo = true
            return status
        }
        if token.hasPrefix("pplx-") || token.lowercased() == "auto" {
            return .unavailable(for: account, "API klíč neposkytuje limit webového předplatného. Pro experimentální čtení kvóty použijte session cookie.")
        }
        var request = URLRequest(url: URL(string: "https://www.perplexity.ai/rest/rate-limit/all")!)
        request.setValue(token.contains("=") ? token : "session-token=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď serveru.") }
            guard http.statusCode == 200 else { return UsageResponseParser.httpFailure(for: account, code: http.statusCode) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let window = (json["pro_search"] ?? json["copilot"]) as? [String: Any],
                  let remaining = window["remaining"] as? Int, let limit = window["limit"] as? Int,
                  limit > 0, remaining >= 0, remaining <= limit else {
                return .unavailable(for: account, "Poskytovatel nevrátil rozpoznatelný limit Pro dotazů.")
            }
            return UsageResponseParser.status(for: account, windows: [UsageWindow(id: "pro", kind: .other,
                label: "Pro dotazy", usedPercent: Double(limit - remaining) / Double(limit) * 100,
                resetsAt: UsageResponseParser.date(window["resets_at"]))], plan: "Perplexity Web")
        } catch {
            return .failure(for: account, "Kvótu Perplexity se nepodařilo načíst.")
        }
    }
}
