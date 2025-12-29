import SwiftUI
import AppKit

// MARK: - Setup Manager

class SetupManager {
    static let shared = SetupManager()

    // All tools use AppConfig.ellProxyPort (ThinkingProxy - Anthropic/OpenAI compatible)
    private var ellProxyPort: String { String(AppConfig.ellProxyPort) }

    enum SetupResult {
        case success(String)
        case failure(String)
        case alreadyConfigured
    }

    // MARK: - Claude CLI Setup

    func setupClaudeCLI(shell: String = "zsh") -> SetupResult {
        let homeDir = AppConfig.Paths.homeDir
        let rcFile = shell == "zsh" ? "\(homeDir)/.zshrc" : "\(homeDir)/.bashrc"

        // Check if already configured
        if let content = try? String(contentsOfFile: rcFile, encoding: .utf8),
           content.contains("ANTHROPIC_BASE_URL") && content.contains("127.0.0.1:\(ellProxyPort)") {
            return .alreadyConfigured
        }

        let config = """

        # EllProxy - Claude CLI
        export ANTHROPIC_BASE_URL="http://127.0.0.1:\(ellProxyPort)"
        export ANTHROPIC_API_KEY="dummy"
        """

        do {
            let existingContent = (try? String(contentsOfFile: rcFile, encoding: .utf8)) ?? ""
            try (existingContent + config).write(toFile: rcFile, atomically: true, encoding: .utf8)
            return .success("Added to ~/.\(shell)rc. Restart terminal to apply.")
        } catch {
            return .failure("Failed to write to ~/.\(shell)rc: \(error.localizedDescription)")
        }
    }

    // MARK: - VS Code / Cline Setup

    func setupCline() -> SetupResult {
        let homeDir = AppConfig.Paths.homeDir
        let settingsPath = AppConfig.Paths.vscodeSettings

        // Ensure directory exists
        let settingsDir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]

        // Read existing settings
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Check if already configured
        if let baseUrl = settings["cline.openaiBaseUrl"] as? String,
           baseUrl.contains("127.0.0.1:\(ellProxyPort)") {
            return .alreadyConfigured
        }

        // Add Cline settings
        settings["cline.apiProvider"] = "openai"
        settings["cline.openaiBaseUrl"] = "http://127.0.0.1:\(ellProxyPort)/v1"
        settings["cline.openaiApiKey"] = "dummy"
        settings["cline.openaiModelId"] = "ellproxy-model"

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: settingsPath))
            
            // BONUS: Automatically switch Cline's provider selection AND API config in VS Code state
            // This modifies the internal state database so user doesn't need ANY manual configuration
            let stateDbPath = "\(homeDir)/Library/Application Support/Code/User/globalStorage/state.vscdb"
            let switchProviderScript = """
            sqlite3 '\(stateDbPath)' "UPDATE ItemTable SET value = json_set(json_set(json_set(json_set(json_set(value, '$.planModeApiProvider', 'openai'), '$.actModeApiProvider', 'openai'), '$.openAiApiKey', 'dummy'), '$.openAiBaseUrl', 'http://127.0.0.1:\(ellProxyPort)/v1'), '$.openAiModelId', 'ellproxy-model') WHERE key = 'saoudrizwan.claude-dev';" 2>/dev/null || true
            """
            
            // Run the SQL update using Process and WAIT for completion
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", switchProviderScript]
            try? process.run()
            process.waitUntilExit() // CRITICAL: Wait for SQL to complete before returning
            
            return .success("""
            Cline configured! Provider & settings auto-set.
            
            Final step (one-time only):
            1. Reload VS Code window (Cmd+R)
            2. Open Cline sidebar
            3. Click "Configure in settings" (blue link)
            4. Enter API Key: dummy
            5. Save → Done! Cline will use EllProxy
            """)
        } catch {
            return .failure("Failed to update VS Code settings: \(error.localizedDescription)")
        }
    }


    // MARK: - Zed Setup

    func setupZed() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(homeDir)/.config/zed/settings.json"

        // Ensure directory exists
        let settingsDir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]

        // Read existing settings
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Check if already configured
        if let languageModels = settings["language_models"] as? [String: Any],
           let openai = languageModels["openai"] as? [String: Any],
           let apiUrl = openai["api_url"] as? String,
           apiUrl.contains("127.0.0.1") {
            return .alreadyConfigured
        }

        // Add language models config
        var languageModels = settings["language_models"] as? [String: Any] ?? [:]
        languageModels["openai"] = [
            "api_url": "http://127.0.0.1:\(ellProxyPort)/v1",
            "api_key": "dummy"
        ]
        settings["language_models"] = languageModels

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: settingsPath))
            return .success("Zed configured. Restart Zed to apply.")
        } catch {
            return .failure("Failed to update Zed settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Copy to Clipboard

    func copyConfig(for toolId: String) {
        let config: String

        switch toolId {
        case "claude-cli":
            config = """
            # Add to ~/.zshrc or ~/.bashrc
            export ANTHROPIC_BASE_URL="http://127.0.0.1:\(ellProxyPort)"
            export ANTHROPIC_API_KEY="dummy"
            """
        case "vscode-cline":
            config = """
            Cline Settings:
            • API Provider: OpenAI Compatible
            • Base URL: http://127.0.0.1:\(ellProxyPort)/v1
            • API Key: dummy
            • Model: ellproxy-model
            """

        case "zed":
            config = """
            Add to ~/.config/zed/settings.json:
            {
              "language_models": {
                "openai": {
                  "api_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                  "api_key": "dummy"
                }
              }
            }
            """
        case "droid-cli":
            config = """
            Add to ~/.factory/config.json custom_models array:
            {
              "custom_models": [
                {
                  "api_key": "dummy",
                  "base_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                  "model": "ellproxy-model",
                  "model_display_name": "EllProxy: Dynamic Model",
                  "provider": "openai"
                }
              ]
            }
            """
        case "opencode-cli":
            config = """
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
            """
        case "trae-ide":
            let handler = TraeSetupHandler()
            config = handler.copyConfig()
        default:
            config = "No configuration available"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
    
    // MARK: - Clear Configurations
    
    func clearClaudeCLI(shell: String = "zsh") -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let rcFile = shell == "zsh" ? "\(homeDir)/.zshrc" : "\(homeDir)/.bashrc"
        
        guard let content = try? String(contentsOfFile: rcFile, encoding: .utf8) else {
            return .failure("Could not read ~/.\(shell)rc")
        }
        
        // Check if configured
        if !content.contains("ANTHROPIC_BASE_URL") || !content.contains("127.0.0.1:\(ellProxyPort)") {
            return .alreadyConfigured // Not configured, nothing to clear
        }
        
        // Remove EllProxy section
        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var skipUntilBlank = false
        
        for line in lines {
            if line.contains("# EllProxy - Claude CLI") {
                skipUntilBlank = true
                continue
            }
            if skipUntilBlank {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    skipUntilBlank = false
                }
                continue
            }
            if !line.contains("ANTHROPIC_BASE_URL") && !line.contains("ANTHROPIC_API_KEY=\"dummy\"") {
                newLines.append(line)
            }
        }
        
        do {
            try newLines.joined(separator: "\n").write(toFile: rcFile, atomically: true, encoding: .utf8)
            return .success("Removed from ~/.\(shell)rc. Restart terminal to apply.")
        } catch {
            return .failure("Failed to write to ~/.\(shell)rc: \(error.localizedDescription)")
        }
    }
    
    func clearCline() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(homeDir)/Library/Application Support/Code/User/settings.json"
        
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Could not read VS Code settings")
        }
        
        // Check if configured
        if let baseUrl = settings["cline.openaiBaseUrl"] as? String,
           !baseUrl.contains("127.0.0.1:\(ellProxyPort)") {
            return .alreadyConfigured // Not configured for EllProxy
        }
        
        // Remove Cline EllProxy settings from settings.json
        settings.removeValue(forKey: "cline.apiProvider")
        settings.removeValue(forKey: "cline.openaiBaseUrl")
        settings.removeValue(forKey: "cline.openaiApiKey")
        settings.removeValue(forKey: "cline.openaiModelId")
        
        do {
            let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: URL(fileURLWithPath: settingsPath))
            
            // ALSO clear from VS Code state database
            let stateDbPath = "\(homeDir)/Library/Application Support/Code/User/globalStorage/state.vscdb"
            let clearStateScript = """
            sqlite3 '\(stateDbPath)' "UPDATE ItemTable SET value = json_remove(json_remove(json_remove(json_remove(json_remove(value, '$.planModeApiProvider'), '$.actModeApiProvider'), '$.openAiApiKey'), '$.openAiBaseUrl'), '$.openAiModelId') WHERE key = 'saoudrizwan.claude-dev';" 2>/dev/null || true
            """
            
            let clearProcess = Process()
            clearProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            clearProcess.arguments = ["-c", clearStateScript]
            try? clearProcess.run()
            clearProcess.waitUntilExit()
            
            return .success("Cline configuration removed from settings & state. Reload VS Code window to apply.")
        } catch {
            return .failure("Failed to update VS Code settings: \(error.localizedDescription)")
        }
    }
    
    func clearZed() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(homeDir)/.config/zed/settings.json"
        
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Could not read Zed settings")
        }
        
        // Check if configured
        guard var languageModels = settings["language_models"] as? [String: Any],
              let openai = languageModels["openai"] as? [String: Any],
              let apiUrl = openai["api_url"] as? String,
              apiUrl.contains("127.0.0.1") else {
            return .alreadyConfigured // Not configured for EllProxy
        }
        
        // Remove OpenAI config
        languageModels.removeValue(forKey: "openai")
        
        if languageModels.isEmpty {
            settings.removeValue(forKey: "language_models")
        } else {
            settings["language_models"] = languageModels
        }
        
        do {
            let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: URL(fileURLWithPath: settingsPath))
            return .success("Zed configuration removed. Restart Zed to apply.")
        } catch {
            return .failure("Failed to update Zed settings: \(error.localizedDescription)")
        }
    }
    

    
    // MARK: - Droid Factory CLI Setup
    
    func setupDroid() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let factoryDir = "\(homeDir)/.factory"
        let configPath = "\(factoryDir)/config.json"
        
        // Ensure .factory directory exists
        try? FileManager.default.createDirectory(atPath: factoryDir, withIntermediateDirectories: true)
        
        var config: [String: Any] = [:]
        
        // Read existing config
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }
        
        var customModels = config["custom_models"] as? [[String: Any]] ?? []
        
        // Check if already configured
        let hasDefault = customModels.contains(where: { ($0["model"] as? String) == "ellproxy-default" })
        let hasThinking = customModels.contains(where: { ($0["model"] as? String) == "ellproxy-thinking" })
        
        if hasDefault && hasThinking {
            return .alreadyConfigured
        }
        
        // Add EllProxy Default model if not exists
        if !hasDefault {
            customModels.append([
                "api_key": "dummy",
                "base_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                "model": "ellproxy-default",
                "model_display_name": "EllProxy: Default Model",
                "provider": "openai"
            ])
        }
        
        // Add EllProxy Thinking model if not exists
        if !hasThinking {
            customModels.append([
                "api_key": "dummy",
                "base_url": "http://127.0.0.1:\(ellProxyPort)/v1",
                "model": "ellproxy-thinking",
                "model_display_name": "EllProxy: Thinking Model",
                "provider": "openai"
            ])
        }
        
        config["custom_models"] = customModels
        
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath))
            return .success("Droid configured with Default and Thinking models. Restart Droid CLI.")
        } catch {
            return .failure("Failed to update Droid config: \(error.localizedDescription)")
        }
    }
    
    func clearDroid() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.factory/config.json"
        let settingsPath = "\(homeDir)/.factory/settings.json"
        
        guard let data = FileManager.default.contents(atPath: configPath),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Could not read Droid config")
        }
        
        // Check if configured and remove from custom_models array
        guard var customModels = config["custom_models"] as? [[String: Any]] else {
            return .alreadyConfigured // Not configured for EllProxy
        }
        
        let originalCount = customModels.count
        customModels.removeAll { 
            let modelId = $0["model"] as? String
            return modelId == "ellproxy-default" || modelId == "ellproxy-thinking" || modelId == "ellproxy-model"
        }
        
        if customModels.count == originalCount {
            return .alreadyConfigured // Models not found
        }
        
        config["custom_models"] = customModels
        
        // Save updated config.json
        do {
            let newData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: URL(fileURLWithPath: configPath))
        } catch {
            return .failure("Failed to update Droid config: \(error.localizedDescription)")
        }
        
        // Also clean settings.json to remove cached model references
        if let settingsData = FileManager.default.contents(atPath: settingsPath),
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
            
            // Recursively clean ellproxy references from settings
            func cleanEllProxyRefs(_ obj: inout Any) {
                if var dict = obj as? [String: Any] {
                    for (key, value) in dict {
                        if let stringValue = value as? String, stringValue.lowercased().contains("ellproxy") {
                            dict[key] = NSNull()
                        } else {
                            var nestedValue = value
                            cleanEllProxyRefs(&nestedValue)
                            dict[key] = nestedValue
                        }
                    }
                    obj = dict
                } else if var array = obj as? [Any] {
                    for i in 0..<array.count {
                        cleanEllProxyRefs(&array[i])
                    }
                    obj = array
                }
            }
            
            var settingsAny: Any = settings
            cleanEllProxyRefs(&settingsAny)
            
            if let cleanedSettings = settingsAny as? [String: Any],
               let cleanedData = try? JSONSerialization.data(withJSONObject: cleanedSettings, options: [.prettyPrinted, .sortedKeys]) {
                try? cleanedData.write(to: URL(fileURLWithPath: settingsPath))
            }
        }
        
        return .success("Droid configuration removed. Restart Droid CLI to apply.")
    }
    
    // MARK: - Opencode CLI Setup
    
    func setupOpencodeCLI() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(homeDir)/.opencode"
        let configPath = "\(configDir)/opencode.json"
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        
        var config: [String: Any] = [:]
        
        // Read existing config
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }
        
        // Check if already configured (look for ellproxy provider)
        if let providers = config["provider"] as? [String: Any],
           providers["ellproxy"] != nil {
            return .alreadyConfigured
        }
        
        // Configure custom provider with EllProxy models
        var provider = config["provider"] as? [String: Any] ?? [:]
        provider["ellproxy"] = [
            "npm": "@ai-sdk/openai-compatible",
            "name": "EllProxy",
            "options": [
                "baseURL": "http://127.0.0.1:\(ellProxyPort)/v1"
            ],
            "models": [
                // === AUTO / DYNAMIC MODELS ===
                "auto": [
                    "name": "🎯 Auto (EllProxy Default)",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "auto-thinking": [
                    "name": "🧠 Auto Thinking",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ],
                    "options": [
                        "thinking": [
                            "type": "enabled",
                            "budgetTokens": 16000
                        ]
                    ]
                ],
                
                // === THINKING MODELS ===
                "claude-sonnet-4-5-thinking": [
                    "name": "Claude Sonnet 4.5 (Thinking)",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "claude-opus-4-5-thinking": [
                    "name": "Claude Opus 4.5 (Thinking)",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "qwen3-235b-thinking": [
                    "name": "Qwen3 235B (Thinking)",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "kimi-k2-thinking": [
                    "name": "Kimi K2 (Thinking)",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                
                // === CODING MODELS ===
                "qwen3-coder-plus": [
                    "name": "Qwen3 Coder Plus (480B)",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "qwen3-coder-flash": [
                    "name": "Qwen3 Coder Flash",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                
                // === CLAUDE MODELS ===
                "claude-sonnet-4-5": [
                    "name": "Claude Sonnet 4.5",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "claude-opus-4-5": [
                    "name": "Claude Opus 4.5",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                
                // === GEMINI MODELS ===
                "gemini-2.5-pro": [
                    "name": "Gemini 2.5 Pro",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "gemini-2.5-flash": [
                    "name": "Gemini 2.5 Flash",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "gemini-3-pro-preview": [
                    "name": "Gemini 3 Pro Preview",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                
                // === KIMI MODELS ===
                "kimi-k2": [
                    "name": "Kimi K2",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ],
                "kimi-k1.5": [
                    "name": "Kimi K1.5",
                    "attachment": true,
                    "modalities": [
                        "input": ["text", "image"],
                        "output": ["text"]
                    ]
                ]
            ]

        ]
        config["provider"] = provider
        
        // Add schema
        config["$schema"] = "https://opencode.ai/config.json"
        
        // Write config file
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath))
        } catch {
            return .failure("Failed to update Opencode config: \(error.localizedDescription)")
        }
        
        // BONUS: Auto-create auth file for true one-click setup
        let authDir = "\(homeDir)/.local/share/opencode"
        let authPath = "\(authDir)/auth.json"
        
        // Ensure auth directory exists
        try? FileManager.default.createDirectory(atPath: authDir, withIntermediateDirectories: true)
        
        var authData: [String: Any] = [:]
        
        // Read existing auth
        if let existingData = FileManager.default.contents(atPath: authPath),
           let existingAuth = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            authData = existingAuth
        }
        
        // Add ellproxy auth entry
        authData["ellproxy"] = [
            "type": "api",
            "key": "dummy-key"
        ]
        
        // Write auth file
        do {
            let authJsonData = try JSONSerialization.data(withJSONObject: authData, options: [.prettyPrinted, .sortedKeys])
            try authJsonData.write(to: URL(fileURLWithPath: authPath))
            return .success("Opencode fully configured! Open OpenCode and select model 'ellproxy/auto'. No manual auth needed!")
        } catch {
            // Auth failed but config succeeded - partial success
            return .success("Opencode config created. Auth file failed - please run 'opencode auth login' manually.")
        }
    }
    
    func clearOpencodeCLI() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.opencode/opencode.json"
        
        guard let data = FileManager.default.contents(atPath: configPath),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("Could not read Opencode config")
        }
        
        // Check if configured (look for ellproxy provider)
        guard var provider = config["provider"] as? [String: Any],
              provider["ellproxy"] != nil else {
            return .alreadyConfigured
        }
        
        // Remove ellproxy provider config
        provider.removeValue(forKey: "ellproxy")
        if provider.isEmpty {
            config.removeValue(forKey: "provider")
        } else {
            config["provider"] = provider
        }
        
        // Remove model if it's ellproxy
        if let model = config["model"] as? String, model.contains("ellproxy") {
            config.removeValue(forKey: "model")
        }
        
        // Clean up legacy keys
        config.removeValue(forKey: "openai")
        config.removeValue(forKey: "providers")
        
        // Write updated config
        do {
            let newData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: URL(fileURLWithPath: configPath))
        } catch {
            return .failure("Failed to update Opencode config: \(error.localizedDescription)")
        }
        
        // BONUS: Also remove auth entry
        let authPath = "\(homeDir)/.local/share/opencode/auth.json"
        
        if let authFileData = FileManager.default.contents(atPath: authPath),
           var authData = try? JSONSerialization.jsonObject(with: authFileData) as? [String: Any] {
            
            authData.removeValue(forKey: "ellproxy")
            
            do {
                let updatedAuthData = try JSONSerialization.data(withJSONObject: authData, options: [.prettyPrinted, .sortedKeys])
                try updatedAuthData.write(to: URL(fileURLWithPath: authPath))
            } catch {
                // Auth cleanup failed, but config cleanup succeeded
                return .success("Opencode config removed. Auth cleanup failed - you may need to remove manually.")
            }
        }
        
        return .success("Opencode configuration and auth fully removed.")
    }
}
