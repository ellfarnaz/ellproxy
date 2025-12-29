import Foundation

/// Shared types and constants for ThinkingProxy
enum ThinkingProxyConstants {
    /// Buffer size for receiving data chunks
    static let receiveBufferSize = 1_048_576 // 1 MB
    
    /// Maximum buffer size for streaming
    static let maxStreamingBufferSize = 65_536 // 64 KB
    
    /// HTTP line ending
    static let httpLineEnding = "\r\n"
    
    /// HTTP header separator
    static let httpHeaderSeparator = "\r\n\r\n"
}

/// Type aliases for cleaner code
typealias HTTPHeaders = [(String, String)]
typealias JSONDictionary = [String: Any]
