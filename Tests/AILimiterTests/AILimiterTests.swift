import Testing
import Foundation
@testable import AILimiter

@Test func testUsageWindowCalculations() async throws {
    let now = Date()
    // 5h window (300 mins = 18000s)
    let resetsIn2h = now.addingTimeInterval(7200) // 2h left of 5h window -> 3h elapsed (60% elapsed)

    // Window with 90% used while only 60% elapsed -> gap is +30% -> ahead of pace (burning fast)
    let windowAhead = UsageWindow(
        id: "primary",
        kind: .session,
        label: "5h Session",
        usedPercent: 90.0,
        resetsAt: resetsIn2h,
        windowDurationMins: 300
    )
    #expect(windowAhead.pace == .ahead)
    #expect(windowAhead.remainingPercent == 10.0)
    #expect(windowAhead.resetCountdownString != nil)

    // Window with 20% used while 60% elapsed -> gap is -40% -> under pace (plenty of quota)
    let windowUnder = UsageWindow(
        id: "primary",
        kind: .session,
        label: "5h Session",
        usedPercent: 20.0,
        resetsAt: resetsIn2h,
        windowDurationMins: 300
    )
    #expect(windowUnder.pace == .under)
    #expect(windowUnder.remainingPercent == 80.0)

    // Window with 60% used while 60% elapsed -> gap is 0% -> on pace
    let windowOn = UsageWindow(
        id: "primary",
        kind: .session,
        label: "5h Session",
        usedPercent: 60.0,
        resetsAt: resetsIn2h,
        windowDurationMins: 300
    )
    #expect(windowOn.pace == .on)
}

@Test func testLimitStatusMultiWindow() async throws {
    let session = UsageWindow(
        id: "primary",
        kind: .session,
        label: "5h Session",
        usedPercent: 100.0,
        resetsAt: Date().addingTimeInterval(3600),
        windowDurationMins: 300
    )
    let weekly = UsageWindow(
        id: "secondary",
        kind: .weekly,
        label: "Týdenní limit",
        usedPercent: 45.0,
        resetsAt: Date().addingTimeInterval(86400 * 3),
        windowDurationMins: 10080
    )

    let status = LimitStatus(
        accountId: UUID(),
        provider: .chatgpt,
        usagePercentage: 100.0,
        planName: "ChatGPT Plus",
        statusDescription: "Limit zpráv vyčerpán",
        resetDate: session.resetsAt,
        healthState: .exhausted,
        windows: [session, weekly],
        resetCreditsCount: 2
    )

    #expect(status.healthState == .exhausted)
    #expect(status.windows.count == 2)
    #expect(status.resetCreditsCount == 2)
    #expect(status.windows[0].usedPercent == 100.0)
    #expect(status.windows[1].usedPercent == 45.0)
}

@Test func testAccountCredentialAutoDetection() async throws {
    let autoCred = AccountCredential(
        provider: .chatgpt,
        title: "Codex",
        token: "auto"
    )
    #expect(autoCred.isDemo == false)

    let demoCred = AccountCredential(
        provider: .chatgpt,
        title: "Demo",
        token: "demo"
    )
    #expect(demoCred.isDemo == true)
}
