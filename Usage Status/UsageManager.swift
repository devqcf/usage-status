import Foundation
import Combine
import SwiftUI

struct ToolConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var limit5h: Int
    var limitWeekly: Int
    var logPath: String
    var autoWatch: Bool
    var isEnabled: Bool
    var manualEvents: [Date]
    
    static func == (lhs: ToolConfig, rhs: ToolConfig) -> Bool {
        return lhs.name == rhs.name &&
               lhs.limit5h == rhs.limit5h &&
               lhs.limitWeekly == rhs.limitWeekly &&
               lhs.logPath == rhs.logPath &&
               lhs.autoWatch == rhs.autoWatch &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.manualEvents == rhs.manualEvents
    }
}

class ToolMonitor {
    let toolName: String
    private var fileWatcher: FolderMonitor?
    private var lastCheckedSize: Int64 = 0
    private var logPath: String
    var onUpdate: () -> Void
    
    init(toolName: String, logPath: String, onUpdate: @escaping () -> Void) {
        self.toolName = toolName
        self.logPath = logPath
        self.onUpdate = onUpdate
        startWatching()
    }
    
    func updateLogPath(_ newPath: String) {
        self.logPath = newPath
        startWatching()
    }
    
    private func startWatching() {
        stopWatching()
        
        let expanded = (logPath as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expanded)
        let folderURL = fileURL.deletingLastPathComponent()
        
        // Ensure directory exists
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue {
            let monitor = FolderMonitor(folderURL: folderURL)
            monitor.folderDidChange = { [weak self] in
                DispatchQueue.main.async {
                    self?.onUpdate()
                }
            }
            monitor.startMonitoring()
            self.fileWatcher = monitor
        }
    }
    
    func stopWatching() {
        fileWatcher?.stopMonitoring()
        fileWatcher = nil
    }
    
    deinit {
        stopWatching()
    }
}

class FolderMonitor {
    let folderURL: URL
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "space.meoa.FolderMonitor")
    
    var folderDidChange: (() -> Void)?
    
    init(folderURL: URL) {
        self.folderURL = folderURL
    }
    
    func startMonitoring() {
        guard source == nil else { return }
        
        fileDescriptor = open(folderURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )
        
        source?.setEventHandler { [weak self] in
            self?.folderDidChange?()
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        
        source?.resume()
    }
    
    func stopMonitoring() {
        source?.cancel()
        source = nil
    }
    
    deinit {
        stopMonitoring()
    }
}

class UsageManager: ObservableObject {
    @Published var configs: [ToolConfig] = []
    
    // Cached lists of auto-detected events
    private var autoEvents: [String: [Date]] = [:]
    private var monitors: [String: ToolMonitor] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    
    init() {
        loadConfigs()
        setupMonitors()
        refreshAllAutoEvents()
        
        // Start a timer to tick once per minute to refresh UI and countdowns
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    
    func addManualEvent(for toolName: String) {
        if let idx = configs.firstIndex(where: { $0.name == toolName }) {
            configs[idx].manualEvents.append(Date())
            saveConfigs()
        }
    }
    
    func removeLastEvent(for toolName: String) {
        if let idx = configs.firstIndex(where: { $0.name == toolName }) {
            // Remove the most recent manual event
            if !configs[idx].manualEvents.isEmpty {
                configs[idx].manualEvents.removeLast()
                saveConfigs()
            }
        }
    }
    
    func clearManualEvents(for toolName: String) {
        if let idx = configs.firstIndex(where: { $0.name == toolName }) {
            configs[idx].manualEvents.removeAll()
            saveConfigs()
        }
    }
    
    // Get rolling event list for last N seconds
    func getEvents(for toolName: String, windowInSeconds: TimeInterval) -> [Date] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowInSeconds)
        
        let manual = configs.first(where: { $0.name == toolName })?.manualEvents ?? []
        let auto = autoEvents[toolName] ?? []
        
        let combined = (manual + auto).sorted()
        return combined.filter { $0 >= cutoff }
    }
    
    // Statistics helper for views
    struct ToolStats {
        let remaining5h: Int
        let used5h: Int
        let limit5h: Int
        let pct5h: Double // 0.0 to 1.0
        let next5hReset: TimeInterval? // seconds until oldest in 5h slides out
        
        let remainingWeekly: Int
        let usedWeekly: Int
        let limitWeekly: Int
        let pctWeekly: Double // 0.0 to 1.0
        let nextWeeklyReset: TimeInterval? // seconds until oldest in 7d slides out
    }
    
    func stats(for config: ToolConfig) -> ToolStats {
        let now = Date()
        
        // 5-Hour Window
        let events5h = getEvents(for: config.name, windowInSeconds: 5 * 3600)
        let used5h = events5h.count
        let remaining5h = max(0, config.limit5h - used5h)
        let pct5h = config.limit5h > 0 ? Double(used5h) / Double(config.limit5h) : 0.0
        
        var next5hReset: TimeInterval?
        if let oldest = events5h.first {
            let resetTime = oldest.addingTimeInterval(5 * 3600)
            let diff = resetTime.timeIntervalSince(now)
            if diff > 0 {
                next5hReset = diff
            }
        }
        
        // Weekly Window (7 days)
        let eventsWeekly = getEvents(for: config.name, windowInSeconds: 7 * 24 * 3600)
        let usedWeekly = eventsWeekly.count
        let remainingWeekly = max(0, config.limitWeekly - usedWeekly)
        let pctWeekly = config.limitWeekly > 0 ? Double(usedWeekly) / Double(config.limitWeekly) : 0.0
        
        var nextWeeklyReset: TimeInterval?
        if let oldest = eventsWeekly.first {
            let resetTime = oldest.addingTimeInterval(7 * 24 * 3600)
            let diff = resetTime.timeIntervalSince(now)
            if diff > 0 {
                nextWeeklyReset = diff
            }
        }
        
        return ToolStats(
            remaining5h: remaining5h,
            used5h: used5h,
            limit5h: config.limit5h,
            pct5h: pct5h,
            next5hReset: next5hReset,
            remainingWeekly: remainingWeekly,
            usedWeekly: usedWeekly,
            limitWeekly: config.limitWeekly,
            pctWeekly: pctWeekly,
            nextWeeklyReset: nextWeeklyReset
        )
    }
    
    // Refresh all files manually
    func forceRefresh() {
        refreshAllAutoEvents()
        objectWillChange.send()
    }
    
    // Private loading/saving
    private func loadConfigs() {
        if let data = UserDefaults.standard.data(forKey: "ToolConfigs"),
           let decoded = try? JSONDecoder().decode([ToolConfig].self, from: data) {
            self.configs = decoded
            
            // Backwards compatibility / updates: make sure we have exactly Antigravity, Claude Code, and Codex
            let names = self.configs.map { $0.name }
            if !names.contains("Antigravity") {
                self.configs.append(ToolConfig(name: "Antigravity", limit5h: 50, limitWeekly: 300, logPath: "~/.gemini/antigravity-cli/history.jsonl", autoWatch: true, isEnabled: true, manualEvents: []))
            }
            if !names.contains("Claude Code") {
                self.configs.append(ToolConfig(name: "Claude Code", limit5h: 50, limitWeekly: 300, logPath: "~/.claude/history.jsonl", autoWatch: true, isEnabled: true, manualEvents: []))
            }
            if !names.contains("Codex") {
                self.configs.append(ToolConfig(name: "Codex", limit5h: 15, limitWeekly: 100, logPath: "", autoWatch: false, isEnabled: true, manualEvents: []))
            }
        } else {
            // Default setup
            self.configs = [
                ToolConfig(name: "Antigravity", limit5h: 50, limitWeekly: 300, logPath: "~/.gemini/antigravity-cli/history.jsonl", autoWatch: true, isEnabled: true, manualEvents: []),
                ToolConfig(name: "Claude Code", limit5h: 50, limitWeekly: 300, logPath: "~/.claude/history.jsonl", autoWatch: true, isEnabled: true, manualEvents: []),
                ToolConfig(name: "Codex", limit5h: 15, limitWeekly: 100, logPath: "", autoWatch: false, isEnabled: true, manualEvents: [])
            ]
            saveConfigs()
        }
    }
    
    func saveConfigs() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "ToolConfigs")
        }
        
        // Refresh monitors and data since config changed
        setupMonitors()
        refreshAllAutoEvents()
        objectWillChange.send()
    }
    
    private func setupMonitors() {
        for config in configs {
            guard config.isEnabled && config.autoWatch && !config.logPath.isEmpty else {
                monitors[config.name]?.stopWatching()
                monitors.removeValue(forKey: config.name)
                continue
            }
            
            if let existing = monitors[config.name] {
                existing.updateLogPath(config.logPath)
            } else {
                let monitor = ToolMonitor(toolName: config.name, logPath: config.logPath) { [weak self] in
                    self?.refreshAutoEvents(for: config.name)
                }
                monitors[config.name] = monitor
            }
        }
        
        // Clean up unused monitors
        let activeNames = Set(configs.filter { $0.isEnabled && $0.autoWatch }.map { $0.name })
        for key in monitors.keys {
            if !activeNames.contains(key) {
                monitors[key]?.stopWatching()
                monitors.removeValue(forKey: key)
            }
        }
    }
    
    private func refreshAllAutoEvents() {
        for config in configs {
            refreshAutoEvents(for: config.name)
        }
    }
    
    private func refreshAutoEvents(for toolName: String) {
        guard let config = configs.first(where: { $0.name == toolName }) else { return }
        
        guard config.isEnabled && config.autoWatch && !config.logPath.isEmpty else {
            autoEvents[toolName] = []
            return
        }
        
        let expanded = (config.logPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            autoEvents[toolName] = []
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                return
            }
            
            let lines = content.components(separatedBy: .newlines)
            var dates: [Date] = []
            
            for line in lines {
                if line.isEmpty { continue }
                if let lineData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let timestampMs = json["timestamp"] as? Double {
                    let date = Date(timeIntervalSince1970: timestampMs / 1000.0)
                    dates.append(date)
                }
            }
            
            DispatchQueue.main.async {
                self.autoEvents[toolName] = dates
                self.objectWillChange.send()
            }
        } catch {
            print("Error reading log file for \(toolName): \(error)")
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}
