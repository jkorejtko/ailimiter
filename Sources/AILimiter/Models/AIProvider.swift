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
            return "Gemini 1.5 Pro / Advanced"
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
            return "Session Token nebo OpenAI API Key"
        case .claude:
            return "Claude.ai sessionKey nebo Anthropic API Key"
        case .gemini:
            return "Google AI Studio API Key nebo Gemini Cookie"
        case .perplexity:
            return "Perplexity API Key nebo Session Cookie"
        }
    }

    public var tokenPlaceholder: String {
        switch self {
        case .chatgpt:
            return "sk-... nebo session token"
        case .claude:
            return "sk-ant-sid01-... nebo sk-ant-api03-..."
        case .gemini:
            return "AIzaSy..."
        case .perplexity:
            return "pplx-... nebo session-token"
        }
    }

    public var tokenHelp: String {
        switch self {
        case .chatgpt:
            return """
            1. Otevři chatgpt.com v prohlížeči (Chrome/Arc/Safari).
            2. Stiskni F12 (DevTools) → záložka Application (Úložiště) → Cookies → https://chatgpt.com.
            3. Zkopíruj hodnotu cookie '__Secure-next-auth.session-token'.
            Případně zadej standardní OpenAI API klíč (sk-...).
            """
        case .claude:
            return """
            1. Otevři claude.ai a přihlas se.
            2. V DevTools (F12) → Application → Cookies → https://claude.ai.
            3. Zkopíruj hodnotu cookie 'sessionKey' (začíná sk-ant-sid01-...).
            Případně zadej Anthropic API klíč.
            """
        case .gemini:
            return """
            1. Přejdi na aistudio.google.com a vygeneruj si bezplatný API klíč (Get API key).
            2. Klíč začíná 'AIzaSy...' – zkopíruj ho a vlož sem pro sledování limitů a kvót.
            """
        case .perplexity:
            return """
            1. Přejdi na perplexity.ai/settings/api pro získání API klíče (pplx-...).
            2. Nebo v DevTools zkopíruj session token z cookies.
            """
        }
    }
}
