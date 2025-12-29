# EllProxy

<p align="center">
  <img src="icon.png" width="128" height="128" alt="EllProxy Icon">
</p>

> [!NOTE]
> **Forked from [VibeProxy](https://github.com/automazeio/vibeproxy)**
> 
> This is a customized fork of the excellent VibeProxy project by [Automaze, Ltd.](https://automaze.io)
> 
> Original project: https://github.com/automazeio/vibeproxy

---

**Stop paying twice for AI.** EllProxy is a beautiful native macOS menu bar app that lets you use your existing Claude Code, ChatGPT, **Gemini**, **Qwen**, and **Antigravity** subscriptions with powerful AI coding tools like **[Factory Droids](https://app.factory.ai/r/FM8BJHFQ)** – no separate API keys required.

Built on [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus), it handles OAuth authentication, token management, and API routing automatically. One click to authenticate, zero friction to code.


<p align="center">
<br>
  <a href="https://www.loom.com/share/5cf54acfc55049afba725ab443dd3777"><img src="ellproxy-factory-video.webp" width="600" height="380" alt="EllProxy Screenshot" border="0"></a>
</p>

> [!TIP]
> 📣 **Latest models supported:**<br>Gemini 3 Pro Support (via Antigravity), GPT-5.1 / GPT-5.1 Codex, and Claude Sonnet 4.5 / Opus 4.5 with extended thinking, and GitHub Copilot! 🚀 
> 
> **Setup Guides:**
> - [Factory CLI Setup →](FACTORY_SETUP.md) - Use Factory Droids with your AI subscriptions
> - [Amp CLI Setup →](AMPCODE_SETUP.md) - Use Amp CLI with fallback to your subscriptions

---

## Features

- 🎯 **Native macOS Experience** - Clean, native SwiftUI interface that feels right at home on macOS
- 🚀 **One-Click Server Management** - Start/stop the proxy server from your menu bar
- 🔐 **OAuth Integration** - Authenticate with Codex, Claude Code, Gemini, Qwen, Antigravity, GitHub Copilot, iFlow, and Kiro directly from the app
- 👥 **Multi-Account Support** - Connect multiple accounts per provider with automatic round-robin distribution and failover when rate-limited
- 📊 **Real-Time Status** - Live connection status and automatic credential detection
- 🔄 **Automatic App Updates** - EllProxy can check for updates and install them seamlessly via Sparkle
- 🎨 **Beautiful Icons** - Custom icons with dark mode support
- 💾 **Self-Contained** - Everything bundled inside the .app (server binary, config, static files)


## Installation

**⚠️ Requirements:** macOS running on **Apple Silicon only** (M1/M2/M3/M4 Macs). Intel Macs are not supported.

### Download Pre-built Release (Recommended)

*Note: Pre-built releases for EllProxy are not available. Please build from source.*

### Build from Source

See [**INSTALLATION.md**](INSTALLATION.md) for detailed build instructions.

## Usage

### First Launch

1. Launch EllProxy - you'll see a menu bar icon
2. Click the icon and select "Open Settings"
3. The server will start automatically
4. Click "Connect" for Claude Code, Codex, Gemini, Qwen, or Antigravity to authenticate

### Authentication

When you click "Connect":
1. Your browser opens with the OAuth page
2. Complete the authentication in the browser
3. EllProxy automatically detects your credentials
4. Status updates to show you're connected

### Server Management

- **Toggle Server**: Click the status (Running/Stopped) to start/stop
- **Menu Bar Icon**: Shows active/inactive state
- **Launch at Login**: Toggle to start EllProxy automatically

## Requirements

- macOS 13.0 (Ventura) or later

## Development

### Project Structure

```
EllProxy/
├── Sources/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar & window management
│   ├── ServerManager.swift     # Server process control & auth
│   ├── SettingsView.swift      # Main UI
│   ├── AuthStatus.swift        # Auth file monitoring
│   └── Resources/
│       ├── AppIcon.iconset     # App icon
│       ├── AppIcon.icns        # App icon
│       ├── cli-proxy-api-plus  # CLIProxyAPIPlus binary
│       ├── config.yaml         # CLIProxyAPIPlus config
│       ├── icon-active.png     # Menu bar icon (active)
│       ├── icon-inactive.png   # Menu bar icon (inactive)
│       ├── icon-claude.png     # Claude Code service icon
│       ├── icon-codex.png      # Codex service icon
│       ├── icon-gemini.png     # Gemini service icon
│       └── icon-qwen.png       # Qwen service icon
├── Package.swift               # Swift Package Manager config
├── Info.plist                  # macOS app metadata
├── build.sh                    # Resource bundling script
├── create-app-bundle.sh        # App bundle creation script
└── Makefile                    # Build automation
```

### Key Components

- **AppDelegate**: Manages the menu bar item and settings window lifecycle
- **ServerManager**: Controls the cli-proxy-api server process and OAuth authentication
- **SettingsView**: SwiftUI interface with native macOS design
- **AuthStatus**: Monitors `~/.cli-proxy-api/` for authentication files
- **File Monitoring**: Real-time updates when auth files are added/removed

## Credits

EllProxy is a fork of [VibeProxy](https://github.com/automazeio/vibeproxy) by [Automaze, Ltd.](https://automaze.io)

Both EllProxy and VibeProxy are built on top of [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus), an excellent unified proxy server for AI services with support for third-party providers.

Special thanks to:
- The **VibeProxy** team at Automaze for creating the original macOS wrapper
- The **CLIProxyAPIPlus** project for providing the core proxy functionality

## License

MIT License - see LICENSE file for details

Original VibeProxy: © 2025 [Automaze, Ltd.](https://automaze.io)

---

*Based on VibeProxy - https://github.com/automazeio/vibeproxy*
