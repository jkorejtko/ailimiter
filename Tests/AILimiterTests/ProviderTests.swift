import Foundation
import Testing
@testable import AILimiter

private final class StubHandlers: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, String)
    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    func set(_ id: String, _ handler: Handler?) { lock.withLock { handlers[id] = handler } }
    func get(_ id: String) -> Handler? { lock.withLock { handlers[id] } }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let handlers = StubHandlers()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Test-Fixture"), let handler = Self.handlers.get(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            request.httpBody = body
        }
        let (code, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct StubSession {
    let id = UUID().uuidString
    let session: URLSession
    init(handler: @escaping StubHandlers.Handler) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-Fixture": id]
        session = URLSession(configuration: configuration)
        StubProtocol.handlers.set(id, handler)
    }
    func close() {
        session.invalidateAndCancel()
        StubProtocol.handlers.set(id, nil)
    }
}

@Test(arguments: [0.0, 0.5, 1.0, 45.0, 100.0])
func codexPercentagesAreAlreadyPercentages(_ percent: Double) {
    let windows = UsageResponseParser.codex(["rate_limit": ["primary_window": ["used_percent": percent], "secondary_window": ["used_percent": percent]]])
    #expect(windows.count == 2)
    #expect(windows.allSatisfy { $0.usedPercent == percent })
}

@Test func malformedOrMissingWindowsAreNotZeroUsage() {
    let account = AccountCredential(provider: .chatgpt, title: "Work", token: "fixture")
    for value: Any in [NSNull(), true, "1", -1, 101] {
        #expect(UsageResponseParser.codex(["rate_limit": ["primary_window": ["used_percent": value]]]).isEmpty)
    }
    #expect(UsageResponseParser.codex(["rate_limit": ["primary_window": [:]]]).isEmpty)
    let status = UsageResponseParser.status(for: account, windows: [], plan: "Test")
    #expect(status.healthState == .unavailable)
    #expect(!status.hasUsageData)
}

@Test func claudeParsesSessionWeeklyAndModelSpecificWindows() {
    let windows = UsageResponseParser.claude([
        "five_hour": ["utilization": 1, "resets_at": "2026-11-17T12:00:00Z"],
        "seven_day": ["utilization": 80],
        "seven_day_opus": ["utilization": 100]
    ])
    #expect(windows.count == 3)
    #expect(windows.first?.usedPercent == 1)
    #expect(windows.first?.resetsAt != nil)
    #expect(windows.last?.usedPercent == 100)
}

@Test func antigravityRequiresReportedRemainingFraction() {
    let windows = GeminiService.windows(["buckets": [
        ["bucketId": "missing-5h"], ["bucketId": "invalid-5h", "remainingFraction": 2],
        ["bucketId": "disabled-5h", "remainingFraction": 0, "disabled": true],
        ["bucketId": "gemini-5h", "remainingFraction": 0.75]
    ]])
    #expect(windows.count == 1)
    #expect(windows.first?.usedPercent == 25)
}

@Test func codexUsesProvidedAccountAndReadOnlyEndpoint() async {
    let stub = StubSession { request in
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eyJ.fixture")
        if request.url?.path == "/backend-api/wham/rate-limit-reset-credits" {
            return (200, #"{"credits":[{"status":"available","expires_at":"2099-01-01T00:00:00Z"},{"status":"available","expires_at":"2000-01-01T00:00:00Z"},{"status":"used"}]}"#)
        }
        #expect(request.url?.path == "/backend-api/wham/usage")
        return (200, #"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":1,"reset_at":1794916800},"secondary_window":{"used_percent":81}}}"#)
    }
    defer { stub.close() }
    let service = ChatGPTService(session: stub.session)
    let account = AccountCredential(provider: .chatgpt, title: "Work", token: "eyJ.fixture")
    let status = await service.fetchLimitStatus(for: account)
    #expect(status.windows.first?.usedPercent == 1)
    #expect(status.healthState == .warning)
    #expect(status.accountId == account.id)
    #expect(status.resetCreditsCount == 1)
    #expect(status.nextCreditExpiresAt != nil)
}

@Test(arguments: [401, 403, 429, 500])
func providerErrorsDoNotMeanExhaustedSubscription(_ code: Int) async {
    let stub = StubSession { _ in (code, #"{"error":"fixture"}"#) }
    defer { stub.close() }
    let codex = await ChatGPTService(session: stub.session).fetchLimitStatus(for: AccountCredential(provider: .chatgpt, title: "Work", token: "eyJ.fixture"))
    let claude = await ClaudeService(session: stub.session, localToken: {
        Issue.record("A manual account must never fall back to local credentials")
        return "unused-fixture"
    }).fetchLimitStatus(for: AccountCredential(provider: .claude, title: "Work", token: "sk-ant-oat-fixture"))
    #expect(codex.healthState == (code == 429 ? .unavailable : .error))
    #expect(claude.healthState == (code == 429 ? .unavailable : .error))
    #expect(codex.resetDate == nil)
    #expect(claude.resetDate == nil)
}

@Test func apiKeysNeverTriggerGenerationOrQuotaRequests() async {
    let stub = StubSession { _ in
        Issue.record("An API key must not trigger a network request")
        return (500, "{}")
    }
    defer { stub.close() }
    let openai = await ChatGPTService(session: stub.session).fetchLimitStatus(for: AccountCredential(provider: .chatgpt, title: "API", token: "sk-fixture"))
    let claude = await ClaudeService(session: stub.session, localToken: { nil }).fetchLimitStatus(for: AccountCredential(provider: .claude, title: "API", token: "sk-ant-api-fixture"))
    let gemini = await GeminiService(session: stub.session).fetchLimitStatus(for: AccountCredential(provider: .gemini, title: "API", token: "AIza-fixture"))
    let perplexity = await PerplexityService(session: stub.session).fetchLimitStatus(for: AccountCredential(provider: .perplexity, title: "API", token: "pplx-fixture"))
    #expect([openai, claude, gemini, perplexity].allSatisfy { $0.healthState == .unavailable })
}

@Test func missingAndUnrecognizedResponsesStayUnavailable() async {
    let stub = StubSession { _ in (200, "{}") }
    defer { stub.close() }
    let codex = await ChatGPTService(session: stub.session).fetchLimitStatus(for: AccountCredential(provider: .chatgpt, title: "Work", token: "eyJ.fixture"))
    let claude = await ClaudeService(session: stub.session, localToken: { nil }).fetchLimitStatus(for: AccountCredential(provider: .claude, title: "Work", token: "sk-ant-oat-fixture"))
    let perplexity = await PerplexityService(session: stub.session).fetchLimitStatus(for: AccountCredential(provider: .perplexity, title: "Work", token: "fixture"))
    #expect([codex, claude, perplexity].allSatisfy { $0.healthState == .unavailable })
}

@Test func antigravityRefreshesOnlyExplicitLocalProfileAndParsesLiveQuota() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("AILimiterTests-\(UUID().uuidString)")
    let profile = home.appendingPathComponent(".t3/userdata/providers/antigravity/test/acp_token.json")
    try FileManager.default.createDirectory(at: profile.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let data = try JSONSerialization.data(withJSONObject: ["client_id": "fixture-client", "client_secret": "fixture+secret", "refresh_token": "fixture-refresh", "project_id": "fixture-project"])
    try data.write(to: profile)
    let stub = StubSession { request in
        if request.url?.host == "oauth2.googleapis.com" {
            #expect(request.httpMethod == "POST")
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("client_secret=fixture%2Bsecret"))
            return (200, #"{"access_token":"fixture-access","expires_in":3600}"#)
        }
        #expect(request.url?.host == "daily-cloudcode-pa.googleapis.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
        return (200, #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.75,"resetTime":"2099-01-01T00:00:00Z"}]}]}"#)
    }
    defer { stub.close() }
    let service = GeminiService(session: stub.session, home: home)
    let status = await service.fetchLimitStatus(for: AccountCredential(provider: .gemini, title: "Local", token: "auto"))
    #expect(status.healthState == .normal)
    #expect(status.windows.first?.usedPercent == 25)
    // A manually configured AI Studio account must not read the existing local profile.
    let manual = await service.fetchLimitStatus(for: AccountCredential(provider: .gemini, title: "Work API", token: "AIza-fixture"))
    #expect(manual.healthState == .unavailable)
}

@Test func multipleAntigravityProfilesDoNotSelectAnArbitraryAccount() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("AILimiterTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    for name in ["personal", "work"] {
        let profile = home.appendingPathComponent(".t3/userdata/providers/antigravity/\(name)/acp_token.json")
        try FileManager.default.createDirectory(at: profile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: profile)
    }
    let stub = StubSession { _ in Issue.record("Ambiguous profiles must not be queried"); return (500, "{}") }
    defer { stub.close() }
    let service = GeminiService(session: stub.session, home: home)
    let status = await service.fetchLimitStatus(for: AccountCredential(provider: .gemini, title: "Local", token: "auto"))
    #expect(status.healthState == .unavailable)
    #expect(status.statusDescription.contains("více"))
}

@Test func explicitCodexProfileUsesOnlySelectedCredentialsAndAccountID() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AILimiterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = directory.appendingPathComponent("selected.json")
    try Data(#"{"tokens":{"access_token":"eyJ.selected-fixture","account_id":"selected-account"}}"#.utf8).write(to: profile)
    let stub = StubSession { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eyJ.selected-fixture")
        #expect(request.value(forHTTPHeaderField: "Chatgpt-Account-Id") == "selected-account")
        #expect(request.value(forHTTPHeaderField: "originator") == ProviderClientIdentity.codexOriginator)
        return (200, #"{"rate_limit":{"primary_window":{"used_percent":5}}}"#)
    }
    defer { stub.close() }
    let service = ChatGPTService(session: stub.session, home: directory)
    let status = await service.fetchLimitStatus(for: AccountCredential(provider: .chatgpt, title: "Selected", token: "auto", profilePath: profile.path))
    #expect(status.windows.first?.usedPercent == 5)
}

@Test func explicitClaudeProfileDoesNotReadDefaultKeychain() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AILimiterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = directory.appendingPathComponent("selected.json")
    try Data(#"{"claudeAiOauth":{"accessToken":"selected-oauth-fixture"}}"#.utf8).write(to: profile)
    let stub = StubSession { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer selected-oauth-fixture")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == ProviderClientIdentity.claudeUserAgent)
        return (200, #"{"five_hour":{"utilization":12}}"#)
    }
    defer { stub.close() }
    let service = ClaudeService(session: stub.session, localToken: { Issue.record("Selected file must bypass Keychain"); return nil })
    let status = await service.fetchLimitStatus(for: AccountCredential(provider: .claude, title: "Selected", token: "auto", profilePath: profile.path))
    #expect(status.windows.first?.usedPercent == 12)
}

@Test func unavailableSelectedProfilesNeverFallBackOrSendRequests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AILimiterTests-\(UUID().uuidString)")
    let defaultFile = directory.appendingPathComponent(".codex/auth.json")
    try FileManager.default.createDirectory(at: defaultFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(#"{"tokens":{"access_token":"eyJ.default-fixture"}}"#.utf8).write(to: defaultFile)
    let stub = StubSession { _ in Issue.record("Missing selected profile must not use another account"); return (500, "{}") }
    defer { stub.close() }
    let missing = directory.appendingPathComponent("missing.json").path
    let codex = await ChatGPTService(session: stub.session, home: directory).fetchLimitStatus(for: AccountCredential(provider: .chatgpt, title: "Selected", token: "auto", profilePath: missing))
    let claude = await ClaudeService(session: stub.session, localToken: { Issue.record("Must not fall back to Keychain"); return nil }).fetchLimitStatus(for: AccountCredential(provider: .claude, title: "Selected", token: "auto", profilePath: missing))
    let antigravity = await GeminiService(session: stub.session, home: directory).fetchLimitStatus(for: AccountCredential(provider: .gemini, title: "Selected", token: "auto", profilePath: missing))
    #expect([codex, claude, antigravity].allSatisfy { $0.healthState == .error })
}

@Test func explicitAntigravityProfileDoesNotRequireT3Directory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AILimiterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = directory.appendingPathComponent("selected.json")
    try Data(#"{"client_id":"selected-client","client_secret":"selected-secret","refresh_token":"selected-refresh","project_id":"selected-project"}"#.utf8).write(to: profile)
    let stub = StubSession { request in
        if request.url?.host == "oauth2.googleapis.com" {
            #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("refresh_token=selected-refresh"))
            return (200, #"{"access_token":"selected-access","expires_in":3600}"#)
        }
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer selected-access")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == ProviderClientIdentity.antigravityUserAgent)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("selected-project"))
        return (200, #"{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.8}]}"#)
    }
    defer { stub.close() }
    let service = GeminiService(session: stub.session, home: directory)
    let status = await service.fetchLimitStatus(for: AccountCredential(provider: .gemini, title: "Selected", token: "auto", profilePath: profile.path))
    #expect(status.healthState == .normal)
    #expect(abs((status.windows.first?.usedPercent ?? 0) - 20) < 0.001)
}

@Test func profilePathsMustBeExplicitAbsoluteFiles() {
    let account = AccountCredential(provider: .chatgpt, title: "Relative", token: "auto", profilePath: "relative/auth.json")
    #expect(throws: LocalProfile.ProfileError.self) { try LocalProfile.selectedFile(for: account) }
}
