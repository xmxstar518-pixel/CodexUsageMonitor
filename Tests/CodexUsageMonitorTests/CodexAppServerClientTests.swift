import Foundation
import Testing
@testable import CodexUsageMonitor

@Test func parsesMultipleRateLimitBuckets() throws {
    let lines = [
        #"{"id":0,"result":{"userAgent":"test"}}"#,
        #"{"id":1,"result":{"account":{"type":"chatgpt","planType":"pro"},"requiresOpenaiAuth":true}}"#,
        #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1787011237}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1787011237},"secondary":null,"planType":"pro"},"codex_other":{"limitId":"codex_other","limitName":"Spark","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1787192948},"secondary":null}}}}"#
    ].joined(separator: "\n")

    let snapshot = try CodexAppServerClient.parse(Data(lines.utf8), fetchedAt: Date(timeIntervalSince1970: 0))

    #expect(snapshot.planType == "pro")
    #expect(snapshot.buckets.count == 2)
    #expect(snapshot.buckets[0].id == "codex")
    #expect(snapshot.buckets[0].windows[0].remainingPercent == 75)
    #expect(snapshot.buckets[1].name == "Spark")
    #expect(snapshot.buckets[1].windows[0].durationMinutes == 10_080)
}

@Test func parsesBackwardCompatibleSingleBucket() throws {
    let line = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":80,"windowDurationMins":60,"resetsAt":1787011237},"secondary":null}}}"#
    let snapshot = try CodexAppServerClient.parse(Data(line.utf8))
    #expect(snapshot.buckets.count == 1)
    #expect(snapshot.headlineRemainingPercent == 20)
}

@Test func fallsBackToSingleBucketWhenMultiBucketMapIsEmpty() throws {
    let line = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":30,"windowDurationMins":60,"resetsAt":1787011237}},"rateLimitsByLimitId":{}}}"#
    let snapshot = try CodexAppServerClient.parse(Data(line.utf8))
    #expect(snapshot.buckets.count == 1)
    #expect(snapshot.headlineRemainingPercent == 70)
}

@Test func parsesAllCurrentChatGPTPlanLabels() throws {
    let plans = ["free", "go", "plus", "pro", "business", "edu", "enterprise"]

    for plan in plans {
        let lines = [
            #"{"id":1,"result":{"account":{"type":"chatgpt","planType":"\#(plan)"},"requiresOpenaiAuth":true}}"#,
            #"{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1787011237},"secondary":null}}}}"#
        ].joined(separator: "\n")

        let snapshot = try CodexAppServerClient.parse(Data(lines.utf8))
        #expect(snapshot.planType == plan)
        #expect(snapshot.buckets.first?.planType == plan)
        #expect(snapshot.headlineRemainingPercent == 90)
    }
}

@Test func preservesFreeAccountWhenNoQuotaWindowIsReturned() throws {
    let lines = [
        #"{"id":1,"result":{"account":{"type":"chatgpt","planType":"free"},"requiresOpenaiAuth":true}}"#,
        #"{"id":2,"result":{"rateLimits":null,"rateLimitsByLimitId":{}}}"#
    ].joined(separator: "\n")

    let snapshot = try CodexAppServerClient.parse(Data(lines.utf8))
    #expect(snapshot.planType == "free")
    #expect(snapshot.buckets.isEmpty)
    #expect(snapshot.headlineRemainingPercent == nil)
}

@Test func parsesWorkspaceCreditsAndReachedLimitState() throws {
    let lines = [
        #"{"id":1,"result":{"account":{"type":"chatgpt","planType":"business"},"requiresOpenaiAuth":true}}"#,
        #"{"id":2,"result":{"credits":{"remaining":12.5},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1787011237},"secondary":null,"rateLimitReachedType":"primary"}}}}"#
    ].joined(separator: "\n")

    let snapshot = try CodexAppServerClient.parse(Data(lines.utf8))
    #expect(snapshot.buckets.first?.creditBalance == 12.5)
    #expect(snapshot.buckets.first?.rateLimitReachedType == "primary")
    #expect(snapshot.headlineRemainingPercent == 0)
}

@Test func detectsSupportedLanguages() {
    #expect(AppLanguage.from(identifier: "zh-Hans-CN") == .simplifiedChinese)
    #expect(AppLanguage.from(identifier: "zh_CN") == .simplifiedChinese)
    #expect(AppLanguage.from(identifier: "en-US") == .english)
    #expect(AppLanguage.from(identifier: "fr-FR") == nil)
    #expect(AppLanguage.detect(arguments: ["app", "--language=en"], environment: [:]) == .english)
}

@Test func mapsRemainingUsageToGradientLevels() {
    func window(remaining: Double) -> UsageWindow {
        UsageWindow(
            id: "test-\(remaining)",
            label: "Test",
            usedPercent: 100 - remaining,
            durationMinutes: nil,
            resetsAt: nil
        )
    }

    #expect(window(remaining: 100).level == .healthy)
    #expect(window(remaining: 65).level == .healthy)
    #expect(window(remaining: 64.9).level == .moderate)
    #expect(window(remaining: 35).level == .moderate)
    #expect(window(remaining: 34.9).level == .low)
    #expect(window(remaining: 15).level == .low)
    #expect(window(remaining: 14.9).level == .critical)
    #expect(window(remaining: 0).level == .critical)
}

@MainActor
@Test func demoModeUsesSanitizedSnapshot() {
    let store = UsageStore(language: .english, arguments: ["app", "--demo"])
    #expect(store.snapshot?.planType == "pro")
    #expect(store.snapshot?.buckets.count == 2)
    #expect(store.snapshot?.headlineRemainingPercent == 66)
}

@MainActor
@Test func firstLaunchUsesMacOSLanguageAndManualChoicePersists() {
    let suiteName = "CodexUsageMonitorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let firstLaunch = UsageStore(
        arguments: ["app", "--demo"],
        environment: [:],
        preferredLanguages: ["zh-Hans-CN"],
        defaults: defaults
    )
    #expect(firstLaunch.language == .simplifiedChinese)
    firstLaunch.setLanguage(.english)

    let nextLaunch = UsageStore(
        arguments: ["app", "--demo"],
        environment: [:],
        preferredLanguages: ["zh-Hans-CN"],
        defaults: defaults
    )
    #expect(nextLaunch.language == .english)
}

@MainActor
@Test func pinStateToggles() {
    let store = UsageStore(language: .english, arguments: ["app", "--demo"])
    #expect(store.isWindowPinned)
    store.toggleWindowPinned()
    #expect(!store.isWindowPinned)
}

@MainActor
@Test func floatingWindowOpacityPersistsAndClamps() {
    let suiteName = "CodexUsageMonitorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let firstLaunch = UsageStore(language: .english, arguments: ["app", "--demo"], defaults: defaults)
    #expect(firstLaunch.windowOpacity == 1)

    firstLaunch.setWindowOpacity(0.553)
    #expect(firstLaunch.windowOpacity == 0.553)

    let nextLaunch = UsageStore(language: .english, arguments: ["app", "--demo"], defaults: defaults)
    #expect(nextLaunch.windowOpacity == 0.553)

    nextLaunch.setWindowOpacity(0)
    #expect(nextLaunch.windowOpacity == 0.2)
    nextLaunch.setWindowOpacity(2)
    #expect(nextLaunch.windowOpacity == 1)
}
