import Foundation

// MARK: - Droid CLI Setup Handler

class DroidSetupHandler: ToolSetupHandler {
    let toolId = "droid-cli"
    let toolName = "Droid Factory CLI"
    
    private var ellProxyPort: String { String(AppConfig.ellProxyPort) }
    
    func detect() -> DetectedTool {
        var tool = DetectedTool(
            id: toolId,
            name: toolName,
            icon: "terminal.fill",
            description: "Factory AI's Droid CLI",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Add to ~/.factory/config.json custom_models array:
            {
              "custom_models": [
                {
                  "api_key": "\(AppConfig.API.dummyAPIKey)",
                  "base_url": "\(AppConfig.API.baseURL())",
                  "model": "ellproxy-default",
                  "model_display_name": "EllProxy: Default Model",
                  "provider": "openai"
                },
                {
                  "api_key": "\(AppConfig.API.dummyAPIKey)",
                  "base_url": "\(AppConfig.API.baseURL())",
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
        
        tool.status = .installed
        tool.statusMessage = "Installed, not configured"
        
        let configPath = AppConfig.Paths.droidConfig
        if let configData = FileManager.default.contents(atPath: configPath),
           let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let customModels = configJson["custom_models"] as? [[String: Any]],
           customModels.contains(where: { ($0["model"] as? String) == "ellproxy-default" }) ||
           customModels.contains(where: { ($0["model"] as? String) == "ellproxy-thinking" }) {
            tool.status = .configured
            tool.statusMessage = "Configured for EllProxy"
        }
        
        return tool
    }
    
    func setup() -> SetupManager.SetupResult {
        return SetupManager.shared.setupDroid()
    }
    
    func clear() -> SetupManager.SetupResult {
        return SetupManager.shared.clearDroid()
    }
    
    func copyConfig() -> String {
        return """
        Add to ~/.factory/config.json custom_models array:
        {
          "custom_models": [
            {
              "api_key": "\(AppConfig.API.dummyAPIKey)",
              "base_url": "\(AppConfig.API.baseURL())",
              "model": "ellproxy-default",
              "model_display_name": "EllProxy: Default Model",
              "provider": "openai"
            },
            {
              "api_key": "\(AppConfig.API.dummyAPIKey)",
              "base_url": "\(AppConfig.API.baseURL())",
              "model": "ellproxy-thinking",
              "model_display_name": "EllProxy: Thinking Model",
              "provider": "openai"
            }
          ]
        }
        Then restart Droid CLI
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
