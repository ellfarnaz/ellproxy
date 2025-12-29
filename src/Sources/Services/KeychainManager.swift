import Foundation

/// Manages secure storage in Application Support directory
/// (Files are deleted when app is uninstalled)
class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Application Support Directory
    
    private var appSupportDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ellproxyDir = appSupport.appendingPathComponent("EllProxy")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: ellproxyDir, withIntermediateDirectories: true)
        
        return ellproxyDir
    }
}
