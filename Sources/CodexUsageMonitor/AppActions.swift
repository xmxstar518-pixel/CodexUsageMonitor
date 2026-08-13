import AppKit
import Foundation

@MainActor
enum AppActions {
    static func confirmAndUninstall(language: AppLanguage) {
        let l10n = L10n(language: language)
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension.lowercased() == "app",
              Bundle.main.bundleIdentifier == "com.xmxstar.CodexUsageMonitor" else {
            showMessage(
                title: l10n.currentVersionCannotUninstall,
                message: l10n.runBuiltAppToUninstall,
                l10n: l10n
            )
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = l10n.uninstallQuestion
        alert.informativeText = l10n.uninstallExplanation
        alert.addButton(withTitle: l10n.uninstallButton)
        alert.addButton(withTitle: l10n.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let script = #"""
        sleep 1
        target="$1"
        case "$target" in
          *.app) ;;
          *) exit 2 ;;
        esac
        bundle_id=$(/usr/bin/defaults read "$target/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
        [ "$bundle_id" = "com.xmxstar.CodexUsageMonitor" ] || exit 3
        /bin/rm -rf -- "$target"
        /usr/bin/defaults delete com.xmxstar.CodexUsageMonitor >/dev/null 2>&1 || true
        /bin/rm -rf -- "$HOME/Library/Caches/com.xmxstar.CodexUsageMonitor"
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "codex-usage-monitor-uninstaller", bundleURL.path]
        do {
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            showMessage(title: l10n.uninstallerFailed, message: error.localizedDescription, l10n: l10n)
        }
    }

    private static func showMessage(title: String, message: String, l10n: L10n) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: l10n.ok)
        alert.runModal()
    }
}
