import Foundation

// MARK: - Claude CLI Setup Handler

class ClaudeSetupHandler: ToolSetupHandler {
    let toolId = "claude-cli"
    let toolName = "Claude CLI"
    
    private var ellProxyPort: String { String(AppConfig.ellProxyPort) }
    
    func detect() -> DetectedTool {
        var tool = DetectedTool(
            id: toolId,
            name: toolName,
            icon: "terminal",
            description: "Anthropic's Claude Code CLI",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Add to ~/.zshrc:
            export ANTHROPIC_BASE_URL="\(AppConfig.API.anthropicBaseURL())"
            export ANTHROPIC_API_KEY="\(AppConfig.API.dummyAPIKey)"
            """
        )
        
        let whichResult = runCommand("/usr/bin/which", arguments: ["claude"])
        if whichResult.isEmpty || whichResult.contains("not found") {
            return tool
        }
        
        tool.status = .installed
        tool.statusMessage = "Installed, not configured"
        
        let homeDir = AppConfig.Paths.homeDir
        let zshrcPath = AppConfig.Paths.zshrc
        let bashrcPath = AppConfig.Paths.bashrc
        
        if let zshrc = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
           zshrc.contains("ANTHROPIC_BASE_URL") && zshrc.contains("127.0.0.1:\(ellProxyPort)") {
            tool.status = .configured
            tool.statusMessage = "Configured in ~/.zshrc"
        } else if let bashrc = try? String(contentsOfFile: bashrcPath, encoding: .utf8),
                  bashrc.contains("ANTHROPIC_BASE_URL") && bashrc.contains("127.0.0.1:\(ellProxyPort)") {
            tool.status = .configured
            tool.statusMessage = "Configured in ~/.bashrc"
        }
        
        return tool
    }
    
    func setup() -> SetupManager.SetupResult {
        return SetupManager.shared.setupClaudeCLI()
    }
    
    func clear() -> SetupManager.SetupResult {
        return SetupManager.shared.clearClaudeCLI()
    }
    
    func copyConfig() -> String {
        return """
        # Add to ~/.zshrc or ~/.bashrc
        export ANTHROPIC_BASE_URL="\(AppConfig.API.anthropicBaseURL())"
        export ANTHROPIC_API_KEY="\(AppConfig.API.dummyAPIKey)"
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
