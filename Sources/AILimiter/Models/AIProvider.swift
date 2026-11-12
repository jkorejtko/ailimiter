import SwiftUI

public enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case chatgpt = "chatgpt"
    case claude = "claude"
    case gemini = "gemini"
    case perplexity = "perplexity"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chatgpt:
            return "ChatGPT"
        case .claude:
            return "Claude"
        case .gemini:
            return "Google Gemini"
        case .perplexity:
            return "Perplexity"
        }
    }

    public var defaultPlan: String {
        switch self {
        case .chatgpt:
            return "ChatGPT Plus / Team"
        case .claude:
            return "Claude Pro / Max"
        case .gemini:
            return "Google AI Studio API"
        case .perplexity:
            return "Perplexity Pro"
        }
    }

    public var iconName: String {
        switch self {
        case .chatgpt:
            return "brain.head.profile"
        case .claude:
            return "bubble.left.and.text.bubble.right.fill"
        case .gemini:
            return "sparkles"
        case .perplexity:
            return "magnifyingglass.circle.fill"
        }
    }

    public var brandColor: Color {
        switch self {
        case .chatgpt:
            return Color(red: 0.06, green: 0.65, blue: 0.53) // OpenAI green/teal
        case .claude:
            return Color(red: 0.85, green: 0.44, blue: 0.28) // Anthropic terracotta
        case .gemini:
            return Color(red: 0.26, green: 0.52, blue: 0.96) // Google Blue
        case .perplexity:
            return Color(red: 0.12, green: 0.72, blue: 0.81) // Perplexity teal
        }
    }

    public var webUrl: URL {
        switch self {
        case .chatgpt:
            return URL(string: "https://chatgpt.com")!
        case .claude:
            return URL(string: "https://claude.ai")!
        case .gemini:
            return URL(string: "https://gemini.google.com")!
        case .perplexity:
            return URL(string: "https://www.perplexity.ai")!
        }
    }

    public var tokenLabel: String {
        switch self {
        case .chatgpt:
            return "Auto-detekce (auto), Session Token nebo OpenAI API Key"
        case .claude:
            return "Auto-detekce (auto), OAuth Token nebo sessionKey"
        case .gemini:
            return "Auto-detekce (auto), Antigravity profil nebo AI Studio Key"
        case .perplexity:
            return "Perplexity API Key nebo Session Cookie"
        }
    }

    public var tokenPlaceholder: String {
        switch self {
        case .chatgpt:
            return "auto nebo sk-... / session token"
        case .claude:
            return "auto nebo sk-ant-oat... / sk-ant-sid..."
        case .gemini:
            return "auto nebo AIzaSy..."
        case .perplexity:
            return "pplx-... nebo session-token"
        }
    }

    public var tokenHelp: String {
        switch self {
        case .chatgpt:
            return """
            • Zadejte 'auto' pro automatické načtení tokenu z lokálního Codex CLI (~/.codex/auth.json).
            • Nebo vložte ChatGPT session token z Cookies (__Secure-next-auth.session-token).
            • Případně zadejte standardní OpenAI API klíč (sk-...).
            """
        case .claude:
            return """
            • Zadejte 'auto' pro automatické načtení tokenu z lokálního Claude Code CLI (Keychain).
            • Nebo zadejte Claude Code OAuth token (sk-ant-oat...).
            • Případně vložte webový cookie 'sessionKey' (sk-ant-sid...) nebo Anthropic API klíč.
            """
        case .gemini:
            return """
            • Zadejte 'auto' pro načtení z lokálního Google Antigravity profilu (~/.t3/userdata).
            • Nebo zadejte bezplatný Google AI Studio API klíč (AIzaSy...).
            """
        case .perplexity:
            return """
            1. Přejdi na perplexity.ai/settings/api pro získání API klíče (pplx-...).
            2. Nebo v DevTools zkopíruj session token z cookies.
            """
        }
    }
}
