import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static func detect(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let override = commandLineOverride(in: arguments)
            ?? environment["CODEX_USAGE_MONITOR_LANGUAGE"],
           let language = from(identifier: override) {
            return language
        }

        return preferredLanguages.compactMap({ from(identifier: $0) }).first ?? .english
    }

    static func from(identifier: String) -> AppLanguage? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh") { return .simplifiedChinese }
        if normalized.hasPrefix("en") { return .english }
        return nil
    }

    private static func commandLineOverride(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--language=") {
                return String(argument.dropFirst("--language=".count))
            }
            if argument == "--language", arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
        }
        return nil
    }
}

struct L10n: Sendable {
    let language: AppLanguage

    var locale: Locale { language.locale }
    var appName: String { pick("Codex 用量监控", "Codex Usage Monitor") }
    var title: String { pick("Codex 用量", "Codex Usage") }
    var loading: String { pick("正在读取 Codex 用量…", "Reading Codex usage…") }
    var unavailable: String { pick("暂时无法读取用量", "Unable to read usage") }
    var retryLater: String { pick("请稍后重试", "Please try again later") }
    var refreshNow: String { pick("立即刷新", "Refresh now") }
    var pinWindow: String { pick("固定浮窗", "Pin Window") }
    var unpinWindow: String { pick("取消固定", "Unpin Window") }
    var languageMenu: String { pick("语言", "Language") }
    var windowOpacity: String { pick("浮窗透明度", "Window Opacity") }
    var simplifiedChinese: String { pick("简体中文", "Simplified Chinese") }
    var english: String { pick("英文", "English") }
    var quit: String { pick("退出", "Quit") }
    var uninstall: String { pick("卸载应用…", "Uninstall App…") }
    var unknownPlan: String { pick("未知计划", "Unknown plan") }
    var noUsageWindow: String { pick("暂无可展示的限额窗口", "No usage window available") }
    var noUsageWindowExplanation: String {
        pick("Codex 没有为此账户返回活动限额窗口。可用性可能取决于计划、地区或工作区设置。",
             "Codex did not return an active quota window for this account. Availability can depend on the plan, region, or workspace settings.")
    }
    var bucketWithoutWindow: String { pick("此项目暂无活动限额窗口", "No active quota window for this item") }
    var usageLimitReached: String { pick("已达到用量上限", "Usage limit reached") }
    var updatedAt: String { pick("更新于", "Updated") }
    var remaining: String { pick("剩余", "Remaining") }
    var used: String { pick("已用", "Used") }
    var reset: String { pick("重置", "reset") }
    var currentVersionCannotUninstall: String { pick("当前版本不能自助卸载", "This version cannot uninstall itself") }
    var runBuiltAppToUninstall: String {
        pick("请运行构建后的 .app，再从菜单选择卸载。源码目录不会被删除。",
             "Run the built .app and choose Uninstall from its menu. The source directory will not be deleted.")
    }
    var uninstallQuestion: String { pick("卸载 Codex 用量监控？", "Uninstall Codex Usage Monitor?") }
    var uninstallExplanation: String {
        pick("将删除当前应用和本地偏好设置。项目源码与 Codex 登录信息不会被删除。",
             "This removes the app and its local preferences. Project source and Codex sign-in data will not be deleted.")
    }
    var uninstallButton: String { pick("卸载", "Uninstall") }
    var cancel: String { pick("取消", "Cancel") }
    var uninstallerFailed: String { pick("无法启动卸载程序", "Could not start the uninstaller") }
    var ok: String { pick("好", "OK") }

    func creditsRemaining(_ value: String) -> String {
        pick("剩余 Credits：\(value)", "Credits remaining: \(value)")
    }

    func windowLabel(for window: UsageWindow) -> String {
        if window.id.hasSuffix("-primary") { return pick("主要窗口", "Primary window") }
        if window.id.hasSuffix("-secondary") { return pick("次要窗口", "Secondary window") }
        return window.label
    }

    func duration(minutes: Int) -> String {
        if minutes % 10_080 == 0 { return durationValue(minutes / 10_080, zhUnit: "周", enUnit: "week") }
        if minutes % 1_440 == 0 { return durationValue(minutes / 1_440, zhUnit: "天", enUnit: "day") }
        if minutes % 60 == 0 { return durationValue(minutes / 60, zhUnit: "小时", enUnit: "hour") }
        return durationValue(minutes, zhUnit: "分钟", enUnit: "minute")
    }

    func errorMessage(for error: UsageMonitorError) -> String {
        switch error {
        case .codexNotFound:
            return pick("未找到 Codex 命令。请先安装或打开 ChatGPT/Codex 桌面应用。",
                        "Codex was not found. Install or open the ChatGPT/Codex desktop app first.")
        case .launchFailed(let message):
            return pick("无法启动 Codex App Server：\(message)", "Could not start Codex App Server: \(message)")
        case .timedOut:
            return pick("读取用量超时，请稍后重试。", "Reading usage timed out. Please try again later.")
        case .serverFailed(let message):
            return pick("Codex 返回错误：\(message)", "Codex returned an error: \(message)")
        case .authenticationRequired:
            return pick("尚未登录 ChatGPT。请先在 Codex 中完成登录。",
                        "You are not signed in to ChatGPT. Sign in through Codex first.")
        case .malformedResponse:
            return pick("Codex 返回了无法识别的用量数据。", "Codex returned unrecognized usage data.")
        }
    }

    private func durationValue(_ value: Int, zhUnit: String, enUnit: String) -> String {
        switch language {
        case .simplifiedChinese:
            return "\(value) \(zhUnit)窗口"
        case .english:
            return "\(value) \(enUnit)\(value == 1 ? "" : "s") window"
        }
    }

    private func pick(_ chinese: String, _ english: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
