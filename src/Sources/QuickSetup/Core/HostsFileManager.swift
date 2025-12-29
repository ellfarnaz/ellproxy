import Foundation

// MARK: - Hosts File Manager

/// Manages modifications to /etc/hosts file for MITM proxy setup
class HostsFileManager {
    static let shared = HostsFileManager()
    
    private let hostsPath = "/etc/hosts"
    private let backupPath = "/tmp/ellproxy_hosts_backup"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Add an entry to /etc/hosts
    /// - Parameters:
    ///   - ip: IP address (e.g., "127.0.0.1")
    ///   - domain: Domain name (e.g., "api.openai.com")
    /// - Returns: Success status and message
    func addEntry(ip: String, domain: String) -> (success: Bool, message: String) {
        // Check if entry already exists
        if hasEntry(domain: domain) {
            return (true, "Entry for \(domain) already exists in hosts file")
        }
        
        // Backup hosts file first
        let backupResult = backupHosts()
        if !backupResult.success {
            return backupResult
        }
        
        // Create entry to add
        let entry = "\n# Added by EllProxy for Trae IDE\n\(ip) \(domain)\n"
        
        // Write entry to temporary file first (avoids AppleScript escaping issues)
        let tempFile = "/tmp/ellproxy_hosts_entry"
        do {
            try entry.write(toFile: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return (false, "Failed to create temporary file: \(error.localizedDescription)")
        }
        
        // Use cat to append temp file to hosts (simpler for AppleScript)
        let script = "cat \(tempFile) >> \(hostsPath)"
        
        let result = runShellScript(script)
        
        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempFile)
        
        if result.success {
            NSLog("[HostsFileManager] ✅ Added entry: \(ip) \(domain)")
            return (true, "Successfully added \(domain) to hosts file")
        } else {
            return (false, "Failed to modify hosts file: \(result.message)")
        }
    }
    
    /// Remove an entry from /etc/hosts
    /// - Parameter domain: Domain name to remove
    /// - Returns: Success status and message
    func removeEntry(domain: String) -> (success: Bool, message: String) {
        // Check if entry exists
        if !hasEntry(domain: domain) {
            return (true, "Entry for \(domain) not found in hosts file")
        }
        
        // Backup hosts file first
        let backupResult = backupHosts()
        if !backupResult.success {
            return backupResult
        }
        
        // Read current hosts file
        guard let hostsContent = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return (false, "Failed to read hosts file")
        }
        
        // Filter out EllProxy entries
        let lines = hostsContent.components(separatedBy: "\n")
        var filtered: [String] = []
        var skipNext = false
        
        for line in lines {
            if line.contains("# Added by EllProxy for Trae IDE") {
                skipNext = true
                continue
            }
            if skipNext && line.contains(domain) {
                skipNext = false
                continue
            }
            filtered.append(line)
        }
        
        let newContent = filtered.joined(separator: "\n")
        
        // Write to temp file
        let tempFile = "/tmp/ellproxy_hosts_new"
        do {
            try newContent.write(toFile: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return (false, "Failed to create temporary file: \(error.localizedDescription)")
        }
        
        // Replace hosts file with temp file
        let script = "cat \(tempFile) > \(hostsPath)"
        
        let result = runShellScript(script)
        
        // Clean up
        try? FileManager.default.removeItem(atPath: tempFile)
        
        if result.success {
            NSLog("[HostsFileManager] ✅ Removed entry: \(domain)")
            return (true, "Successfully removed \(domain) from hosts file")
        } else {
            return (false, "Failed to modify hosts file: \(result.message)")
        }
    }
    
    /// Check if an entry exists in /etc/hosts
    /// - Parameter domain: Domain name to check
    /// - Returns: True if entry exists
    func hasEntry(domain: String) -> Bool {
        guard let hostsContent = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return false
        }
        
        return hostsContent.contains(domain)
    }
    
    /// Create a backup of /etc/hosts
    /// - Returns: Success status and message
    func backupHosts() -> (success: Bool, message: String) {
        let script = "sudo cp \(hostsPath) \(backupPath)"
        let result = runShellScript(script)
        
        if result.success {
            NSLog("[HostsFileManager] 💾 Backed up hosts file to \(backupPath)")
            return (true, "Hosts file backed up successfully")
        } else {
            return (false, "Failed to backup hosts file: \(result.message)")
        }
    }
    
    /// Restore /etc/hosts from backup
    /// - Returns: Success status and message
    func restoreHosts() -> (success: Bool, message: String) {
        // Check if backup exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupPath) else {
            return (false, "Backup file not found at \(backupPath)")
        }
        
        let script = "sudo cp \(backupPath) \(hostsPath)"
        let result = runShellScript(script)
        
        if result.success {
            NSLog("[HostsFileManager] ♻️ Restored hosts file from backup")
            return (true, "Hosts file restored from backup")
        } else {
            return (false, "Failed to restore hosts file: \(result.message)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Run a shell script with sudo privileges using AppleScript for GUI password prompt
    /// - Parameter script: Shell script to execute
    /// - Returns: Success status and output/error message
    private func runShellScript(_ script: String) -> (success: Bool, message: String) {
        // Escape single quotes in script for AppleScript
        let escapedScript = script.replacingOccurrences(of: "'", with: "'\\''")
        
        // Use AppleScript to run the command with admin privileges (GUI password prompt)
        let appleScript = """
        do shell script "\(escapedScript)" with administrator privileges
        """
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let exitCode = process.terminationStatus
            
            if exitCode == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (true, output)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                
                // User cancelled password prompt
                if error.contains("User canceled") {
                    return (false, "User cancelled password prompt")
                }
                
                return (false, error)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
