# AILimiter

A native macOS menu bar app for tracking AI subscription usage and reset times, with notifications at 80% and 100% usage. Built with Swift, without external Swift dependencies.

Beta software. Core functionality is covered by automated tests; live quota availability depends on the provider and account.

## Supported services

- Codex subscription quotas, not ChatGPT web message limits.
- Claude session, weekly, and model quotas.
- Antigravity consumer subscription quotas.
- Perplexity Pro quotas through an experimental web session integration.

API keys do not provide these subscription quotas. The app does not measure billing or send generation requests to validate keys.

## Build and run

Requires macOS 13+ and Xcode or Command Line Tools with Swift 6.4+. Tests require macOS 14+; the secret scanner requires Python 3.

```sh
make build     # Build dist/AILimiter.app
make run       # Build and open the app
make install   # Copy the app to /Applications
make test      # Run isolated tests
make security  # Scan available Git history and working files for common secrets
```

Set `ARCH=arm64` or `ARCH=x86_64` to choose a build target. Builds are signed locally and are not notarized. Quit an existing installation before updating it.

## Accounts

Select a local JSON profile or paste a supported OAuth token or session cookie. Add separate cards for multiple accounts. The interface currently uses Czech labels.

Default discovery checks Codex and Claude Code profiles and Antigravity profiles managed by T3 Code. You can choose a compatible file from any location. A failed selected profile never falls back to another account.

Use `auto` for default discovery or `demo` for clearly marked offline sample data.

## Privacy

Tokens are stored in macOS Keychain. Names and selected file paths stay in local settings. Profiles are read without modification. Legacy plaintext copies are removed after successful Keychain migration; old backups are unaffected.

Credentials are sent to the relevant providers over HTTPS. There is no analytics, application backend, or automatic crash reporting. Network sessions do not use disk caches, automatic cookie storage, or redirects.

The app is not sandboxed and may request Keychain access. Do not share credentials in issues, screenshots, or commits. The secret scanner cannot detect every possible secret.

## Limitations

- Internal provider APIs can change or reject access. HTTP 429 does not automatically mean an exhausted subscription.
- Missing data is marked unavailable; failed refreshes preserve timestamped values with a warning.
- Expired Codex and Claude tokens require signing in again. Antigravity tokens are refreshed in memory.
- Tests use mocked responses and synthetic profiles. Live accounts and the interface are not covered by end-to-end tests.

## Client compatibility

Requests use compatibility identifiers defined in [ProviderClientIdentity.swift](Sources/AILimiter/Services/Providers/ProviderClientIdentity.swift), not the versions installed on your computer.

Antigravity uses POST for OAuth renewal and quota retrieval, not generation. Its default project identifier belongs to the shared consumer service.

## Feedback and contact

- [Report a bug or suggest a skill](https://github.com/jkorejtko/ailimiter/issues/new)
- [Connect with me on LinkedIn](https://www.linkedin.com/in/ji%C5%99%C3%AD-korejtko-a21916107/)

## License

MIT. See [LICENSE](LICENSE). The quota integration approach was informed by [T3 Code](https://github.com/pingdotgg/t3code); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). AILimiter is an independent project and is not affiliated with the providers.
