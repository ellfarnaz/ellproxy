import Foundation

// MARK: - Trae Proxy Manager

/// Manages Trae-Proxy subprocess lifecycle for MITM proxy on port 443
class TraeProxyManager {
    static let shared = TraeProxyManager()
    
    private var process: Process?
    var pidFile: String { "/tmp/ellproxy_trae_proxy.pid" }
    
    // Trae-Proxy paths (bundled with app)
    var proxyDirectory: String {
        guard let resourcePath = Bundle.main.resourcePath else {
            NSLog("[TraeProxyManager] ❌ Unable to find app resource path")
            return ""
        }
        return "\(resourcePath)/trae-proxy"
    }
    
    private var pythonScript: String {
        "\(proxyDirectory)/trae_proxy.py"
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check if Trae-Proxy is currently running
    /// - Returns: True if process is alive
    func isRunning() -> Bool {
        guard let pid = getStoredPID() else {
            return false
        }
        
        // Check if process exists: kill -0 doesn't kill, just checks
        let result = runShellCommand("kill -0 \(pid) 2>/dev/null")
        return result.exitCode == 0
    }
    
    /// Start Trae-Proxy subprocess
    /// - Returns: Success status and message
    func start() -> (success: Bool, message: String) {
        NSLog("[TraeProxyManager] 🚀 Starting Trae-Proxy...")
        
        // Check if already running
        if isRunning() {
            NSLog("[TraeProxyManager] ⚠️ Trae-Proxy already running")
            return (true, "Trae-Proxy is already running")
        }
        
        // Verify Python script exists
        guard FileManager.default.fileExists(atPath: pythonScript) else {
            NSLog("[TraeProxyManager] ❌ Python script not found: \(pythonScript)")
            return (false, "Trae-Proxy script not found at \(pythonScript)")
        }
        
        // Write startup script to temporary file (avoids AppleScript escaping hell)
        let tempScript = "/tmp/ellproxy_start_trae.sh"
        let scriptContent = """
        #!/bin/bash
        cd "\(proxyDirectory)"
        python3 trae_proxy.py > /tmp/trae-proxy.log 2>&1 &
        echo $! > \(pidFile)
        """
        
        do {
            try scriptContent.write(toFile: tempScript, atomically: true, encoding: .utf8)
            
            // Make executable
            let chmodResult = runShellCommand("chmod +x \(tempScript)")
            if chmodResult.exitCode != 0 {
                return (false, "Failed to make script executable")
            }
        } catch {
            return (false, "Failed to create temp script: \(error.localizedDescription)")
        }
        
        // Run via sudo using simple AppleScript
        let result = runWithSudo(tempScript)
        
        // Clean up temp script
        try? FileManager.default.removeItem(atPath: tempScript)
        
        if result.success {
            // Wait a bit for process to start
            sleep(1)
            
            if isRunning() {
                NSLog("[TraeProxyManager] ✅ Trae-Proxy started successfully")
                return (true, "Trae-Proxy started successfully on port 443")
            } else {
                NSLog("[TraeProxyManager] ❌ Trae-Proxy failed to start")
                return (false, "Trae-Proxy failed to start. Check /tmp/trae-proxy.log")
            }
        } else {
            return (false, "Failed to start Trae-Proxy: \(result.message)")
        }
    }
    
    /// Stop Trae-Proxy subprocess
    /// - Returns: Success status and message
    func stop() -> (success: Bool, message: String) {
        NSLog("[TraeProxyManager] 🛑 Stopping Trae-Proxy...")
        
        guard let pid = getStoredPID() else {
            NSLog("[TraeProxyManager] ⚠️ No PID found, process may not be running")
            return (true, "Trae-Proxy is not running")
        }
        
        // Kill process
        let killScript = "kill \(pid) 2>/dev/null || true"
        let result = runShellCommand(killScript)
        
        // Clean up PID file
        try? FileManager.default.removeItem(atPath: pidFile)
        
        NSLog("[TraeProxyManager] ✅ Trae-Proxy stopped")
        return (true, "Trae-Proxy stopped successfully")
    }
    
    /// Get current status message
    /// - Returns: Human-readable status string
    func getStatus() -> String {
        if isRunning() {
            return "Trae-Proxy running on port 443"
        } else {
            return "Trae-Proxy not running"
        }
    }
    
    // MARK: - Private Methods
    
    /// Run command with sudo privileges via AppleScript
    /// - Parameter command: Shell command or script path to run
    /// - Returns: Success status and output
    private func runWithSudo(_ command: String) -> (success: Bool, message: String) {
        // Simple AppleScript - just run the command/script
        let appleScript = """
        do shell script "\(command)" with administrator privileges
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
                
                if error.contains("User canceled") {
                    return (false, "User cancelled password prompt")
                }
                
                return (false, error)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    /// Run shell command without sudo
    /// - Parameter command: Shell command
    /// - Returns: Exit code and output
    private func runShellCommand(_ command: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
    
    /// Read stored PID from file
    /// - Returns: Process ID if exists
    private func getStoredPID() -> Int? {
        guard let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int(pidString) else {
            return nil
        }
        return pid
    }
}
