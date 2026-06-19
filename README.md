# ⏳ Usage Status

A lightweight, native macOS menu bar application to track your rolling 5-hour and weekly usage limits for **Google Antigravity**, **Anthropic Claude Code**, and **OpenAI Codex** in real-time.

---

## 📸 Screenshots

### Menu Bar Status
![Menu Bar](assets/menubar.png)

### Live Dashboard
![Dropdown Window](assets/dropdown.png)

---

## ✨ Features

- **🔋 Real-time Log-Watching:** Monitors your local CLI history files (`~/.gemini/antigravity-cli/history.jsonl` and `~/.claude/history.jsonl`) to instantly update your usage counts.
- **🎨 Native Integration:** Clean, monochrome SwiftUI design that seamlessly blends with your macOS menu bar (supports dark & light modes).
- **📈 Legibility-First UI:** Enlarged legibility typography with thin, non-intrusive progress bars and circular menu bar gauges.
- **⏳ Smart Rollover Prediction:** Displays precise, rolling-window countdowns (e.g., `(14m)` or `(2d)`) showing exactly when your limit will refresh.
- **⚡ No Configuration:** Completely configuration-free. Just launch it, and it works.

---

## 🛠️ Installation & Build

### 1. Download
You can download the pre-packaged `.dmg` from the [Releases](https://github.com/devqcf/usage-status/releases) tab.

### 2. Manual Build
If you prefer to build the app from source:

```bash
# Clone the repository
git clone https://github.com/devqcf/usage-status.git
cd usage-status

# Build the Release version
xcodebuild -project "Usage Status.xcodeproj" -scheme "Usage Status" -configuration Release build SYMROOT=build
```

The compiled application bundle will be generated under `build/Release/Usage Status.app`.

---

## 📂 Project Architecture

- **[Usage_StatusApp.swift](file:///Users/deargo/Projects/Usage%20Status/Usage%20Status/Usage_StatusApp.swift)**: Handles the `MenuBarExtra` lifecycle and dynamically renders the vector brand logos (Gemini Sparkle, Anthropic Hand, OpenAI Flower) and circular gauge icons using `ImageRenderer`.
- **[ContentView.swift](file:///Users/deargo/Projects/Usage%20Status/Usage%20Status/ContentView.swift)**: The main popover interface with clean usage meters, rollover intervals, and progress bars.
- **[UsageManager.swift](file:///Users/deargo/Projects/Usage%20Status/Usage%20Status/UsageManager.swift)**: Uses Grand Central Dispatch file system event streams to monitor changes to log files reactively.
