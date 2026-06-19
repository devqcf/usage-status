import Foundation
import Combine

struct ToolConfig: Identifiable, Equatable, Sendable {
    enum Provider: String, Sendable {
        case antigravity
        case claude
        case codex
    }

    let provider: Provider
    let name: String
    let isEnabled: Bool

    var id: Provider { provider }

    static let defaults = [
        ToolConfig(provider: .antigravity, name: "Antigravity", isEnabled: true),
        ToolConfig(provider: .claude, name: "Claude Code", isEnabled: true),
        ToolConfig(provider: .codex, name: "Codex", isEnabled: true)
    ]
}

struct UsageWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

struct ToolUsage: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case available
        case unavailable(String)
        case error(String)
    }

    let primary: UsageWindow?
    let secondary: UsageWindow?
    let state: State
    let updatedAt: Date?

    nonisolated static func unavailable(_ reason: String) -> ToolUsage {
        ToolUsage(primary: nil, secondary: nil, state: .unavailable(reason), updatedAt: nil)
    }
}

@MainActor
final class UsageManager: ObservableObject {
    @Published private(set) var configs = ToolConfig.defaults
    @Published private(set) var usage: [ToolConfig.Provider: ToolUsage] = [:]
    @Published private(set) var isRefreshing = false

    private var monitors: [DirectoryMonitor] = []
    private var refreshTask: Task<Void, Never>?
    private var minuteTimer: Timer?

    init(startMonitoring: Bool = true) {
        for config in configs {
            usage[config.provider] = .unavailable("Checking local data…")
        }

        if startMonitoring {
            setupMonitors()
            forceRefresh()
            let manager = WeakUsageManager(self)
            minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in
                    manager.value?.objectWillChange.send()
                }
            }
        }
    }

    func usage(for config: ToolConfig) -> ToolUsage {
        usage[config.provider] ?? .unavailable("No usage data")
    }

    func forceRefresh() {
        refreshTask?.cancel()
        isRefreshing = true

        refreshTask = Task {
            let results = await UsageLoader.loadAll()
            guard !Task.isCancelled else { return }
            usage = results
            isRefreshing = false
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isRefreshing = true
            let results = await UsageLoader.loadAll()
            guard !Task.isCancelled else { return }
            usage = results
            isRefreshing = false
        }
    }

    private func setupMonitors() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".claude", isDirectory: true),
            home.appendingPathComponent(".gemini", isDirectory: true)
        ]

        monitors = directories.compactMap { directory in
            guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
            let manager = WeakUsageManager(self)
            let monitor = DirectoryMonitor(url: directory) {
                Task { @MainActor in manager.value?.scheduleRefresh() }
            }
            monitor.start()
            return monitor
        }
    }

    deinit {
        refreshTask?.cancel()
        minuteTimer?.invalidate()
        monitors.forEach { $0.stop() }
    }
}

private nonisolated final class WeakUsageManager: @unchecked Sendable {
    weak var value: UsageManager?

    init(_ value: UsageManager) {
        self.value = value
    }
}

private nonisolated final class DirectoryMonitor: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "space.meoa.usage-status.file-monitor")
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        stop()
    }
}

enum UsageLoader {
    nonisolated static func loadAll(home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> [ToolConfig.Provider: ToolUsage] {
        await Task.detached(priority: .utility) {
            [
                .codex: loadCodex(home: home),
                .claude: loadUnsupportedProvider(
                    paths: [
                        home.appendingPathComponent(".claude/history.jsonl"),
                        home.appendingPathComponent(".claude/projects")
                    ],
                    missingMessage: "Claude local data not found",
                    presentMessage: "Claude logs do not expose quota percentage"
                ),
                .antigravity: loadUnsupportedProvider(
                    paths: [
                        home.appendingPathComponent(".gemini/antigravity-cli/history.jsonl"),
                        home.appendingPathComponent(".gemini")
                    ],
                    missingMessage: "Antigravity local data not found",
                    presentMessage: "Antigravity logs do not expose quota percentage"
                )
            ]
        }.value
    }

    nonisolated static func loadCodex(home: URL) -> ToolUsage {
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sessions.path) else {
            return .unavailable("Codex session data not found")
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable("Codex session data is unreadable")
        }

        let files: [(URL, Date)] = enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { return nil }
            return (url, values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.1 > $1.1 }

        for (file, modifiedAt) in files {
            if let snapshot = latestCodexSnapshot(in: file, fallbackDate: modifiedAt) {
                return snapshot
            }
        }
        return .unavailable("No Codex rate-limit snapshot yet")
    }

    nonisolated static func latestCodexSnapshot(in file: URL, fallbackDate: Date = .distantPast) -> ToolUsage? {
        guard let data = try? Data(contentsOf: file),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in content.split(separator: "\n").reversed() {
            guard let lineData = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any],
                  let primary = parseWindow(rateLimits["primary"]),
                  let secondary = parseWindow(rateLimits["secondary"]) else {
                continue
            }

            let timestamp = (root["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return ToolUsage(
                primary: primary,
                secondary: secondary,
                state: .available,
                updatedAt: timestamp ?? fallbackDate
            )
        }
        return nil
    }

    nonisolated private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = number(object["used_percent"]),
              let windowMinutes = number(object["window_minutes"]) else {
            return nil
        }
        let resetSeconds = number(object["resets_at"])
        return UsageWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowMinutes: Int(windowMinutes),
            resetsAt: resetSeconds.map(Date.init(timeIntervalSince1970:))
        )
    }

    nonisolated private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    nonisolated private static func loadUnsupportedProvider(
        paths: [URL],
        missingMessage: String,
        presentMessage: String
    ) -> ToolUsage {
        let exists = paths.contains { FileManager.default.fileExists(atPath: $0.path) }
        return .unavailable(exists ? presentMessage : missingMessage)
    }
}
