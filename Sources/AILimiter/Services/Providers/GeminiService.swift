import Foundation

public final class GeminiService: @unchecked Sendable {
    public static let shared = GeminiService()
    private let session = URLSession.shared

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if token.lowercased().hasPrefix("demo") || token.isEmpty {
            return mockStatus(for: account, isDemo: true)
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(token)") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
                return errorStatus(for: account, message: "Neplatný Gemini API klíč")
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .gemini,
                    usagePercentage: 100.0,
                    planName: "Gemini 1.5 Pro / Flash",
                    statusDescription: "Denní/minutová kvóta vyčerpána (429)",
                    resetDate: Date().addingTimeInterval(3600),
                    healthState: .exhausted
                )
            } else if httpResponse.statusCode == 200 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .gemini,
                    usagePercentage: 0.0,
                    planName: "Gemini 1.5 Pro / Flash",
                    statusDescription: "Kvóta aktivní v pořádku (15 RPM / 1500 RPD)",
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
            provider: .gemini,
            usagePercentage: 25.0,
            usedCount: 4,
            totalLimit: 15,
            planName: isDemo ? "Gemini 1.5 Pro (Demo simulace)" : "Gemini 1.5 Pro",
            statusDescription: "Simulace: zadejte reálný API klíč z AI Studio",
            healthState: .normal
        )
    }

    private func errorStatus(for account: AccountCredential, message: String) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .gemini,
            usagePercentage: 0.0,
            planName: "Gemini",
            statusDescription: message,
            healthState: .error
        )
    }
}
