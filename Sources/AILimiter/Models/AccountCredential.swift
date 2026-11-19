import Foundation

public struct AccountCredential: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var provider: AIProvider
    public var title: String
    public var token: String
    public var isEnabled: Bool
    public var createdAt: Date
    public var profilePath: String?

    public init(
        id: UUID = UUID(),
        provider: AIProvider,
        title: String,
        token: String,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        profilePath: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.token = token
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.profilePath = profilePath
    }

    public var isDemo: Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "demo"
    }

    public var displayTitle: String {
        // Keep stored identifiers and custom names intact while updating old default labels.
        switch provider {
        case .chatgpt where ["ChatGPT", "ChatGPT / Codex"].contains(title): return provider.displayName
        case .gemini where ["Google Gemini", "Antigravity (Gemini)"].contains(title): return provider.displayName
        default: return title
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, title, token, isEnabled, createdAt, profilePath
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        provider = try values.decode(AIProvider.self, forKey: .provider)
        title = try values.decode(String.self, forKey: .title)
        token = try values.decodeIfPresent(String.self, forKey: .token) ?? ""
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        profilePath = try values.decodeIfPresent(String.self, forKey: .profilePath)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(provider, forKey: .provider)
        try values.encode(title, forKey: .title)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(profilePath, forKey: .profilePath)
    }
}
