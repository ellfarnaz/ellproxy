import Foundation

// MARK: - Auth Command

/// Authentication commands for CLI Proxy API
public enum AuthCommand: Equatable {
    case claudeLogin
    case codexLogin
    case copilotLogin
    case geminiLogin
    case qwenLogin(email: String)
    case antigravityLogin
    case iflowLogin
    case kiroLogin
}
