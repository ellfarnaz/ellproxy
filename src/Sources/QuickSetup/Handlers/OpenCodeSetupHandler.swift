import Foundation

// MARK: - OpenCode CLI Setup Handler

class OpenCodeSetupHandler: ToolSetupHandler {
    let toolId = "opencode-cli"
    let toolName = "OpenCode CLI"
    
    private var ellProxyPort: String { String(AppConfig.ellProxyPort) }
    
    func detect() -> DetectedTool {
        var tool = DetectedTool(
            id: toolId,
            name: toolName,
            icon: "terminal.fill",
            description: "OpenCode.ai CLI Assistant",
            status: .notInstalled,
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
                    "baseURL": "\(AppConfig.API.baseURL())/v1"
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
            """
        )
        
        let whichResult = runCommand("/usr/bin/which", arguments: ["opencode"])
        var isInstalled = !whichResult.isEmpty && !whichResult.contains("not found")
        
        // Fallback: Check standard installation path
        let homeDir = AppConfig.Paths.homeDir
        let standardPath = "\(homeDir)/.opencode/bin/opencode"
        if !isInstalled && FileManager.default.fileExists(atPath: standardPath) {
            isInstalled = true
        }
        
        if !isInstalled {
            return tool
        }
        
        tool.status = ToolStatus.installed
        tool.statusMessage = "Installed, not configured"
        
        // Check configuration (look for ellproxy provider)
        let configPath = "\(homeDir)/.opencode/opencode.json"
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let provider = json["provider"] as? [String: Any],
           provider["ellproxy"] != nil {
            
            tool.status = ToolStatus.configured
            tool.statusMessage = "Configured for EllProxy"
        }
        
        return tool
    }
    
    func setup() -> SetupManager.SetupResult {
        return SetupManager.shared.setupOpencodeCLI()
    }
    
    func clear() -> SetupManager.SetupResult {
        return SetupManager.shared.clearOpencodeCLI()
    }
    
    func copyConfig() -> String {
        return """
        Add to ~/.opencode/opencode.json:
        {
          "$schema": "https://opencode.ai/config.json",
          "provider": {
            "ellproxy": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "EllProxy (Dynamic)",
              "options": {
                "baseURL": "\(AppConfig.API.baseURL())/v1"
              },
              "models": {
                "auto": {
                  "name": "Auto (uses EllProxy default model)"
                }
              }
            }
          }
        }
        
        Then run:
        1. opencode auth login
        2. Select "Other"
        3. Provider ID: ellproxy
        4. API Key: dummy-key
        5. In OpenCode, select model: ellproxy/auto
        """
    }
    
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
