# EllProxy

<p align="center">
  <img src="icon.png" width="128" height="128" alt="EllProxy Icon">
</p>

> [!NOTE]
> **Forked from [VibeProxy](https://github.com/automazeio/vibeproxy) v1.8.23**
> 
> EllProxy is an enhanced fork with modular architecture, advanced model management, and automated release workflows.
> 
> Original project: https://github.com/automazeio/vibeproxy

---

**Stop paying twice for AI.** EllProxy is a next-generation native macOS menu bar app that lets you use your existing Claude Code, ChatGPT, **Gemini**, **Qwen**, and **Antigravity** subscriptions with powerful AI coding tools like **[Factory Droids](https://app.factory.ai/r/FM8BJHFQ)** – no separate API keys required.

Built on [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus), it handles OAuth authentication, token management, and API routing automatically. One click to authenticate, zero friction to code.

<p align="center">
<br>
  <a href="https://www.loom.com/share/5cf54acfc55049afba725ab443dd3777"><img src="ellproxy-factory-video.webp" width="600" height="380" alt="EllProxy Demo" border="0"></a>
</p>

> [!TIP]
> 📣 **Latest models supported:**<br>Gemini 3 Pro Support (via Antigravity), GPT-5.1 / GPT-5.1 Codex, Claude Sonnet 4.5 / Opus 4.5 with extended thinking, and GitHub Copilot! 🚀 
> 
> **Setup Guides:**
> - [Factory CLI Setup →](FACTORY_SETUP.md) - Use Factory Droids with your AI subscriptions
> - [Amp CLI Setup →](AMPCODE_SETUP.md) - Use Amp CLI with fallback to your subscriptions

---

## 🚀 What Can You Do with EllProxy?

EllProxy acts as a universal bridge between your AI accounts and your favorite coding tools.

### 1. **Unlock Premium AI Without Extra Subs**
Stop paying $20/mo for ChatGPT Plus, $20/mo for Claude Pro, and $20/mo for GitHub Copilot.
*   **Bring Your Own Accounts:** Login once with your existing Google (Gemini), Anthropic, or OpenAI accounts.
*   **Unlimited Access:** Use the same powerful models (Claude 3.5 Sonnet, GPT-4o, Gemini 1.5 Pro) directly in your editor.

### 2. **One-Click Tool Setup**
 forget about messing with `.env` files or API keys. EllProxy automatically detects and configures your favorite tools:
*   **Editors:** Cursor, VS Code (Cline, Roo, Envoid), Zed, Trae, Windsurf.
*   **CLIs:** Claude Code, AmpCode, Dictionary.
*   **Agents:** Factory Droids.
*(Just click "Setup" in the app, and we inject the correct proxy URL for you!)*

### 3. **Never Downtime with "Smart Failover"**
Is Claude API acting up? EllProxy has your back.
*   **Auto-Fallback:** Set Gemini or GPT-4o as your backup. If your main model fails, EllProxy instantly switches to the backup so your coding flow never breaks.
*   **Panic Mode:** Flip "Routing" to OFF to force *all* requests to your cheap/fast default model immediately.

### 4. **Supercharge Your "Reasoning" Models**
Get the most out of "Thinking" models like Gemini 2.0 Flash Thinking or Claude 3.7 Sonnet.
*   **Reasoning Slider:** Choose between **Low** (Fast), **Medium**, or **High** (Deep Thought) effort.
*   **Cache:** We cache reasoning tokens to speed up repeated queries and save you money/quota.

### 5. **Manage Models Like a Pro**
*   **Auto-Sync:** New model released today? Click "Sync" and it appears in your list instantly.
*   **Custom Models:** Have a fine-tuned model ID? Add it manually.
*   **Visual Organization:** See models grouped by provider with live status indicators.

---

## Installation

**⚠️ Requirements:** macOS 14.0+ on **Apple Silicon only** (M1/M2/M3/M4). Intel Macs are not supported.

### Download Pre-built Release

1. Visit [Releases](https://github.com/ellfarnaz/ellproxy/releases)
2. Download `EllProxy.zip` or `EllProxy.dmg`
3. Extract/mount and drag to `/Applications`
4. **First launch:** Right-click EllProxy.app → Open (bypass Gatekeeper for unsigned apps)

> [!WARNING]
> EllProxy releases are **unsigned** (no Apple Developer account). macOS will show a security warning on first launch.
> 
> **To open:** Right-click → Open → Click "Open" in the dialog. Only needed once.

### Build from Source

See [**INSTALLATION.md**](INSTALLATION.md) for detailed build instructions.

---

## Usage

### First Launch

1. Launch EllProxy - menu bar icon appears
2. Click icon → "Open Settings"
3. Server starts automatically
4. Click "Connect" for your providers to authenticate

### Model Management

1. Click "Models" tab in Settings
2. Click "Sync Models" to discover available models
3. Set default and fallback models per provider
4. Search models with the search button

### Authentication

When you click "Connect":
1. Browser opens with OAuth page
2. Complete authentication
3. EllProxy auto-detects credentials
4. Status updates to "Connected"

---

## Development

### Project Structure (EllProxy)

```
EllProxy/
├── src/Sources/
│   ├── App/                    # Application entry and delegates
│   │   ├── AppDelegate.swift   # Menu bar & window lifecycle
│   │   ├── main.swift          # Entry point
│   │   └── Config/             # App configuration
│   ├── Services/               # Core business logic
│   │   ├── ModelRouter.swift   # Model routing logic
│   │   ├── ModelSyncService.swift  # Model discovery & sync
│   │   ├── KeychainManager.swift   # Secure credential storage
│   │   ├── ServerManager.swift     # Server process control
│   │   ├── TunnelManager.swift     # Tunnel management
│   │   └── DiscoveredModelsStore.swift  # Model persistence
│   ├── Views/                  # SwiftUI interface components
│   │   ├── ModelsView.swift    # Model management UI
│   │   ├── SettingsView.swift  # Main settings interface
│   │   ├── AddModelView.swift  # Manual model addition
│   │   └── FallbackModelPickerPopover.swift  # Fallback selection
│   ├── ThinkingProxy/          # Extended thinking support
│   │   ├── Core/               # Protocols and configuration
│   │   ├── Processing/         # Thinking parameter processing
│   │   ├── ThinkingProxy.swift # Main proxy implementation
│   │   └── [Feature modules]   # Anthropic, DeepSeek, etc.
│   ├── QuickSetup/             # Tool auto-setup system
│   │   ├── Core/               # Setup managers
│   │   ├── Detection/          # Tool detection
│   │   └── Handlers/           # Per-tool setup handlers
│   ├── Models/                 # Data models
│   │   └── AuthStatus.swift    # Authentication state
│   ├── Config/                 # Configuration management
│   │   └── AppConfig.swift     # App configuration
│   ├── ServerManagement/       # Server control
│   │   ├── AuthCommand.swift   # Auth commands
│   │   └── RingBuffer.swift    # Log buffering
│   └── Resources/              # Assets and data
│       ├── models/             # Provider model definitions
│       │   ├── claude.json     # Claude models
│       │   ├── google.json     # Gemini models
│       │   └── [others]        # Per-provider model data
│       ├── cli-proxy-api-plus  # Proxy binary
│       └── [icons & assets]    # Visual resources
├── services/
│   └── trae-proxy/             # SSL certificate proxy
├── scripts/
│   ├── sync_thinking_support.sh   # Model sync script
│   ├── update_binary.sh           # Binary auto-update
│   └── dev-tools/                 # Development scripts (git ignored)
├── clean_and_prepare.sh        # Release preparation
└── create-app-bundle.sh        # Bundle creation
```

### Architecture Comparison

| Component | VibeProxy v1.8.23 | EllProxy |
|-----------|-------------------|----------|
| **Files** | 10 Swift files (flat) | 50+ Swift files (modular) |
| **Structure** | Single directory | 12 specialized modules |
| **Model Management** | Hardcoded | Dynamic discovery & sync |
| **ThinkingProxy** | Monolithic (33KB) | Modular (8 files) |
| **Setup System** | Manual | QuickSetup module (7 handlers) |
| **Services** | None | `services/trae-proxy/` |
| **Automation** | None | CI/CD + auto-update |

---

## Credits

EllProxy is an enhanced fork of [VibeProxy v1.8.23](https://github.com/automazeio/vibeproxy) by [Automaze, Ltd.](https://automaze.io)

Both EllProxy and VibeProxy are built on top of [CLIProxyAPIPlus](https://github.com/router-for-me/CLIProxyAPIPlus).

Special thanks to:
- The **VibeProxy** team at Automaze for creating the excellent foundation
- The **CLIProxyAPIPlus** project for the core proxy functionality
- The open-source community for continuous improvements

---

## License

MIT License - see LICENSE file for details

Original VibeProxy: © 2025 [Automaze, Ltd.](https://automaze.io)

---

*Enhanced fork of VibeProxy - https://github.com/automazeio/vibeproxy*
