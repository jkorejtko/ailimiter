import Foundation

public final class GeminiService: @unchecked Sendable {
    public static let shared = GeminiService()
    private let session = URLSession.shared

    private var cachedAccessToken: String? = nil
    private var tokenExpiry: Date? = nil

    private init() {}

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        let rawToken = account.token.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Pokud je na Macu přítomen Antigravity profil (~/.t3), VŽDY ho zkusíme prioritně (poskytuje reálná 5h a týdenní okna)
        if let antigravityStatus = await fetchAntigravityLiveStatus(for: account) {
            return antigravityStatus
        }

        // 2. Google AI Studio API klíč (AIzaSy...) jako záloha, pokud Antigravity není na stroji
        if rawToken.hasPrefix("AIza") || (!rawToken.isEmpty && rawToken != "auto" && rawToken != "demo") {
            let studioStatus = await fetchAIStudioStatus(for: account, apiKey: rawToken)
            if studioStatus.healthState != .error {
                return studioStatus
            }
        }

        if rawToken.lowercased() == "demo" {
            return mockStatus(for: account)
        }

        return errorStatus(for: account, message: "Nenalezen Antigravity profil v ~/.t3 ani platný API klíč")
    }

    // MARK: - Antigravity Quota API (T3 Code metoda)

    private func findAntigravityTokenFile() -> (url: URL, projectId: String?)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent(".t3/userdata/providers/antigravity")

        guard FileManager.default.fileExists(atPath: baseDir.path) else { return nil }

        // Prohledáme složku pro acp_token.json
        if let enumerator = FileManager.default.enumerator(at: baseDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "acp_token.json" {
                    if let data = try? Data(contentsOf: fileURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let refreshToken = json["refresh_token"] as? String, !refreshToken.isEmpty {
                        let project = json["project_id"] as? String
                        return (url: fileURL, projectId: project)
                    }
                }
            }
        }
        return nil
    }

    private func getRefreshedAccessToken(from tokenFileUrl: URL) async -> (token: String, projectId: String?)? {
        if let cached = cachedAccessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            let data = try? Data(contentsOf: tokenFileUrl)
            let json = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
            return (token: cached, projectId: json?["project_id"] as? String)
        }

        guard let data = try? Data(contentsOf: tokenFileUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String,
              let clientSecret = json["client_secret"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            return nil
        }

        let projectId = json["project_id"] as? String

        guard let tokenUrl = URL(string: "https://oauth2.googleapis.com/token") else { return nil }
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 8.0

        guard let (respData, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let respJson = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let newAccessToken = respJson["access_token"] as? String else {
            return nil
        }

        let expiresIn = (respJson["expires_in"] as? Double) ?? 3600.0
        cachedAccessToken = newAccessToken
        tokenExpiry = Date().addingTimeInterval(expiresIn)

        return (token: newAccessToken, projectId: projectId)
    }

    private func fetchAntigravityLiveStatus(for account: AccountCredential) async -> LimitStatus? {
        guard let tokenFileInfo = findAntigravityTokenFile(),
              let auth = await getRefreshedAccessToken(from: tokenFileInfo.url) else {
            return nil
        }

        let endpoints = [
            "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
            "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
        ]

        var summaryJson: [String: Any]? = nil

        for endpointStr in endpoints {
            guard let url = URL(string: endpointStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity/hub/2.24.0 (aidev_client; os_type=darwin; arch=arm64; cl=963137146)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let payload = auth.projectId != nil ? ["project": auth.projectId!] : [:]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = 8.0

            if let (data, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                summaryJson = json
                break
            }
        }

        guard let summary = summaryJson else { return nil }

        var windows: [UsageWindow] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Parsování buckets z groups nebo přímo z rootu
        var buckets: [[String: Any]] = []
        if let groups = summary["groups"] as? [[String: Any]] {
            for group in groups {
                if let bList = group["buckets"] as? [[String: Any]] {
                    buckets.append(contentsOf: bList)
                }
            }
        }
        if let rootBuckets = summary["buckets"] as? [[String: Any]] {
            buckets.append(contentsOf: rootBuckets)
        }

        for bucket in buckets {
            guard let bucketId = bucket["bucketId"] as? String else { continue }
            if let disabled = bucket["disabled"] as? Bool, disabled { continue }

            let remFraction = (bucket["remainingFraction"] as? Double) ?? 1.0
            let usedPercent = min(100.0, max(0.0, (1.0 - remFraction) * 100.0))
            let windowStr = bucket["window"] as? String ?? ""
            let resetTimeStr = bucket["resetTime"] as? String

            var resetDate: Date? = nil
            if let rStr = resetTimeStr {
                resetDate = isoFormatter.date(from: rStr) ?? ISO8601DateFormatter().date(from: rStr)
            }

            let family: String
            if bucketId.contains("argon") {
                family = "Gemini Argon"
            } else if bucketId.contains("carbon") {
                family = "Gemini Carbon"
            } else if bucketId.contains("3p") {
                family = "Claude & GPT"
            } else if bucketId.contains("gemini") {
                family = "Gemini"
            } else {
                family = (bucket["displayName"] as? String) ?? bucketId
            }

            let kind: WindowKind
            let durationMins: Int
            let label: String

            if windowStr == "5h" || bucketId.contains("5h") {
                kind = .session
                durationMins = 300
                label = "\(family) · 5h"
            } else if windowStr == "weekly" || bucketId.contains("weekly") {
                kind = .weekly
                durationMins = 10080
                label = "\(family) · Týdenní"
            } else {
                kind = .other
                durationMins = 1440
                label = "\(family) · Kvóta"
            }

            windows.append(UsageWindow(
                id: bucketId,
                kind: kind,
                label: label,
                usedPercent: usedPercent,
                resetsAt: resetDate,
                windowDurationMins: durationMins
            ))
        }

        guard !windows.isEmpty else { return nil }

        // Seřadíme okna: session první, pak weekly
        windows.sort { w1, w2 in
            if w1.kind == .session && w2.kind != .session { return true }
            if w1.kind == .weekly && w2.kind == .other { return true }
            return false
        }

        let highestUsed = windows.map { $0.usedPercent }.max() ?? 0.0
        let sessionWindow = windows.first(where: { $0.kind == .session }) ?? windows.first

        let health: LimitHealthState
        if highestUsed >= 100.0 {
            health = .exhausted
        } else if highestUsed >= 80.0 {
            health = .warning
        } else {
            health = .normal
        }

        let desc: String
        if health == .exhausted {
            desc = "Limit kvóty vyčerpán"
        } else if let pace = sessionWindow?.pace {
            desc = pace.label
        } else {
            desc = "Kvóta aktivní v normě"
        }

        return LimitStatus(
            accountId: account.id,
            provider: .gemini,
            usagePercentage: highestUsed,
            planName: "Antigravity (Gemini)",
            statusDescription: desc,
            resetDate: sessionWindow?.resetsAt,
            healthState: health,
            isDemo: false,
            windows: windows
        )
    }

    // MARK: - Google AI Studio Fallback

    private func fetchAIStudioStatus(for account: AccountCredential, apiKey: String) async -> LimitStatus {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1&key=\(apiKey)") else {
            return errorStatus(for: account, message: "Neplatná URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0

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
                    planName: "Google AI Studio API",
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
        let sessionWindow = UsageWindow(
            id: "gemini-5h",
            kind: .session,
            label: "5h Session",
            usedPercent: 23.0,
            resetsAt: Date().addingTimeInterval(3600),
            windowDurationMins: 300
        )
        let weeklyWindow = UsageWindow(
            id: "gemini-weekly",
            kind: .weekly,
            label: "Týdenní limit",
            usedPercent: 12.0,
            resetsAt: Date().addingTimeInterval(86400 * 4),
            windowDurationMins: 10080
        )
        return LimitStatus(
            accountId: account.id,
            provider: .gemini,
            usagePercentage: 23.0,
            planName: "Antigravity IDE [DEMO]",
            statusDescription: "Simulace: připojte lokální Google účet",
            resetDate: Date().addingTimeInterval(3600),
            healthState: .normal,
            isDemo: true,
            windows: [sessionWindow, weeklyWindow]
        )
    }

    private func errorStatus(for account: AccountCredential, message: String) -> LimitStatus {
        return LimitStatus(
            accountId: account.id,
            provider: .gemini,
            usagePercentage: 0.0,
            planName: "Google Antigravity",
            statusDescription: message,
            healthState: .error,
            isDemo: false
        )
    }
}
