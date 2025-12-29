import Foundation

// MARK: - Application Configuration

/// Centralized configuration for EllProxy
/// All constants, ports, paths, and URLs are defined here
enum AppConfig {
    
    // MARK: - Network Configuration
    
    /// Main EllProxy port (ThinkingProxy)
    static let ellProxyPort: UInt16 = 8317
    
    /// Target port (CLIProxyAPI)
    static let targetPort: UInt16 = 8318
    
    /// Target host
    static let targetHost = "127.0.0.1"
    
    // MARK: - Paths
    
    enum Paths {
        /// User's home directory
        static let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        // VS Code paths
        static var vscodeSettings: String {
            "\(homeDir)/Library/Application Support/Code/User/settings.json"
        }
        
        static var vscodeState: String {
            "\(homeDir)/Library/Application Support/Code/User/globalStorage/state.vscdb"
        }
        
        static var vscodiumSettings: String {
            "\(homeDir)/Library/Application Support/VSCodium/User/settings.json"
        }
        
        // Zed paths
        static var zedSettings: String {
            "\(homeDir)/.config/zed/settings.json"
        }
        
        // Droid CLI paths
        static var droidConfig: String {
            "\(homeDir)/.factory/config.json"
        }
        
        static var droidSettings: String {
            "\(homeDir)/.factory/settings.json"
        }
        
        // Shell rc files
        static var zshrc: String {
            "\(homeDir)/.zshrc"
        }
        
        static var bashrc: String {
            "\(homeDir)/.bashrc"
        }
        
        // Application paths
        static let vscodeApp = "/Applications/Visual Studio Code.app"
        static let vscodiumApp = "/Applications/VSCodium.app"
        static let cursorApp = "/Applications/Cursor.app"
        static let windsurfApp = "/Applications/Windsurf.app"
        static let zedApp = "/Applications/Zed.app"
    }
    
    // MARK: - API Configuration
    
    enum API {
        /// Base URL for EllProxy API
        static func baseURL(port: UInt16 = ellProxyPort) -> String {
            "http://127.0.0.1:\(port)/v1"
        }
        
        /// Anthropic API base URL for Claude CLI
        static func anthropicBaseURL(port: UInt16 = ellProxyPort) -> String {
            "http://127.0.0.1:\(port)"
        }
        
        /// Dummy API key for local development
        static let dummyAPIKey = "dummy"
        
        /// Default model ID
        static let defaultModelId = "ellproxy-model"
    }
    
    // MARK: - Tool Configuration
    
    enum Tool {
        /// Cline settings keys
        enum Cline {
            static let apiProvider = "cline.apiProvider"
            static let openaiBaseUrl = "cline.openaiBaseUrl"
            static let openaiApiKey = "cline.openaiApiKey"
            static let openaiModelId = "cline.openaiModelId"
            static let stateKey = "saoudrizwan.claude-dev"
        }
        
        /// Environment variables for Claude CLI
        enum Claude {
            static let baseURLKey = "ANTHROPIC_BASE_URL"
            static let apiKeyKey = "ANTHROPIC_API_KEY"
        }
    }
}
