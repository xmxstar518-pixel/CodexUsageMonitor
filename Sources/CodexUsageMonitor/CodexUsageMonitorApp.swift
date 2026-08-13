import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @StateObject private var store = UsageStore()
    @State private var didShowInitialPanel = false

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView()
                .environmentObject(store)
                .onAppear { store.start() }
        } label: {
            Label(store.menuTitle, systemImage: "gauge.with.dots.needle.67percent")
                .onAppear {
                    store.start()
                    if !didShowInitialPanel {
                        didShowInitialPanel = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            FloatingPanelController.shared.show(store: store)
                        }
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
