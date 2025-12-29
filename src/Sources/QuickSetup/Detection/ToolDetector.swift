import SwiftUI
import AppKit

// MARK: - Tool Detector

class ToolDetector: ObservableObject {
    static let shared = ToolDetector()

    @Published var tools: [DetectedTool] = []
    @Published var isScanning = false

    private let ellProxyPort = "8317"

    init() {
        scan()
    }

    func scan() {
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let detectedTools = [
                self.detectClaudeCLI(),
                self.detectVSCodeCline(),
                self.detectWindsurf(),
                self.detectZed(),
                self.detectDroidCLI(),
                self.detectOpencodeCLI(),
                self.detectTrae()
            ]

            DispatchQueue.main.async {
                self.tools = detectedTools
                self.isScanning = false
            }
        }
    }

    // MARK: - Claude CLI Detection

    private func detectClaudeCLI() -> DetectedTool {
        var tool = DetectedTool(
            id: "claude-cli",
            name: "Claude CLI",
            icon: "terminal",
            description: "Anthropic's Claude Code CLI",
            status: ToolStatus.notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Add to ~/.zshrc:
            export ANTHROPIC_BASE_URL="http://127.0.0.1:\(ellProxyPort)"
            export ANTHROPIC_API_KEY="dummy"
            """
        )

        let whichResult = runCommand("/usr/bin/which", arguments: ["claude"])
        if whichResult.isEmpty || whichResult.contains("not found") {
            return tool
        }

        tool.status = ToolStatus.installed
        tool.statusMessage = "Installed, not configured"

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let zshrcPath = "\(homeDir)/.zshrc"
        let bashrcPath = "\(homeDir)/.bashrc"

        if let zshrc = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
           zshrc.contains("ANTHROPIC_BASE_URL") && zshrc.contains("127.0.0.1:\(ellProxyPort)") {
            tool.status = ToolStatus.configured
            tool.statusMessage = "Configured in ~/.zshrc"
        } else if let bashrc = try? String(contentsOfFile: bashrcPath, encoding: .utf8),
                  bashrc.contains("ANTHROPIC_BASE_URL") && bashrc.contains("127.0.0.1:\(ellProxyPort)") {
            tool.status = ToolStatus.configured
            tool.statusMessage = "Configured in ~/.bashrc"
        }

        return tool
    }

    // MARK: - VS Code + Cline Detection

    private func detectVSCodeCline() -> DetectedTool {
        var tool = DetectedTool(
            id: "vscode-cline",
            name: "VS Code + Cline",
            icon: "chevron.left.forwardslash.chevron.right",
            description: "Cline AI extension for VS Code",
            status: ToolStatus.notInstalled,
            statusMessage: "VS Code not found",
            configInstructions: """
            In Cline settings:
            • API Provider: OpenAI Compatible
            • Base URL: http://127.0.0.1:\(ellProxyPort)/v1
            • API Key: dummy
            • Model: ellproxy-model
            """
        )

        let vscodeApps = [
            "/Applications/Visual Studio Code.app",
            "/Applications/VSCodium.app",
            "/Applications/Cursor.app"
        ]

        var vsCodeInstalled = false
        for app in vscodeApps {
            if FileManager.default.fileExists(atPath: app) {
                vsCodeInstalled = true
                break
            }
        }

        if !vsCodeInstalled {
            return tool
        }

        tool.status = ToolStatus.installed
        tool.statusMessage = "Cline extension status unknown"

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPaths = [
            "\(homeDir)/Library/Application Support/Code/User/settings.json",
            "\(homeDir)/Library/Application Support/VSCodium/User/settings.json"
        ]

        for settingsPath in settingsPaths {
            if let settings = try? String(contentsOfFile: settingsPath, encoding: .utf8) {
                if (settings.contains("cline") || settings.contains("claude-dev")) &&
                   settings.contains("127.0.0.1:\(ellProxyPort)") {
                    tool.status = ToolStatus.configured
                    tool.statusMessage = "Configured for EllProxy"
                    break
                } else if settings.contains("cline") || settings.contains("claude-dev") {
                    tool.statusMessage = "Cline installed, not configured for EllProxy"
                }
            }
        }

        return tool
    }

    // MARK: - Windsurf Detection

    private func detectWindsurf() -> DetectedTool {
        var tool = DetectedTool(
            id: "windsurf",
            name: "Windsurf",
            icon: "wind",
            description: "Codeium's AI editor",
            status: ToolStatus.notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Windsurf uses its own AI backend.
            Manual proxy configuration may be limited.
            """
        )

        if FileManager.default.fileExists(atPath: "/Applications/Windsurf.app") {
            tool.status = ToolStatus.installed
            tool.statusMessage = "Installed"
        }

        return tool
    }

    // MARK: - Zed Detection

    private func detectZed() -> DetectedTool {
        var tool = DetectedTool(
            id: "zed",
            name: "Zed",
            icon: "bolt",
            description: "High-performance code editor",
            status: ToolStatus.notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            In Zed settings.json, add:
            {
              "language_models": {
                "openai": {
                  "api_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                  "api_key": "dummy"
                }
              }
            }
            """
        )

        if FileManager.default.fileExists(atPath: "/Applications/Zed.app") {
            tool.status = ToolStatus.installed
            tool.statusMessage = "Installed"

            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let zedSettingsPath = "\(homeDir)/.config/zed/settings.json"

            if let settings = try? String(contentsOfFile: zedSettingsPath, encoding: .utf8) {
                if settings.contains("127.0.0.1:\(ellProxyPort)") {
                    tool.status = ToolStatus.configured
                    tool.statusMessage = "Configured for EllProxy"
                }
            }
        }

        return tool
    }
    
    // MARK: - Droid Factory CLI Detection
    
    private func detectDroidCLI() -> DetectedTool {
        var tool = DetectedTool(
            id: "droid-cli",
            name: "Droid Factory CLI",
            icon: "terminal.fill",
            description: "Factory AI's Droid CLI",
            status: ToolStatus.notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Add to ~/.factory/config.json custom_models array:
            {
              "custom_models": [
                {
                  "api_key": "dummy",
                  "base_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                  "model": "ellproxy-default",
                  "model_display_name": "EllProxy: Default Model",
                  "provider": "openai"
                },
                {
                  "api_key": "dummy",
                  "base_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                  "model": "ellproxy-thinking",
                  "model_display_name": "EllProxy: Thinking Model",
                  "provider": "openai"
                }
              ]
            }
            Then restart Droid CLI
            """
        )
        
        let whichResult = runCommand("/usr/bin/which", arguments: ["droid"])
        if whichResult.isEmpty || whichResult.contains("not found") {
            return tool
        }
        
        tool.status = ToolStatus.installed
        tool.statusMessage = "Installed, not configured"
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.factory/config.json"
        
        if let configData = FileManager.default.contents(atPath: configPath),
           let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let customModels = configJson["custom_models"] as? [[String: Any]],
           customModels.contains(where: { ($0["model"] as? String) == "ellproxy-default" }) ||
           customModels.contains(where: { ($0["model"] as? String) == "ellproxy-thinking" }) {
            tool.status = ToolStatus.configured
            tool.statusMessage = "Configured for EllProxy"
        }
        
        return tool
    }

    // MARK: - Opencode CLI Detection
    
    private func detectOpencodeCLI() -> DetectedTool {
        var tool = DetectedTool(
            id: "opencode-cli",
            name: "Opencode CLI",
            icon: "terminal.fill",
            description: "Opencode.ai CLI Assistant",
            status: ToolStatus.notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Add to ~/.opencode/opencode.json:
            {
              "$schema": "https://opencode.ai/config.json",
              "provider": {
                "ellproxy": {
                  "npm": "@ai-sdk/openai-compatible",
                  "name": "EllProxy (Dynamic)",
                  "options": {
                    "baseURL": "http://127.0.0.1:\(ellProxyPort)/v1"
                  },
                  "models": {
                    "auto": {
                      "name": "Auto (uses EllProxy default model)"
                    }
                  }
                }
              }
            }
            Then run: opencode auth login
            Select "Other" → Provider ID: ellproxy → API Key: dummy-key
            Select model: ellproxy/auto
            """
        )
        
        let whichResult = runCommand("/usr/bin/which", arguments: ["opencode"])
        var isInstalled = !whichResult.isEmpty && !whichResult.contains("not found")
        
        // Fallback: Check standard installation path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let standardPath = "\(homeDir)/.opencode/bin/opencode"
        if !isInstalled && FileManager.default.fileExists(atPath: standardPath) {
            isInstalled = true
        }
        
        if !isInstalled {
            return tool
        }
        
        tool.status = ToolStatus.installed
        tool.statusMessage = "Installed, not configured"
        
        // Define paths (OpenCode uses ~/.opencode not ~/.config/opencode)
        let configPath = "\(homeDir)/.opencode/opencode.json"
        
        // Check configuration (look for ellproxy provider)
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let provider = json["provider"] as? [String: Any],
           provider["ellproxy"] != nil {
            
            tool.status = ToolStatus.configured
            tool.statusMessage = "Configured for EllProxy"
        }
        
        return tool
    }
    
    // MARK: - Trae IDE Detection
    
    private func detectTrae() -> DetectedTool {
        let handler = TraeSetupHandler()
        return handler.detect()
    }

    // MARK: - Helper

    private func runCommand(_ command: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
