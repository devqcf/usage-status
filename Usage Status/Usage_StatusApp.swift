import SwiftUI

@main
struct Usage_StatusApp: App {
    @StateObject private var manager = UsageManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(manager: manager)
        } label: {
            MenuBarCompositeLabel(configs: manager.configs, usage: manager.usage)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarCompositeLabel: View {
    let configs: [ToolConfig]
    let usage: [ToolConfig.Provider: ToolUsage]

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Image(systemName: "chart.bar")
        }
    }

    private var renderedImage: NSImage? {
        let renderer = ImageRenderer(
            content: MenuBarLabelContent(configs: configs, usage: usage)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}

private struct MenuBarLabelContent: View {
    let configs: [ToolConfig]
    let usage: [ToolConfig.Provider: ToolUsage]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(configs.filter(\.isEnabled)) { config in
                HStack(spacing: 3) {
                    ProviderIcon(provider: config.provider)
                    gauge(for: usage[config.provider]?.primary)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 2)
        .frame(height: 18)
    }

    private func gauge(for window: UsageWindow?) -> some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.2), lineWidth: 1.2)
            if let window {
                Circle()
                    .trim(from: 0, to: window.remainingPercent / 100)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 6, weight: .bold))
            }
        }
        .frame(width: 9, height: 9)
    }
}
