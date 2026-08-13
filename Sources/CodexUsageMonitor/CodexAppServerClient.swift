import Foundation
import Darwin

struct CodexAppServerClient: Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let timeout = timeout
        return try await Task.detached(priority: .utility) {
            try Self.fetchUsageSynchronously(timeout: timeout)
        }.value
    }

    private static func fetchUsageSynchronously(timeout: TimeInterval) throws -> UsageSnapshot {
        let executable = try resolveCodexExecutable()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw UsageMonitorError.launchFailed(error.localizedDescription)
        }

        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_usage_monitor",
                        "title": "Codex Usage Monitor",
                        "version": appVersion
                    ]
                ]
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/read", "id": 1, "params": ["refreshToken": false]],
            ["method": "account/rateLimits/read", "id": 2]
        ]

        do {
            for message in messages {
                let data = try JSONSerialization.data(withJSONObject: message)
                input.fileHandleForWriting.write(data)
                input.fileHandleForWriting.write(Data([0x0A]))
            }
        } catch {
            process.terminate()
            throw UsageMonitorError.serverFailed("写入请求失败")
        }

        let responseData: Data
        do {
            responseData = try readResponses(
                from: output.fileHandleForReading.fileDescriptor,
                process: process,
                timeout: timeout
            )
        } catch {
            try? input.fileHandleForWriting.close()
            process.terminate()
            throw error
        }

        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        return try parse(responseData)
    }

    private static func readResponses(from descriptor: Int32, process: Process, timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var collected = Data()
        var pending = Data()
        var responseIDs = Set<Int>()
        var bytes = [UInt8](repeating: 0, count: 8_192)

        while Date() < deadline {
            let remainingMilliseconds = max(1, Int32(deadline.timeIntervalSinceNow * 1_000))
            var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&descriptorState, 1, remainingMilliseconds)
            if pollResult == 0 { break }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw UsageMonitorError.serverFailed("读取响应失败")
            }

            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count <= 0 {
                if process.isRunning { continue }
                break
            }

            let chunk = Data(bytes.prefix(Int(count)))
            collected.append(chunk)
            pending.append(chunk)

            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                   let id = intValue(object["id"]) {
                    responseIDs.insert(id)
                }
            }

            if responseIDs.contains(1), responseIDs.contains(2) {
                return collected
            }
        }

        throw UsageMonitorError.timedOut
    }

    static func parse(_ responseData: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let text = String(data: responseData, encoding: .utf8) ?? ""
        let lines = text.split(whereSeparator: \Character.isNewline)
        var accountResult: [String: Any]?
        var limitsResult: [String: Any]?

        for line in lines {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "未知错误"
                throw UsageMonitorError.serverFailed(message)
            }

            switch Self.intValue(object["id"]) {
            case 1:
                accountResult = object["result"] as? [String: Any]
            case 2:
                limitsResult = object["result"] as? [String: Any]
            default:
                break
            }
        }

        let account = accountResult?["account"] as? [String: Any]
        if accountResult != nil, account == nil,
           (accountResult?["requiresOpenaiAuth"] as? Bool) == true {
            throw UsageMonitorError.authenticationRequired
        }
        guard let limitsResult else {
            throw UsageMonitorError.malformedResponse
        }

        var rawBuckets: [(String, [String: Any])] = []
        if let byID = limitsResult["rateLimitsByLimitId"] as? [String: Any] {
            rawBuckets = byID.compactMap { key, value in
                guard let value = value as? [String: Any] else { return nil }
                return (key, value)
            }
        } else if let single = limitsResult["rateLimits"] as? [String: Any] {
            rawBuckets = [((single["limitId"] as? String) ?? "codex", single)]
        }

        let accountPlan = account?["planType"] as? String
        let buckets = rawBuckets.map { key, raw -> UsageBucket in
            var windows: [UsageWindow] = []
            if let primary = raw["primary"] as? [String: Any],
               let used = doubleValue(primary["usedPercent"]) {
                windows.append(makeWindow(id: "\(key)-primary", label: "主要窗口", raw: primary, used: used))
            }
            if let secondary = raw["secondary"] as? [String: Any],
               let used = doubleValue(secondary["usedPercent"]) {
                windows.append(makeWindow(id: "\(key)-secondary", label: "次要窗口", raw: secondary, used: used))
            }

            let credits = raw["credits"] as? [String: Any]
            let creditBalance = doubleValue(credits?["balance"])
                ?? doubleValue(credits?["remaining"])
                ?? doubleValue(credits?["available"])

            return UsageBucket(
                id: (raw["limitId"] as? String) ?? key,
                name: (raw["limitName"] as? String) ?? (key == "codex" ? "Codex" : key),
                planType: (raw["planType"] as? String) ?? accountPlan,
                windows: windows,
                creditBalance: creditBalance
            )
        }.sorted { lhs, rhs in
            if lhs.id == "codex" { return true }
            if rhs.id == "codex" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        guard !buckets.isEmpty else {
            throw UsageMonitorError.malformedResponse
        }

        return UsageSnapshot(
            accountType: account?["type"] as? String,
            planType: accountPlan ?? buckets.compactMap(\.planType).first,
            buckets: buckets,
            fetchedAt: fetchedAt
        )
    }

    private static func makeWindow(id: String, label: String, raw: [String: Any], used: Double) -> UsageWindow {
        let timestamp = doubleValue(raw["resetsAt"])
        return UsageWindow(
            id: id,
            label: label,
            usedPercent: min(100, max(0, used)),
            durationMinutes: intValue(raw["windowDurationMins"]),
            resetsAt: timestamp.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func resolveCodexExecutable() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_EXECUTABLE"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            NSString(string: "~/.local/bin/codex").expandingTildeInPath,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("codex").path)
            }
        }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw UsageMonitorError.codexNotFound
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
