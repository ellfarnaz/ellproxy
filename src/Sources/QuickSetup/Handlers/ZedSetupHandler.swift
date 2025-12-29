import Foundation

// MARK: - Zed Setup Handler

class ZedSetupHandler: ToolSetupHandler {
    let toolId = "zed"
    let toolName = "Zed"
    
    private var ellProxyPort: String { String(AppConfig.ellProxyPort) }
    
    func detect() -> DetectedTool {
        var tool = DetectedTool(
            id: toolId,
            name: toolName,
            icon: "bolt",
            description: "High-performance code editor",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            In Zed settings.json, add:
            {
              "language_models": {
                "openai": {
                  "api_url": "\(AppConfig.API.baseURL())",
                  "api_key": "\(AppConfig.API.dummyAPIKey)"
                }
              }
            }
            """
        )
        
        if FileManager.default.fileExists(atPath: AppConfig.Paths.zedApp) {
            tool.status = .installed
            tool.statusMessage = "Installed"
            
            let settingsPath = AppConfig.Paths.zedSettings
            if let settings = try? String(contentsOfFile: settingsPath, encoding: .utf8) {
                if settings.contains("127.0.0.1:\(ellProxyPort)") {
                    tool.status = .configured
                    tool.statusMessage = "Configured for EllProxy"
                }
            }
        }
        
        return tool
    }
    
    func setup() -> SetupManager.SetupResult {
        return SetupManager.shared.setupZed()
    }
    
    func clear() -> SetupManager.SetupResult {
        return SetupManager.shared.clearZed()
    }
    
    func copyConfig() -> String {
        return """
        Add to ~/.config/zed/settings.json:
        {
          "language_models": {
            "openai": {
              "api_url": "\(AppConfig.API.baseURL())",
              "api_key": "\(AppConfig.API.dummyAPIKey)"
            }
          }
        }
        """
    }
}
