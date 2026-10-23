import SwiftUI

public enum LimitHealthState: String, Codable {
    case normal     // < 80%
    case warning    // 80% - 99%
    case exhausted  // 100% / rate limited
    case error      // Network error, expired token, etc.

    public var color: Color {
        switch self {
        case .normal:
            return Color(red: 0.18, green: 0.80, blue: 0.44) // Emerald Green
        case .warning:
            return Color(red: 0.96, green: 0.65, blue: 0.14) // Amber / Orange
        case .exhausted:
            return Color(red: 0.91, green: 0.30, blue: 0.24) // Crimson Red
        case .error:
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
        }
    }
}

public struct LimitStatus: Identifiable, Codable, Equatable {
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
    public var lastChecked: Date

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
        lastChecked: Date = Date()
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
        self.lastChecked = lastChecked
    }

    public var resetCountdownString: String? {
        guard let resetDate = resetDate else { return nil }
        let now = Date()
        let diff = resetDate.timeIntervalSince(now)
        if diff <= 0 {
            return "Obnovuje se..."
        }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 {
            return "Obnovení za \(hours)h \(minutes)m"
        } else {
            return "Obnovení za \(minutes)m"
        }
    }
}
