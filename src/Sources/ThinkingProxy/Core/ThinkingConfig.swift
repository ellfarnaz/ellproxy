import Foundation

// MARK: - Thinking Proxy Configuration

/// Configuration constants for ThinkingProxy
struct ThinkingConfig {
    /// Hard cap on thinking token budget
    static let hardTokenCap = 32000
    
    /// Minimum headroom to maintain
    static let minimumHeadroom = 1024
    
    /// Headroom ratio (10% of context window)
    static let headroomRatio = 0.1
    
    /// Proxy port (from AppConfig)
    let proxyPort: UInt16 = AppConfig.ellProxyPort
    
    /// Target port (CLIProxyAPI)
    let targetPort: UInt16 = AppConfig.targetPort
    
    /// Target host
    let targetHost = AppConfig.targetHost
}
