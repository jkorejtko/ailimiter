import SwiftUI

public enum LimitHealthState: String, Codable, Sendable {
    case normal     // < 80%
    case warning    // 80% - 99%
    case exhausted  // 100% / rate limited
    case error      // Network error, expired token, etc.
    case unavailable // No reported quota; never treat this as zero usage.

    public var color: Color {
        switch self {
        case .normal:
            return Color(red: 0.18, green: 0.80, blue: 0.44) // Emerald Green
        case .warning:
            return Color(red: 0.96, green: 0.65, blue: 0.14) // Amber / Orange
        case .exhausted:
            return Color(red: 0.91, green: 0.30, blue: 0.24) // Crimson Red
        case .error, .unavailable:
            return Color.secondary
        }
    }

    public var badgeTitle: String {
        switch self {
        case .normal:
            return "V pořádku"
        case .warning:
            return "Pozor (>80%)"
        case .exhausted:
            return "Limit vyčerpán"
        case .error:
            return "Chyba"
        case .unavailable:
            return "Nedostupné"
        }
    }
}

public enum WindowKind: String, Codable, Sendable {
    case session
    case weekly
    case monthly
    case other

    public var displayTitle: String {
        switch self {
        case .session: return "5h Session"
        case .weekly: return "Týdenní"
        case .monthly: return "Měsíční"
        case .other: return "Limit"
        }
    }
}

public enum LimitPace: String, Codable, Sendable {
    case ahead
    case on
    case under

    public var label: String {
        switch self {
        case .ahead: return "Rychlé čerpání (> tempo)"
        case .on: return "V normě s oknem"
        case .under: return "S rezervou"
        }
    }

    public var iconName: String {
        switch self {
        case .ahead: return "chart.line.uptrend.xyaxis"
        case .on: return "gauge.medium"
        case .under: return "chart.line.downtrend.xyaxis"
        }
    }

    public var color: Color {
        switch self {
        case .ahead: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .on: return Color(red: 0.18, green: 0.80, blue: 0.44)
        case .under: return Color(red: 0.2, green: 0.6, blue: 1.0)
        }
    }
}

public struct UsageWindow: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: WindowKind
    public var label: String
    public var usedPercent: Double          // 0.0 ... 100.0
    public var resetsAt: Date?
    public var windowDurationMins: Int?
    public var scopeLabel: String?

    public init(
        id: String,
        kind: WindowKind,
        label: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowDurationMins: Int? = nil,
        scopeLabel: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.usedPercent = min(max(usedPercent, 0.0), 100.0)
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
        self.scopeLabel = scopeLabel
    }

    public var remainingPercent: Double {
        return max(0.0, 100.0 - usedPercent)
    }

    public var pace: LimitPace? {
        guard let resetsAt = resetsAt, let windowDurationMins = windowDurationMins, windowDurationMins > 0 else {
            return nil
        }
        let now = Date()
        let totalSec = Double(windowDurationMins * 60)
        let remainingSec = resetsAt.timeIntervalSince(now)
        let elapsedFraction = max(0.0, min(1.0, (totalSec - remainingSec) / totalSec))
        let gap = usedPercent - (elapsedFraction * 100.0)
        if gap > 5.0 { return .ahead }
        if gap < -5.0 { return .under }
        return .on
    }

    public var resetCountdownString: String? {
        guard let resetsAt = resetsAt else { return nil }
        let now = Date()
        let diff = resetsAt.timeIntervalSince(now)
        if diff <= 0 {
            return "Čeká na aktualizaci"
        }
        let totalSeconds = Int(diff)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

public struct LimitStatus: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let accountId: UUID
    public let provider: AIProvider
    public var usagePercentage: Double      // 0.0 ... 100.0
    public var usedCount: Int?              // e.g. 38
    public var totalLimit: Int?             // e.g. 40
    public var planName: String             // e.g. "Plus / GPT-4o"
    public var statusDescription: String    // e.g. "Zbývají 2 zprávy"
    public var resetDate: Date?             // Kdy se limit obnoví
    public var healthState: LimitHealthState
    public var isDemo: Bool
    public var lastChecked: Date

    // T3 Code style windows & credits
    public var windows: [UsageWindow]
    public var resetCreditsCount: Int?
    public var nextCreditExpiresAt: Date?
    public var refreshError: String? = nil

    public var hasUsageData: Bool {
        healthState != .error && healthState != .unavailable
    }

    static func unavailable(for account: AccountCredential, _ message: String) -> LimitStatus {
        LimitStatus(accountId: account.id, provider: account.provider, usagePercentage: 0,
                    planName: account.provider.displayName, statusDescription: message, healthState: .unavailable)
    }

    static func failure(for account: AccountCredential, _ message: String) -> LimitStatus {
        LimitStatus(accountId: account.id, provider: account.provider, usagePercentage: 0,
                    planName: account.provider.displayName, statusDescription: message, healthState: .error)
    }

    public init(
        id: UUID = UUID(),
        accountId: UUID,
        provider: AIProvider,
        usagePercentage: Double,
        usedCount: Int? = nil,
        totalLimit: Int? = nil,
        planName: String,
        statusDescription: String,
        resetDate: Date? = nil,
        healthState: LimitHealthState = .normal,
        isDemo: Bool = false,
        lastChecked: Date = Date(),
        windows: [UsageWindow] = [],
        resetCreditsCount: Int? = nil,
        nextCreditExpiresAt: Date? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.provider = provider
        self.usagePercentage = min(max(usagePercentage, 0.0), 100.0)
        self.usedCount = usedCount
        self.totalLimit = totalLimit
        self.planName = planName
        self.statusDescription = statusDescription
        self.resetDate = resetDate
        self.healthState = healthState
        self.isDemo = isDemo
        self.lastChecked = lastChecked
        self.windows = windows
        self.resetCreditsCount = resetCreditsCount
        self.nextCreditExpiresAt = nextCreditExpiresAt
    }

    public var resetCountdownString: String? {
        guard let resetDate = resetDate else { return nil }
        let now = Date()
        let diff = resetDate.timeIntervalSince(now)
        if diff <= 0 {
            return "Obnovuje se..."
        }
        let totalSeconds = Int(diff)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return String(format: "Obnovení za %02dd %02dh %02dm", days, hours, minutes)
        } else if hours > 0 {
            return "Obnovení za \(hours)h \(minutes)m"
        } else {
            return "Obnovení za \(minutes)m"
        }
    }
}
