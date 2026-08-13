import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @EnvironmentObject private var store: UsageStore
    var presentation: Presentation = .menuBar

    enum Presentation: Equatable {
        case menuBar
        case floatingPanel
    }

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
        .frame(
            minWidth: presentation == .floatingPanel ? 360 : 400,
            idealWidth: 400,
            maxWidth: presentation == .floatingPanel ? .infinity : 400,
            minHeight: presentation == .floatingPanel ? 320 : nil,
            maxHeight: presentation == .floatingPanel ? .infinity : nil,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: presentation == .menuBar)
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
                if presentation == .menuBar {
                    FloatingPanelController.shared.show(store: store)
                } else {
                    store.toggleWindowPinned()
                }
            } label: {
                Label(
                    presentation == .menuBar
                        ? l10n.pinWindow
                        : (store.isWindowPinned ? l10n.unpinWindow : l10n.pinWindow),
                    systemImage: presentation == .menuBar
                        ? "pin"
                        : (store.isWindowPinned ? "pin.fill" : "pin.slash")
                )
            }
            .foregroundStyle(
                presentation == .menuBar || store.isWindowPinned
                    ? Color.accentColor
                    : Color.secondary
            )
            Spacer()
            Menu {
                Button {
                    store.setLanguage(.simplifiedChinese)
                } label: {
                    if store.language == .simplifiedChinese {
                        Label(l10n.simplifiedChinese, systemImage: "checkmark")
                    } else {
                        Text(l10n.simplifiedChinese)
                    }
                }
                Button {
                    store.setLanguage(.english)
                } label: {
                    if store.language == .english {
                        Label(l10n.english, systemImage: "checkmark")
                    } else {
                        Text(l10n.english)
                    }
                }
            } label: {
                Image(systemName: "globe")
            }
            .menuStyle(.borderlessButton)
            .help(l10n.languageMenu)
            .fixedSize()
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
    private var isSnapping = false
    private let snapDistance: CGFloat = 14

    func show(store: UsageStore) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let rootView = UsagePopoverView(presentation: .floatingPanel).environmentObject(store)
        let controller = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = store.l10n.title
        panel.contentViewController = controller
        panel.contentMinSize = NSSize(width: 360, height: 380)
        panel.contentMaxSize = NSSize(width: 720, height: 900)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.panel = panel
        setPinned(store.isWindowPinned)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    func windowDidMove(_ notification: Notification) {
        snapToVisibleScreenEdges()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        snapToVisibleScreenEdges()
    }

    func updateTitle(_ title: String) {
        panel?.title = title
    }

    func setPinned(_ isPinned: Bool) {
        panel?.level = isPinned ? .floating : .normal
    }

    private func snapToVisibleScreenEdges() {
        guard let panel, !isSnapping, let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        var origin = frame.origin

        if abs(frame.minX - visible.minX) <= snapDistance {
            origin.x = visible.minX
        } else if abs(frame.maxX - visible.maxX) <= snapDistance {
            origin.x = visible.maxX - frame.width
        }

        if abs(frame.minY - visible.minY) <= snapDistance {
            origin.y = visible.minY
        } else if abs(frame.maxY - visible.maxY) <= snapDistance {
            origin.y = visible.maxY - frame.height
        }

        guard origin != frame.origin else { return }
        isSnapping = true
        panel.setFrameOrigin(origin)
        isSnapping = false
    }
}
