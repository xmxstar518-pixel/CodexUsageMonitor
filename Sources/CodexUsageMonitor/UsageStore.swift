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

    init(language: AppLanguage = .detect()) {
        self.language = language
        self.l10n = L10n(language: language)
    }

    var menuTitle: String {
        guard let remaining = snapshot?.headlineRemainingPercent else { return "Codex" }
        return "\(Int(remaining.rounded()))%"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
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
}
