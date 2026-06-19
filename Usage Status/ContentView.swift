import SwiftUI

struct ContentView: View {
    @StateObject private var manager = UsageManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(manager: manager)
            
            Divider()
                .opacity(0.15)
            
            VStack(spacing: 14) {
                let enabledTools = manager.configs.filter { $0.isEnabled }
                
                if enabledTools.isEmpty {
                    Text("No active trackers.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(enabledTools) { config in
                        ToolRowView(config: config, manager: manager)
                        
                        if config.name != enabledTools.last?.name {
                            Divider()
                                .opacity(0.08)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 260)
        .background(Color.clear)
    }
}

// MARK: - Header View
struct HeaderView: View {
    @ObservedObject var manager: UsageManager
    
    var body: some View {
        HStack {
            Text("Limits")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    manager.forceRefresh()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh logs")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Tool Row View
struct ToolRowView: View {
    let config: ToolConfig
    @ObservedObject var manager: UsageManager
    
    var body: some View {
        let stats = manager.stats(for: config)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                toolIcon(for: config.name)
                    .foregroundColor(.primary)
                Text(config.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: 6) {
                CompactLimitRow(
                    label: "5-Hour",
                    used: stats.used5h,
                    limit: stats.limit5h,
                    pct: stats.pct5h,
                    nextReset: stats.next5hReset
                )
                
                CompactLimitRow(
                    label: "Weekly",
                    used: stats.usedWeekly,
                    limit: stats.limitWeekly,
                    pct: stats.pctWeekly,
                    nextReset: stats.nextWeeklyReset
                )
            }
        }
    }
    
    @ViewBuilder
    private func toolIcon(for name: String) -> some View {
        switch name {
        case "Antigravity":
            Image("antigravity_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
        case "Claude Code":
            Image("claude_code_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
        case "Codex":
            Image("codex_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
        default:
            Image(systemName: "circle")
                .font(.system(size: 12))
        }
    }
}

// MARK: - Compact Limit Row View
struct CompactLimitRow: View {
    let label: String
    let used: Int
    let limit: Int
    let pct: Double
    let nextReset: TimeInterval?
    
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                if pct > 0 && nextReset != nil {
                    Text(formatShortCountdown(nextReset))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(used)/\(limit)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            // Slim monochrome progress line
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 3)
                    
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * CGFloat(min(1.0, pct)), height: 3)
                }
            }
            .frame(height: 3)
        }
    }
    
    private func formatShortCountdown(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds else { return "" }
        let intSecs = Int(seconds)
        if intSecs < 60 {
            return "(\(intSecs)s)"
        }
        let mins = intSecs / 60
        if mins < 60 {
            return "(\(mins)m)"
        }
        let hours = mins / 60
        if hours < 24 {
            return "(\(hours)h)"
        }
        let days = hours / 24
        return "(\(days)d)"
    }
}

#Preview {
    ContentView()
}
