//
//  Usage_StatusApp.swift
//  Usage Status
//
//  Created by deargo on 19.06.2026.
//

import SwiftUI

@main
struct Usage_StatusApp: App {
    @StateObject private var manager = UsageManager()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            menuBarImage
        }
        .menuBarExtraStyle(.window)
    }
    
    private var menuBarImage: some View {
        let enabledConfigs = manager.configs.filter { $0.isEnabled }
        
        let view = MenuBarLabelView(configs: enabledConfigs, manager: manager)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0 // Render at high-density for Retina screens
        
        if let nsImage = renderer.nsImage {
            nsImage.isTemplate = true // Enables automatic light/dark theme tinting
            return Image(nsImage: nsImage)
        }
        
        // Fallback standard symbol if renderer fails
        return Image(systemName: "sparkles")
    }
}

// MARK: - Menu Bar Renderable SwiftUI View
struct MenuBarLabelView: View {
    let configs: [ToolConfig]
    let manager: UsageManager
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(configs) { config in
                let stats = manager.stats(for: config)
                let pct = stats.limit5h > 0 ? Double(stats.remaining5h) / Double(stats.limit5h) : 0.0
                
                HStack(spacing: 4) {
                    Image(imageAssetName(for: config.name))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                    
                    // Circular progress gauge
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.25), lineWidth: 1.2)
                            .frame(width: 8, height: 8)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(1.0, max(0.0, pct))))
                            .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                            .frame(width: 8, height: 8)
                            .rotationEffect(Angle(degrees: -90))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.clear)
    }
    
    private func imageAssetName(for name: String) -> String {
        switch name {
        case "Antigravity": return "antigravity_logo"
        case "Claude Code": return "claude_code_logo"
        case "Codex": return "codex_logo"
        default: return ""
        }
    }
}
