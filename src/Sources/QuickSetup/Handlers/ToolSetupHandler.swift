import Foundation

// MARK: - Tool Setup Handler Protocol

/// Protocol for handling tool setup, detection, and configuration
protocol ToolSetupHandler {
    /// Unique tool identifier
    var toolId: String { get }
    
    /// Tool display name
    var toolName: String { get }
    
    /// Detects if the tool is installed and configured
    func detect() -> DetectedTool
    
    /// Sets up the tool configuration
    func setup() -> SetupManager.SetupResult
    
    /// Clears the tool configuration
    func clear() -> SetupManager.SetupResult
    
    /// Returns configuration text for clipboard
    func copyConfig() -> String
}

// MARK: - Default Implementations

extension ToolSetupHandler {
    /// Default copy config returns basic instructions
    func copyConfig() -> String {
        return "Configuration for \(toolName)"
    }
}
