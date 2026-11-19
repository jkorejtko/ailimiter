import Foundation

/// Compatibility identifiers sent to private quota endpoints, not AILimiter's version.
/// Keep changes explicit: providers may vary their response by client identity.
/// See README: "Client compatibility".
enum ProviderClientIdentity {
    static let codexOriginator = "codex_cli_rs"
    static let codexBeta = "codex-1"
    static let claudeUserAgent = "claude-code/2.1.273"
    static let claudeBeta = "oauth-2025-04-20"

    static var antigravityUserAgent: String {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x64"
        #endif
        return "antigravity/hub/2.24.0 (aidev_client; os_type=darwin; arch=\(architecture))"
    }
}
