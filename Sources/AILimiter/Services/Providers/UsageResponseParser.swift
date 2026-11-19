import Foundation
import CoreFoundation

enum UsageResponseParser {
    static func percentage(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent
    }

    static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double, seconds.isFinite, seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func codex(_ json: [String: Any]) -> [UsageWindow] {
        guard let limits = json["rate_limit"] as? [String: Any] else { return [] }
        return [("primary_window", "primary", 18000), ("secondary_window", "secondary", 604800)].compactMap { key, id, defaultSeconds in
            guard let window = limits[key] as? [String: Any],
                  let used = percentage(window["used_percent"]) else { return nil }
            let seconds = (window["limit_window_seconds"] as? Int) ?? defaultSeconds
            guard seconds > 0, seconds <= 366 * 86400 else { return nil }
            let kind: WindowKind = seconds >= 28 * 86400 ? .monthly : (seconds >= 7 * 86400 ? .weekly : .session)
            let label = kind == .monthly ? "Měsíční" : (kind == .weekly ? "Týdenní" : "\(seconds / 3600)h Session")
            return UsageWindow(id: id, kind: kind, label: label, usedPercent: used,
                               resetsAt: date(window["reset_at"] ?? window["resets_at"]), windowDurationMins: seconds / 60)
        }
    }

    static func claude(_ json: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for key in json.keys.sorted() where key == "five_hour" || key.hasPrefix("seven_day") {
            guard let value = json[key] as? [String: Any], let used = percentage(value["utilization"]) else { continue }
            let session = key == "five_hour"
            let label = session ? "5h Session" : (key == "seven_day" ? "Týdenní" : "Týdenní · \(key.dropFirst(10))")
            windows.append(UsageWindow(id: key, kind: session ? .session : .weekly, label: label,
                                       usedPercent: used, resetsAt: date(value["resets_at"]), windowDurationMins: session ? 300 : 10080))
        }
        if let limits = json["limits"] as? [[String: Any]] {
            for (index, limit) in limits.enumerated() {
                guard limit["kind"] as? String == "weekly_scoped",
                      let used = percentage(limit["percent"]),
                      let scope = limit["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any],
                      let name = model["display_name"] as? String else { continue }
                windows.append(UsageWindow(id: "scoped_\(index)", kind: .weekly, label: "Týdenní · \(name)",
                                           usedPercent: used, resetsAt: date(limit["resets_at"]), windowDurationMins: 10080))
            }
        }
        return windows
    }

    static func status(for account: AccountCredential, windows: [UsageWindow], plan: String,
                       limitReached: Bool = false) -> LimitStatus {
        guard !windows.isEmpty else { return .unavailable(for: account, "Poskytovatel nevrátil údaje o kvótě.") }
        let maximum = windows.max(by: { $0.usedPercent < $1.usedPercent })!
        let health: LimitHealthState = limitReached || maximum.usedPercent >= 100 ? .exhausted : (maximum.usedPercent >= 80 ? .warning : .normal)
        return LimitStatus(accountId: account.id, provider: account.provider, usagePercentage: maximum.usedPercent,
                           planName: plan, statusDescription: health == .exhausted ? "Limit vyčerpán" : "Kvóta načtena",
                           resetDate: maximum.resetsAt, healthState: health, windows: windows)
    }

    static func httpFailure(for account: AccountCredential, code: Int) -> LimitStatus {
        switch code {
        case 401, 403: return .failure(for: account, "Přihlášení není platné nebo vypršelo. Přihlaste se znovu v příslušném CLI nebo obnovte token.")
        case 429: return .unavailable(for: account, "Kontrola kvóty byla omezena (HTTP 429). Zkuste to později; stav předplatného nelze určit.")
        default: return .failure(for: account, "Kontrola kvóty selhala (HTTP \(code)).")
        }
    }
}
