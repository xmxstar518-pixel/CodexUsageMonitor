import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @EnvironmentObject private var store: UsageStore

    private var l10n: L10n { store.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let snapshot = store.snapshot {
                VStack(spacing: 8) {
                    ForEach(snapshot.buckets) { bucket in
                        UsageBucketView(bucket: bucket)
                    }
                }
            } else if store.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(l10n.loading)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.0percent")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(l10n.unavailable)
                        .font(.headline)
                    Text(store.errorMessage ?? l10n.retryLater)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }

            if let error = store.errorMessage, store.snapshot != nil {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            Divider()
            controls
        }
        .padding(14)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.title)
                    .font(.title2.weight(.semibold))
                if let snapshot = store.snapshot {
                    Text(statusLine(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(l10n.refreshNow)
            .disabled(store.isLoading)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                FloatingPanelController.shared.show(store: store)
            } label: {
                Label(l10n.pinWindow, systemImage: "pin")
            }
            Spacer()
            Menu {
                Button(l10n.quit) {
                    NSApplication.shared.terminate(nil)
                }
                Divider()
                Button(l10n.uninstall, role: .destructive) {
                    AppActions.confirmAndUninstall(language: store.language)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func statusLine(_ snapshot: UsageSnapshot) -> String {
        let plan = snapshot.planType?.uppercased() ?? l10n.unknownPlan
        let time = snapshot.fetchedAt.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(l10n.locale)
        )
        return "\(plan) · \(l10n.updatedAt) \(time)"
    }
}

struct UsageBucketView: View {
    @EnvironmentObject private var store: UsageStore
    let bucket: UsageBucket

    private var l10n: L10n { store.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(bucket.name)
                    .font(.headline)
                Spacer()
                if let plan = bucket.planType {
                    Text(plan.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            ForEach(bucket.windows) { window in
                UsageWindowView(window: window, showLabel: bucket.windows.count > 1)
            }

            if let credits = bucket.creditBalance {
                Label(l10n.creditsRemaining(credits.formatted(.number.precision(.fractionLength(0...2)))), systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary)
        }
    }
}

struct UsageWindowView: View {
    @EnvironmentObject private var store: UsageStore
    let window: UsageWindow
    let showLabel: Bool

    private var l10n: L10n { store.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                if showLabel {
                    Text(l10n.windowLabel(for: window))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(l10n.remaining) \(window.remainingPercent.formatted(.number.precision(.fractionLength(0...1))))%")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Spacer()
                Text("\(l10n.used) \(window.usedPercent.formatted(.number.precision(.fractionLength(0...1))))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: window.remainingPercent, total: 100)
                .tint(progressColor)

            HStack {
                if let duration = window.durationMinutes {
                    Label(l10n.duration(minutes: duration), systemImage: "clock")
                }
                Spacer()
                if let reset = window.resetsAt {
                    Text("\(reset.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(l10n.locale))) \(l10n.reset)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var progressColor: Color {
        switch window.remainingPercent {
        case ..<15: return .red
        case ..<35: return .orange
        default: return .green
        }
    }

}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelController()
    private var panel: NSPanel?

    func show(store: UsageStore) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let rootView = UsagePopoverView().environmentObject(store)
        let controller = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = store.l10n.title
        panel.contentViewController = controller
        panel.contentMinSize = NSSize(width: 400, height: 320)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
