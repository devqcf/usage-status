import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: UsageManager

    private var enabledTools: [ToolConfig] {
        manager.configs.filter(\.isEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            toolList
        }
        .frame(width: 290)
    }

    private var header: some View {
        HStack {
            Text("Usage limits")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") {
                manager.forceRefresh()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .disabled(manager.isRefreshing)
            .help("Refresh local usage data")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var toolList: some View {
        VStack(spacing: 14) {
            ForEach(Array(enabledTools.enumerated()), id: \.element.id) { index, config in
                ToolRowView(config: config, usage: manager.usage(for: config))
                if index < enabledTools.count - 1 {
                    Divider().opacity(0.08)
                }
            }
        }
        .padding(14)
    }
}

private struct ToolRowView: View {
    let config: ToolConfig
    let usage: ToolUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProviderIcon(provider: config.provider)
                Text(config.name)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if let updatedAt = usage.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            switch usage.state {
            case .available:
                if let primary = usage.primary {
                    LimitRow(window: primary)
                }
                if let secondary = usage.secondary {
                    LimitRow(window: secondary)
                }
            case .unavailable(let reason), .error(let reason):
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LimitRow: View {
    let window: UsageWindow

    private var label: String {
        switch window.windowMinutes {
        case 300: return "5-hour"
        case 10_080: return "Weekly"
        default:
            let hours = window.windowMinutes / 60
            return hours < 24 ? "\(hours)-hour" : "\(hours / 24)-day"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                if let resetsAt = window.resetsAt {
                    Text("resets \(resetsAt, style: .relative)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 12))

            ProgressView(value: window.usedPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(window.usedPercent >= 90 ? .red : .primary)
                .accessibilityLabel("\(label) usage")
                .accessibilityValue("\(Int(window.usedPercent.rounded())) percent used")
        }
    }
}

struct ProviderIcon: View {
    let provider: ToolConfig.Provider

    var body: some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 12, height: 12)
    }

    private var assetName: String {
        switch provider {
        case .antigravity: return "antigravity_logo"
        case .claude: return "claude_code_logo"
        case .codex: return "codex_logo"
        }
    }
}
