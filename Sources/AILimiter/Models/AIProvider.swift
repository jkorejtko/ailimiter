import SwiftUI

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatgpt = "chatgpt"
    case claude = "claude"
    case gemini = "gemini"
    case perplexity = "perplexity"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chatgpt:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Antigravity"
        case .perplexity:
            return "Perplexity"
        }
    }

    public var defaultPlan: String {
        switch self {
        case .chatgpt:
            return "Codex předplatné"
        case .claude:
            return "Claude Pro / Max"
        case .gemini:
            return "Antigravity"
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
            return URL(string: "https://chatgpt.com/codex")!
        case .claude:
            return URL(string: "https://claude.ai")!
        case .gemini:
            return URL(string: "https://antigravity.google")!
        case .perplexity:
            return URL(string: "https://www.perplexity.ai")!
        }
    }

    public var supportsLocalProfiles: Bool { self != .perplexity }

    public var defaultProfileDescription: String {
        switch self {
        case .chatgpt: return "Výchozí: ~/.codex/auth.json"
        case .claude: return "Výchozí: Claude Code Keychain, potom ~/.claude/.credentials.json"
        case .gemini: return "Výchozí: jediný acp_token.json v ~/.t3/userdata/providers/antigravity"
        case .perplexity: return "Lokální profil není podporován."
        }
    }

    public var tokenLabel: String {
        switch self {
        case .chatgpt:
            return "auto, OAuth token nebo ChatGPT session cookie"
        case .claude:
            return "Auto-detekce (auto), OAuth Token nebo sessionKey"
        case .gemini:
            return "auto pro lokální Antigravity profil"
        case .perplexity:
            return "Perplexity session cookie"
        }
    }

    public var tokenPlaceholder: String {
        switch self {
        case .chatgpt:
            return "auto nebo OAuth / session token"
        case .claude:
            return "auto nebo sk-ant-oat... / sk-ant-sid..."
        case .gemini:
            return "auto"
        case .perplexity:
            return "session-token"
        }
    }

    public var tokenHelp: String {
        switch self {
        case .chatgpt:
            return """
            • Vyberte lokální auth.json přihlášeného Codex účtu nebo použijte výchozí profil.
            • Nebo vložte ChatGPT session token z Cookies (__Secure-next-auth.session-token).
            • Jde o kvótu Codexu, nikoli počet zpráv na webu ChatGPT. API klíč tuto kvótu neposkytuje.
            """
        case .claude:
            return """
            • Vyberte lokální credentials JSON soubor nebo použijte výchozí Claude Code Keychain.
            • Nebo zadejte Claude Code OAuth token (sk-ant-oat...).
            • Případně vložte webovou cookie 'sessionKey' (sk-ant-sid...). API klíč tuto kvótu neposkytuje.
            """
        case .gemini:
            return """
            • Vyberte OAuth JSON profil s client_id, client_secret a refresh_token. Umístění není omezené na T3 Code.
            • Výchozí autodetekce hledá jediný acp_token.json v adresáři T3 Code. AI Studio klíč tuto kvótu neposkytuje.
            """
        case .perplexity:
            return """
            • V DevTools na perplexity.ai zkopírujte session cookie. Čtení kvóty je experimentální.
            • API klíč neposkytuje limit webového předplatného.
            """
        }
    }
}
