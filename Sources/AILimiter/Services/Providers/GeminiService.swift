import Foundation

public actor GeminiService {
    public static let shared = GeminiService()
    private let session: URLSession
    private let home: URL
    private var cachedToken: (file: URL, data: Data, token: String, expiresAt: Date)?

    init(session: URLSession = ProviderHTTP.session(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.session = session
        self.home = home
    }

    public func fetchLimitStatus(for account: AccountCredential) async -> LimitStatus {
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "demo" {
            var status = UsageResponseParser.status(for: account, windows: [UsageWindow(id: "demo", kind: .session, label: "Gemini · 5h", usedPercent: 23)], plan: "Antigravity [DEMO]")
            status.isDemo = true
            status.statusDescription = "Simulovaná data"
            return status
        }
        guard token == "auto" else {
            return .unavailable(for: account, "Google AI Studio API klíč neposkytuje kvótu Antigravity ani Gemini webu. Pro lokální Antigravity profil použijte auto.")
        }
        do {
            let file: URL
            if let selected = try LocalProfile.selectedFile(for: account) {
                file = selected
            } else {
                let directory = home.appendingPathComponent(".t3/userdata/providers/antigravity")
                let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent == "acp_token.json" }
                guard files.count == 1, let discovered = files.first else {
                    return .unavailable(for: account, files.isEmpty ? "Nenalezen Antigravity profil. Vyberte OAuth JSON soubor v nastavení účtu." : "Nalezeno více Antigravity profilů. Vyberte konkrétní OAuth JSON soubor v nastavení účtu.")
                }
                file = discovered
            }
            let data = try Data(contentsOf: file)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let clientID = json["client_id"] as? String,
                  let secret = json["client_secret"] as? String,
                  let refresh = json["refresh_token"] as? String else {
                return .failure(for: account, "Antigravity profil neobsahuje potřebné přihlašovací údaje.")
            }
            let accessToken: String
            if let cached = cachedToken, cached.file == file, cached.data == data, cached.expiresAt > Date().addingTimeInterval(60) {
                accessToken = cached.token
            } else {
                var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                // application/x-www-form-urlencoded encodes spaces as + and literal + as %2B.
                let fields = [("client_id", clientID), ("client_secret", secret), ("refresh_token", refresh), ("grant_type", "refresh_token")]
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                request.httpBody = fields.map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").data(using: .utf8)
                request.timeoutInterval = 8
                let (responseData, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď přihlášení.") }
                guard http.statusCode == 200 else {
                    return .failure(for: account, "Přihlášení Antigravity nelze obnovit (HTTP \(http.statusCode)). Obnovte přihlášení v aplikaci, která profil vytvořila.")
                }
                guard let responseJSON = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let access = responseJSON["access_token"] as? String, !access.isEmpty else {
                    return .failure(for: account, "Přihlášení Antigravity nevrátilo token.")
                }
                accessToken = access
                let expires = responseJSON["expires_in"] as? Double ?? 3600
                cachedToken = (file, data, access, Date().addingTimeInterval(expires))
            }
            // Consumer accounts use the daily endpoint. Do not replace failures with unused production quotas.
            var request = URLRequest(url: URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(ProviderClientIdentity.antigravityUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["project": json["project_id"] as? String ?? "aicode-consumers"])
            request.timeoutInterval = 8
            let (summary, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(for: account, "Neplatná odpověď kvóty.") }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 { cachedToken = nil }
                return UsageResponseParser.httpFailure(for: account, code: http.statusCode)
            }
            guard let summaryJSON = try JSONSerialization.jsonObject(with: summary) as? [String: Any] else {
                return .unavailable(for: account, "Nerozpoznaný formát kvóty Antigravity.")
            }
            return UsageResponseParser.status(for: account, windows: Self.windows(summaryJSON), plan: "Antigravity")
        } catch {
            return .failure(for: account, "Kvótu Antigravity se nepodařilo načíst. Zkontrolujte profil a připojení.")
        }
    }

    static func displayWindows(_ windows: [UsageWindow]) -> (primary: [UsageWindow], other: [UsageWindow]) {
        func priority(_ window: UsageWindow) -> Int {
            let model = "\(window.id) \(window.label)".lowercased()
            if model.contains("argon") { return 1 }
            if model.contains("hydrogen") { return 2 }
            if window.kind == .session && (model.contains("gemini") || window.id.lowercased() == "5h") && !model.contains("3p") { return 0 }
            return 3
        }
        let primary = windows.filter { priority($0) < 3 }.sorted {
            (priority($0), $0.id) < (priority($1), $1.id)
        }
        return (primary, windows.filter { priority($0) == 3 })
    }

    static func windows(_ json: [String: Any]) -> [UsageWindow] {
        var buckets = json["buckets"] as? [[String: Any]] ?? []
        for group in json["groups"] as? [[String: Any]] ?? [] {
            buckets += group["buckets"] as? [[String: Any]] ?? []
        }
        var seen = Set<String>()
        return buckets.compactMap { bucket in
            guard let id = bucket["bucketId"] as? String, !seen.contains(id),
                  bucket["disabled"] as? Bool != true,
                  let fraction = UsageResponseParser.percentage(bucket["remainingFraction"]), fraction <= 1 else { return nil }
            seen.insert(id)
            let session = bucket["window"] as? String == "5h" || id.contains("5h")
            let weekly = bucket["window"] as? String == "weekly" || id.contains("weekly")
            let kind: WindowKind = session ? .session : (weekly ? .weekly : .other)
            let label = bucket["displayName"] as? String ?? id
            return UsageWindow(id: id, kind: kind, label: label,
                               usedPercent: (1 - fraction) * 100, resetsAt: UsageResponseParser.date(bucket["resetTime"]),
                               windowDurationMins: session ? 300 : (weekly ? 10080 : nil), scopeLabel: label)
        }.sorted { $0.id < $1.id }
    }
}
