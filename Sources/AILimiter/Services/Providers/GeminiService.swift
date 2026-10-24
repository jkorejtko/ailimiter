import Foundation

public final class GeminiService: @unchecked Sendable {
    public static let shared = GeminiService()
    private let session = URLSession.shared

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        // 1. Přednostně zkontrolujeme aktivitu z lokálního Google Antigravity IDE (nevyžaduje API klíč)
        if let activity = fetchAntigravityActivity() {
            let prompts = activity.todayPrompts
            let desc: String
            if prompts == 0 {
                desc = "Dnes žádná aktivita (připraveno)"
            } else if prompts == 1 {
                desc = "Dnes odeslán 1 agentní prompt"
            } else if prompts >= 2 && prompts <= 4 {
                desc = "Dnes odeslány \(prompts) agentní prompty"
            } else {
                desc = "Dnes odesláno \(prompts) agentních promptů"
            }

            return LimitStatus(
                accountId: account.id,
                provider: .gemini,
                usagePercentage: 0.0,
                planName: "Antigravity IDE (Gemini)",
                statusDescription: desc,
                healthState: .normal,
                isDemo: false
            )
        }

        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)

        if token.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        if token.isEmpty {
            return errorStatus(for: account, message: "Není zadán API klíč")
        }

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1&key=\(token)") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return errorStatus(for: account, message: "Neplatná odpověď")
            }

            if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
                var errorMsg = "Neplatný Gemini API klíč"
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any],
                   let msg = errorObj["message"] as? String, !msg.isEmpty {
                    errorMsg = msg
                }
                return errorStatus(for: account, message: errorMsg)
            } else if httpResponse.statusCode == 429 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .gemini,
                    usagePercentage: 100.0,
                    planName: "Google AI Studio API",
                    statusDescription: "Kvóta vyčerpána (429 Resource Exhausted)",
                    resetDate: Date().addingTimeInterval(3600),
                    healthState: .exhausted,
                    isDemo: false
                )
            } else if httpResponse.statusCode == 200 {
                return LimitStatus(
                    accountId: account.id,
                    provider: .gemini,
                    usagePercentage: 0.0,
                    planName: "Google AI Studio (Standard Tier)",
                    statusDescription: "Klíč aktivní (v pořádku)",
                    healthState: .normal,
                    isDemo: false
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
            provider: .gemini,
            usagePercentage: 25.0,
            usedCount: 4,
            totalLimit: 15,
            planName: "Google AI Studio API [DEMO]",
            statusDescription: "Simulace: zadejte reálný API klíč z aistudio.google.com",
            resetDate: Date().addingTimeInterval(3600),
            healthState: .normal,
            isDemo: true
        )
    }

    private func errorStatus(for account: AccountCredential, message: String) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .gemini,
            usagePercentage: 0.0,
            planName: "Google AI Studio API",
            statusDescription: message,
            healthState: .error,
            isDemo: false
        )
    }

    private func fetchAntigravityActivity() -> (todayPrompts: Int, todayConversations: Int)? {
        let realHome: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            realHome = URL(fileURLWithPath: String(cString: dir))
        } else {
            realHome = URL(fileURLWithPath: "/Users/\(NSUserName())")
        }
        let baseDir = realHome.appendingPathComponent(".gemini/antigravity-ide/brain")
        guard FileManager.default.fileExists(atPath: baseDir.path) else {
            return nil
        }

        let calendar = Calendar.current
        var todayPrompts = 0
        var todayConversations = 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayStr = dateFormatter.string(from: Date())

        guard let convDirs = try? FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }

        for convDir in convDirs {
            let logFile = convDir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard FileManager.default.fileExists(atPath: logFile.path) else { continue }

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }

            if calendar.isDateInToday(modDate) || modDate.timeIntervalSinceNow > -86400 {
                if let content = try? String(contentsOf: logFile, encoding: .utf8) {
                    var convHasTodayPrompt = false
                    content.enumerateLines { line, _ in
                        if line.contains("\"type\":\"USER_INPUT\"") && line.contains(todayStr) {
                            todayPrompts += 1
                            convHasTodayPrompt = true
                        }
                    }
                    if convHasTodayPrompt {
                        todayConversations += 1
                    }
                }
            }
        }

        return (todayPrompts, todayConversations)
    }
}

