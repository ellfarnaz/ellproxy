# VibeProxy - Copilot Instructions

## Project Overview

VibeProxy is a native macOS menu bar app (SwiftUI) that proxies AI API requests through existing subscriptions (Claude Code, Codex, Gemini, Qwen, Antigravity, GitHub Copilot). It wraps CLIProxyAPIPlus binary and adds extended thinking support for Claude models.

**Apple Silicon only** • Swift 5.9+ • macOS 14+

## Architecture

```
┌──────────────────┐     ┌───────────────────┐     ┌────────────────────┐
│  AI Client       │────▶│  ThinkingProxy    │────▶│  CLIProxyAPIPlus   │────▶ AI Provider APIs
│  (Port 8317)     │     │  (Port 8317→8318) │     │  (Port 8318)       │
└──────────────────┘     └───────────────────┘     └────────────────────┘
```

### Key Components

| File | Purpose |
|------|---------|
| [AppDelegate.swift](src/Sources/AppDelegate.swift) | Menu bar management, window lifecycle, Sparkle updates, coordinates ServerManager + ThinkingProxy startup |
| [ServerManager.swift](src/Sources/ServerManager.swift) | Manages CLIProxyAPIPlus process, handles OAuth auth commands, graceful termination |
| [ThinkingProxy.swift](src/Sources/ThinkingProxy.swift) | HTTP proxy using NWListener that intercepts requests to add `thinking` parameters for Claude models via `-thinking-NUMBER` suffix |
| [AuthStatus.swift](src/Sources/AuthStatus.swift) | Monitors `~/.cli-proxy-api/` for OAuth token files, parses account info |
| [SettingsView.swift](src/Sources/SettingsView.swift) | Main SwiftUI interface with ServiceRow components for multi-account management |
| [IconCatalog.swift](src/Sources/IconCatalog.swift) | Thread-safe singleton for icon caching with template mode support |

### Critical Patterns

**Dual-port architecture**: ThinkingProxy (8317) → CLIProxyAPIPlus (8318). Users connect to 8317; the proxy intercepts and modifies requests before forwarding.

**Extended thinking**: Model name suffix `-thinking-NUMBER` triggers budget injection (e.g., `claude-sonnet-4-5-20250929-thinking-5000` → 5000 token budget). See `ThinkingProxy.parseThinkingSuffix()`.

**Multi-account OAuth**: ServiceType enum defines providers; AuthManager scans `~/.cli-proxy-api/` for JSON credential files. Round-robin with auto-failover on rate limits.

## Build & Development

```bash
make app        # Build release .app bundle (runs create-app-bundle.sh)
make run        # Build and launch
make install    # Install to /Applications
make clean      # Remove build artifacts
```

**Direct Swift build**: `cd src && swift build -c release`

**App bundle structure**: `create-app-bundle.sh` copies binary, resources, and Sparkle.framework to `VibeProxy.app/Contents/`

## Testing & Debugging

- No test suite exists currently
- Debug via Xcode console or NSLog statements (search for `NSLog`)
- Auth debugging: Check `~/.cli-proxy-api/` for credential JSON files
- Server logs: View in Settings window log panel

## Code Conventions

- **Process management**: Use graceful SIGTERM → SIGKILL pattern (see `ServerManager.stop()`)
- **Thread safety**: Use dispatch queues and locks (see `stateQueue` in ThinkingProxy, `cacheLock` in IconCatalog)
- **Notifications**: Use `NotificationCenter` with custom names from [NotificationNames.swift](src/Sources/NotificationNames.swift)
- **Icons**: Always use `IconCatalog.shared.image(named:resizedTo:template:)` for consistent caching

## Common Tasks

**Adding a new service provider**:
1. Add case to `ServiceType` enum in [AuthStatus.swift](src/Sources/AuthStatus.swift)
2. Add `AuthCommand` case in [ServerManager.swift](src/Sources/ServerManager.swift#L200)
3. Add ServiceRow in [SettingsView.swift](src/Sources/SettingsView.swift)
4. Add icon to `src/Sources/Resources/`

**Modifying thinking proxy behavior**: Edit `transformRequest()` and `parseThinkingSuffix()` in ThinkingProxy.swift

## External Dependencies

- **Sparkle** (v2.5+): Auto-updates via `appcast.xml`
- **CLIProxyAPIPlus**: Bundled Go binary at `src/Sources/Resources/cli-proxy-api-plus`
- **Cloudflared**: Optional, for tunnel functionality (TunnelManager.swift)
