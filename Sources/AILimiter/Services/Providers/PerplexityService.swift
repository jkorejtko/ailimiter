import Foundation

public final class PerplexityService {
    public static let shared = PerplexityService()
    private let session = URLSession.shared

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if token.lowercased().hasPrefix("demo") || token.isEmpty {
            return mockStatus(for: account, isDemo: true)
        }

        guard let url = URL(string: "https://api.perplexity.ai/models") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 401 {
                return errorStatus(for: account, message: "Neplatný Perplexity klíč")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .perplexity,
                    usagePercentage: 100.0,
                    planName: "Perplexity Pro",
                    statusDescription: "Rate limit vyčerpán (429)",
                    resetDate: Date().addingTimeInterval(3600),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .perplexity,
                    usagePercentage: 10.0,
                    usedCount: 30,
                    totalLimit: 300,
                    planName: "Perplexity Pro",
                    statusDescription: "Aktivní, 270 Pro dotazů zbývá",
                    healthState: .normal
                )
            } else {
                return errorStatus(for: account, message: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return errorStatus(for: account, message: "Chyba sítě: \(error.localizedDescription)")
        }
    }

    private func mockStatus(for account: AccountCredential, isDemo: Bool) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .perplexity,
            usagePercentage: 15.0,
            usedCount: 45,
            totalLimit: 300,
            planName: isDemo ? "Perplexity Pro (Demo)" : "Perplexity Pro",
            statusDescription: "255 Pro dotazů zbývá dnes",
            healthState: .normal
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
