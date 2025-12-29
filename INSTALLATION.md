# Installing EllProxy

<div align="center">
  <img src="header.png" width="100%" alt="EllProxy Header" style="border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1);">
</div>

**⚠️ Requirements:** macOS running on **Apple Silicon only** (M1/M2/M3/M4 Macs). Intel Macs are not supported.

> [!NOTE]
> This is a fork of [VibeProxy](https://github.com/automazeio/vibeproxy). Pre-built releases are not available. Please build from source.

## Build from Source

---

### Prerequisites

- macOS 13.0 (Ventura) or later
- Swift 5.9+
- Xcode Command Line Tools
- Git

### Build Instructions

1. **Clone or download this repository**
   ```bash
   cd ellproxy
   ```

2. **Build the app**
   ```bash
   ./create-app-bundle.sh
   ```

   This will:
   - Build the Swift executable in release mode
   - Bundle CLIProxyAPIPlus
   - Create `EllProxy.app`
   - Sign it with your Developer ID (if available)

3. **Install**
   ```bash
   # Move to Applications folder
   mv EllProxy.app /Applications/

   # Or run directly
   open EllProxy.app
   ```

### Build Commands

```bash
# Quick build and run
make run

# Build .app bundle
make app

# Install to /Applications
make install

# Clean build artifacts
make clean
```

### Code Signing (Optional)

If you have an Apple Developer account, the build script will automatically detect and use your Developer ID certificate for signing.

To manually specify a certificate:
```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./create-app-bundle.sh
```

---

## Verifying Downloads

Before installing any downloaded app, verify its authenticity:

### 1. Inspect the Code

All source code is available in this repository - feel free to review before building.

---

## Troubleshooting

### "App is damaged and can't be opened"

This can happen if download quarantine attributes cause issues:

```bash
xattr -cr /Applications/EllProxy.app
```

Then try opening again.

### Build Fails

**Error: Swift not found**
```bash
# Install Xcode Command Line Tools
xcode-select --install
```

**Error: Permission denied**
```bash
# Make scripts executable
chmod +x build.sh create-app-bundle.sh
```

### Still Having Issues?

- **Check System Requirements**: macOS 13.0 (Ventura) or later
- **Check Logs**: Look for errors in Console.app (search for "EllProxy")
- Check the [README](README.md) for more information
