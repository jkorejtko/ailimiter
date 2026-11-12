import Foundation

public struct AccountCredential: Identifiable, Codable, Equatable {
    public let id: UUID
    public var provider: AIProvider
    public var title: String
    public var token: String
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        provider: AIProvider,
        title: String,
        token: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.token = token
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    public var isDemo: Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "auto" {
            return false
        }
        if provider == .gemini {
            let realHome = FileManager.default.homeDirectoryForCurrentUser
            let baseDir = realHome.appendingPathComponent(".t3/userdata/providers/antigravity")
            if FileManager.default.fileExists(atPath: baseDir.path) {
                return false
            }
        }
        return trimmed == "demo" || trimmed.isEmpty
    }
}
