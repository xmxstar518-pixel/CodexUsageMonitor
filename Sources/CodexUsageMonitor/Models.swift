import Foundation

enum UsageLevel: Equatable, Sendable {
    case healthy
    case moderate
    case low
    case critical
}

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var level: UsageLevel {
        switch remainingPercent {
        case ..<15: return .critical
        case ..<35: return .low
        case ..<65: return .moderate
        default: return .healthy
        }
    }
}

struct UsageBucket: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let planType: String?
    let windows: [UsageWindow]
    let creditBalance: Double?
    let rateLimitReachedType: String?
}

struct UsageSnapshot: Equatable, Sendable {
    let accountType: String?
    let planType: String?
    let buckets: [UsageBucket]
    let fetchedAt: Date

    var headlineRemainingPercent: Double? {
        buckets.first(where: { $0.id == "codex" })?.windows.first?.remainingPercent
            ?? buckets.first?.windows.first?.remainingPercent
    }
}

enum UsageMonitorError: Error, Sendable {
    case codexNotFound
    case launchFailed(String)
    case timedOut
    case serverFailed(String)
    case authenticationRequired
    case malformedResponse

}
