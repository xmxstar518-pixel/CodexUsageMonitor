import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    let language: AppLanguage
    let l10n: L10n
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var refreshInterval: TimeInterval = 60 {
        didSet { restartTimer() }
    }

    private let client = CodexAppServerClient()
    private var timer: Timer?
    private var hasStarted = false
    private let isDemoMode: Bool

    init(
        language: AppLanguage = .detect(),
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.language = language
        self.l10n = L10n(language: language)
        self.isDemoMode = arguments.contains("--demo")
        if isDemoMode {
            self.snapshot = Self.demoSnapshot
        }
    }

    var menuTitle: String {
        guard let remaining = snapshot?.headlineRemainingPercent else { return "Codex" }
        return "\(Int(remaining.rounded()))%"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !isDemoMode else { return }
        restartTimer()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.fetchUsage()
            errorMessage = nil
        } catch let error as UsageMonitorError {
            errorMessage = l10n.errorMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        guard hasStarted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        timer?.tolerance = min(10, refreshInterval * 0.1)
    }

    private static var demoSnapshot: UsageSnapshot {
        let reset = Date().addingTimeInterval(3 * 24 * 60 * 60)
        return UsageSnapshot(
            accountType: "chatgpt",
            planType: "pro",
            buckets: [
                UsageBucket(
                    id: "codex",
                    name: "Codex",
                    planType: "pro",
                    windows: [UsageWindow(
                        id: "codex-primary",
                        label: "Primary window",
                        usedPercent: 34,
                        durationMinutes: 10_080,
                        resetsAt: reset
                    )],
                    creditBalance: nil
                ),
                UsageBucket(
                    id: "codex-spark",
                    name: "GPT-5.3-Codex-Spark",
                    planType: "pro",
                    windows: [UsageWindow(
                        id: "codex-spark-primary",
                        label: "Primary window",
                        usedPercent: 0,
                        durationMinutes: 10_080,
                        resetsAt: reset.addingTimeInterval(2 * 24 * 60 * 60)
                    )],
                    creditBalance: nil
                )
            ],
            fetchedAt: Date()
        )
    }
}
