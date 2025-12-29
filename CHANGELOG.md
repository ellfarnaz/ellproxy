# Changelog

> [!NOTE]
> **This is a fork of [VibeProxy](https://github.com/automazeio/vibeproxy)**
> 
> EllProxy maintains the core functionality while adding custom features and improvements.
> Changes specific to EllProxy are documented below. For the original VibeProxy history, see the upstream repository.

All notable changes to EllProxy will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### 🚀 EllProxy Custom Features

This initial release focuses on project organization and release automation:

#### Added
- **Project Restructuring** - Organized codebase for better maintainability
  - Moved `Trae-Proxy` service to `services/trae-proxy/`
  - Consolidated all test and run scripts into `scripts/` directory
  - Isolated development tools to `scripts/dev-tools/` (git ignored)
  
- **Automated Binary Updates** - Created `scripts/update_binary.sh`
  - Automatically fetches latest CLIProxyAPIPlus binary from upstream
  - Integrated into release preparation workflow
  - Ensures builds always use the latest compatible version

- **Release Automation** - New `clean_and_prepare.sh` script
  - Automated cleanup of development artifacts
  - Security audit for sensitive keys in config files
  - Auto-update of CLIProxyAPIPlus binary before build
  - Fresh production build generation
  
- **CI/CD Pipeline** - GitHub Actions workflows for unsigned releases
  - Auto-detection of upstream CLIProxyAPIPlus updates
  - Automatic PR creation and merging for binary updates
  - Automated version tagging and CHANGELOG updates
  - Unsigned DMG and ZIP generation (no Apple Developer account required)
  
#### Changed
- **UI Terminology** - Rebranded "Testing" → "Sync" throughout the application
  - Updated all UI labels in `ModelSyncService.swift`
  - Modified macOS notification messages
  - Renamed `test_thinking_support1.sh` → `sync_thinking_support.sh`
  
- **Enhanced Notifications** - Provider names now included in sync notifications
  - Format: "Syncing [Provider]: [Model]"
  - Added `X-EllProxy-Provider` header to sync test requests
  - Improved user feedback during model synchronization

#### Fixed
- **Build System** - Updated all file paths for restructured project
  - `create-app-bundle.sh` now uses `services/trae-proxy/` path
  - `ModelSyncService.swift` references `scripts/sync_thinking_support.sh`
  - `.gitignore` excludes AI agent metadata folders

---

## [1.0.0-beta] - TBD

Initial beta release of **EllProxy**.

### Inherited from VibeProxy
- Native macOS menu bar application
- CLIProxyAPIPlus integration (v6.6.63-0)
- Multi-provider OAuth support (Claude, Codex, Gemini, Qwen, Antigravity, GitHub Copilot)
- Extended thinking support for Claude models
- Real-time model synchronization
- Multi-account management with auto-failover

### Requirements
- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)

---

## Future Releases

Planned features and improvements will be documented here.

---

[Unreleased]: https://github.com/ellfarnaz/ellproxy/compare/v1.0.0-beta...HEAD
[1.0.0-beta]: https://github.com/ellfarnaz/ellproxy/releases/tag/v1.0.0-beta
