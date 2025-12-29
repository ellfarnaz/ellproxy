import Foundation

// MARK: - Cline Setup Handler

class ClineSetupHandler: ToolSetupHandler {
    let toolId = "vscode-cline"
    let toolName = "VS Code + Cline"
    
    private var ellProxyPort: String { String(AppConfig.ellProxyPort) }
    
    func detect() -> DetectedTool {
        var tool = DetectedTool(
            id: toolId,
            name: toolName,
            icon: "chevron.left.forwardslash.chevron.right",
            description: "Cline AI extension for VS Code",
            status: .notInstalled,
            statusMessage: "VS Code not found",
            configInstructions: """
            In Cline settings:
            • API Provider: OpenAI Compatible
            • Base URL: \(AppConfig.API.baseURL())/v1
            • API Key: \(AppConfig.API.dummyAPIKey)
            • Model: \(AppConfig.API.defaultModelId)
            """
        )
        
        let vscodeApps = [
            AppConfig.Paths.vscodeApp,
            AppConfig.Paths.vscodiumApp,
            AppConfig.Paths.cursorApp
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
        
        tool.status = .installed
        tool.statusMessage = "Cline extension status unknown"
        
        let settingsPaths = [
            AppConfig.Paths.vscodeSettings,
            AppConfig.Paths.vscodiumSettings
        ]
        
        for settingsPath in settingsPaths {
            if let settings = try? String(contentsOfFile: settingsPath, encoding: .utf8) {
                if (settings.contains("cline") || settings.contains("claude-dev")) &&
                   settings.contains("127.0.0.1:\(ellProxyPort)") {
                    tool.status = .configured
                    tool.statusMessage = "Configured for EllProxy"
                    break
                } else if settings.contains("cline") || settings.contains("claude-dev") {
                    tool.statusMessage = "Cline installed, not configured for EllProxy"
                }
            }
        }
        
        return tool
    }
    
    func setup() -> SetupManager.SetupResult {
        return SetupManager.shared.setupCline()
    }
    
    func clear() -> SetupManager.SetupResult {
        return SetupManager.shared.clearCline()
    }
    
    func copyConfig() -> String {
        return """
        Cline Settings:
        • API Provider: OpenAI Compatible
        • Base URL: \(AppConfig.API.baseURL())
        • API Key: \(AppConfig.API.dummyAPIKey)
        • Model: \(AppConfig.API.defaultModelId)
        """
    }
}
