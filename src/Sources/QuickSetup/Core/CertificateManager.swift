import Foundation
import AppKit

// MARK: - Certificate Manager

/// Manages SSL certificate generation and installation for MITM proxy setup
class CertificateManager {
    static let shared = CertificateManager()
    
    private let certificatesDir: String
    private let domain = "api.openai.com"
    
    private init() {
        // Store certificates in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ellProxyDir = appSupport.appendingPathComponent("EllProxy")
        certificatesDir = ellProxyDir.appendingPathComponent("certificates").path
        
        // Create certificates directory if it doesn't exist
        try? FileManager.default.createDirectory(atPath: certificatesDir, withIntermediateDirectories: true, attributes: nil)
    }
    
    // MARK: - Public Methods
    
    /// Generate self-signed certificate for api.openai.com
    /// - Returns: Success status and message
    func generateSelfSignedCertificate() -> (success: Bool, message: String) {
        let keyPath = getCertificateKeyPath()
        let crtPath = getCertificatePath()
        
        // Check if certificate already exists
        if FileManager.default.fileExists(atPath: crtPath) {
            return (true, "Certificate already exists at \(crtPath)")
        }
        
        NSLog("[CertificateManager] 🔐 Generating self-signed certificate for \(domain)")
        
        // Generate private key
        let keyGenScript = """
        openssl genrsa -out "\(keyPath)" 2048 2>&1
        """
        
        let keyResult = runShellScript(keyGenScript)
        if !keyResult.success {
            return (false, "Failed to generate private key: \(keyResult.message)")
        }
        
        // Generate self-signed certificate
        let certGenScript = """
        openssl req -new -x509 -key "\(keyPath)" \
          -out "\(crtPath)" -days 365 \
          -subj "/CN=\(domain)" 2>&1
        """
        
        let certResult = runShellScript(certGenScript)
        if !certResult.success {
            return (false, "Failed to generate certificate: \(certResult.message)")
        }
        
        NSLog("[CertificateManager] ✅ Certificate generated successfully")
        NSLog("[CertificateManager] 📍 Key: \(keyPath)")
        NSLog("[CertificateManager] 📍 Cert: \(crtPath)")
        
        return (true, "Certificate generated at \(crtPath)")
    }
    
    /// Get the path to the certificate file
    /// - Returns: Full path to .crt file
    func getCertificatePath() -> String {
        return "\(certificatesDir)/\(domain).crt"
    }
    
    /// Get the path to the certificate key file
    /// - Returns: Full path to .key file
    func getCertificateKeyPath() -> String {
        return "\(certificatesDir)/\(domain).key"
    }
    
    /// Check if certificate exists
    /// - Returns: True if certificate file exists
    func certificateExists() -> Bool {
        return FileManager.default.fileExists(atPath: getCertificatePath())
    }
    
    /// Remove generated certificates AND from all keychains (DEEP CLEAN!)
    /// - Returns: Success status and message
    func removeCertificateCompletely() -> (success: Bool, message: String) {
        let crtPath = getCertificatePath()
        let keyPath = getCertificateKeyPath()
        
        var messages: [String] = []
        var hadErrors = false
        
        // Step 1: Remove from System Keychain (requires sudo)
        NSLog("[CertificateManager] 🧹 Removing certificate from System Keychain...")
        
        // Use temp script file to avoid AppleScript escaping issues
        let tempCleanupScript = "/tmp/vp-sysclean.sh"
        let cleanupScriptContent = """
        #!/bin/bash
        security delete-certificate -c "\(domain)" -t /Library/Keychains/System.keychain 2>/dev/null || true
        """
        
        do {
            try cleanupScriptContent.write(toFile: tempCleanupScript, atomically: true, encoding: .utf8)
            _ = runShellScript("chmod +x \(tempCleanupScript)")
        } catch {
            messages.append("⚠️ Failed to create cleanup script")
            hadErrors = true
        }
        
        let systemResult = runWithSudo(tempCleanupScript)
        try? FileManager.default.removeItem(atPath: tempCleanupScript)
        
        if systemResult.success || systemResult.message.contains("not be found") {
            messages.append("✅ Removed from System Keychain")
            NSLog("[CertificateManager] ✅ Removed from System Keychain")
        } else {
            messages.append("⚠️ System Keychain: \(systemResult.message)")
            hadErrors = true
        }
        
        // Step 2: Remove from Login Keychain (no sudo needed)
        NSLog("[CertificateManager] 🧹 Removing certificate from Login Keychain...")
        let loginCleanup = runShellScript("security delete-certificate -c \"\(domain)\" -t ~/Library/Keychains/login.keychain-db 2>&1 || true")
        if loginCleanup.success || loginCleanup.message.contains("not be found") {
            messages.append("✅ Removed from Login Keychain")
            NSLog("[CertificateManager] ✅ Removed from Login Keychain")
        } else {
            messages.append("⚠️ Login Keychain: \(loginCleanup.message)")
        }
        
        // Step 3: Remove certificate files
        var filesRemoved = false
        if FileManager.default.fileExists(atPath: crtPath) {
            do {
                try FileManager.default.removeItem(atPath: crtPath)
                NSLog("[CertificateManager] 🗑️ Removed certificate file: \(crtPath)")
                filesRemoved = true
            } catch {
                messages.append("⚠️ Failed to remove certificate file")
                hadErrors = true
            }
        }
        
        if FileManager.default.fileExists(atPath: keyPath) {
            do {
                try FileManager.default.removeItem(atPath: keyPath)
                NSLog("[CertificateManager] 🗑️ Removed key file: \(keyPath)")
                filesRemoved = true
            } catch {
                messages.append("⚠️ Failed to remove key file")
                hadErrors = true
            }
        }
        
        if filesRemoved {
            messages.append("✅ Certificate files deleted")
        }
        
        // Step 4: Verify everything is clean
        let verifySystem = runShellScript("security find-certificate -c \"\(domain)\" /Library/Keychains/System.keychain 2>&1")
        let verifyLogin = runShellScript("security find-certificate -c \"\(domain)\" ~/Library/Keychains/login.keychain-db 2>&1")
        
        if verifySystem.message.contains("could not be found") && verifyLogin.message.contains("could not be found") {
            messages.append("✅ Verification: All keychains clean")
            NSLog("[CertificateManager] ✅ VERIFICATION PASSED: Certificate completely removed")
        } else {
            if !verifySystem.message.contains("could not be found") {
                messages.append("⚠️ WARNING: Still found in System Keychain!")
                NSLog("[CertificateManager] ⚠️ Certificate still in System Keychain")
                hadErrors = true
            }
            if !verifyLogin.message.contains("could not be found") {
                messages.append("⚠️ WARNING: Still found in Login Keychain!")
                NSLog("[CertificateManager] ⚠️ Certificate still in Login Keychain")
            }
        }
        
        let finalMessage = messages.joined(separator: "\n")
        
        if hadErrors {
            return (false, "Cleanup completed with warnings:\n\(finalMessage)")
        } else if messages.isEmpty {
            return (true, "Nothing to clean - certificates not found")
        } else {
            return (true, "Complete cleanup successful:\n\(finalMessage)")
        }
    }
    
    /// Get installation instructions for the certificate
    /// - Returns: User-friendly installation instructions
    func getInstallationInstructions() -> String {
        let crtPath = getCertificatePath()
        
        return """
        📜 Certificate Installation Instructions
        
        ⚠️ IMPORTANT: You must install and trust the certificate for Trae to work with EllProxy.
        
        1. Open Finder and navigate to:
           \(crtPath)
        
        2. Double-click the certificate file
           → This will open "Keychain Access"
        
        3. Add the certificate to the "System" keychain
        
        4. Double-click the imported certificate
        
        5. Expand the "Trust" section
        
        6. Set "When using this certificate" to "Always Trust"
        
        7. Close the window and enter your password to confirm
        
        ✅ Once installed, Trae will be able to connect to EllProxy!
        """
    }
    
    /// Open the certificates directory in Finder
    func openCertificatesDirectory() {
        NSWorkspace.shared.open(URL(fileURLWithPath: certificatesDir))
    }
    
    /// Trust certificate in System Keychain using authorizationdb (for Trae IDE)
    /// This temporarily disables macOS trust settings security to automate certificate trust
    /// - Returns: Success status and message
    func trustCertificateInSystemKeychain() -> (success: Bool, message: String) {
        let crtPath = getCertificatePath()
        
        // Check if certificate exists
        guard FileManager.default.fileExists(atPath: crtPath) else {
            return (false, "Certificate file not found")
        }
        
        NSLog("[CertificateManager] 🔒 Trusting certificate in System Keychain (authorizationdb)...")
        
        // Write trust script with trap for guaranteed cleanup
        let tempScript = "/tmp/vp-systrust.sh"
        let scriptContent = """
        #!/bin/bash
        set -e
        
        # CRITICAL: Ensure security is always restored (even on error/interrupt)
        trap 'security authorizationdb remove com.apple.trust-settings.admin 2>/dev/null || true' EXIT INT TERM
        
        # Temporarily disable trust settings security check
        security authorizationdb write com.apple.trust-settings.admin allow
        
        # Add and trust certificate in System Keychain
        security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "\(crtPath)"
        
        # Security will be re-enabled by trap on exit
        """
        
        do {
            try scriptContent.write(toFile: tempScript, atomically: true, encoding: .utf8)
            
            // Make executable
            let chmodResult = runShellScript("chmod +x \(tempScript)")
            if !chmodResult.success {
                return (false, "Failed to make trust script executable")
            }
        } catch {
            return (false, "Failed to create trust script: \(error.localizedDescription)")
        }
        
        // Run via sudo
        let result = runWithSudo(tempScript)
        
        // Clean up temp script
        try? FileManager.default.removeItem(atPath: tempScript)
        
        if result.success {
            // Verify security was restored
            let verifyResult = runShellScript("security authorizationdb read com.apple.trust-settings.admin 2>&1")
            if verifyResult.message.contains("allow") {
                NSLog("[CertificateManager] ⚠️ Security check still disabled! Force re-enabling...")
                _ = runWithSudo("security authorizationdb remove com.apple.trust-settings.admin")
            }
            
            NSLog("[CertificateManager] ✅ Certificate trusted in System Keychain")
            return (true, "Certificate trusted automatically in System Keychain")
        } else {
            // Force security restore on failure
            _ = runWithSudo("security authorizationdb remove com.apple.trust-settings.admin")
            return (false, "Failed to trust certificate: \(result.message)")
        }
    }
    
    /// Trust certificate in System keychain (requires sudo)
    /// - Returns: Success status and message
    func trustCertificate() -> (success: Bool, message: String) {
        let crtPath = getCertificatePath()
        
        // Check if certificate exists
        guard FileManager.default.fileExists(atPath: crtPath) else {
            return (false, "Certificate file not found")
        }
        
        NSLog("[CertificateManager] 🔒 Trusting certificate in System keychain...")
        
        // Write trust script to temp file
        let tempScript = "/tmp/ellproxy_trust_cert.sh"
        let scriptContent = """
        #!/bin/bash
        security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "\(crtPath)"
        """
        
        do {
            try scriptContent.write(toFile: tempScript, atomically: true, encoding: .utf8)
            
            // Make executable
            let chmodResult = runShellScript("chmod +x \(tempScript)")
            if !chmodResult.success {
                return (false, "Failed to make trust script executable")
            }
        } catch {
            return (false, "Failed to create trust script: \(error.localizedDescription)")
        }
        
        // Run via sudo
        let result = runWithSudo(tempScript)
        
        // Clean up
        try? FileManager.default.removeItem(atPath: tempScript)
        
        if result.success {
            NSLog("[CertificateManager] ✅ Certificate trusted successfully")
            return (true, "Certificate trusted in System keychain")
        } else {
            return (false, "Failed to trust certificate: \(result.message)")
        }
    }
    
    /// Remove certificate from System keychain (requires sudo)
    /// - Returns: Success status and message
    func untrustCertificate() -> (success: Bool, message: String) {
        NSLog("[CertificateManager] 🔓 Removing certificate from System keychain...")
        
        // Write untrust script to temp file
        let tempScript = "/tmp/ellproxy_untrust_cert.sh"
        let scriptContent = """
        #!/bin/bash
        security delete-certificate -c "\(domain)" -t /Library/Keychains/System.keychain 2>/dev/null || true
        """
        
        do {
            try scriptContent.write(toFile: tempScript, atomically: true, encoding: .utf8)
            
            // Make executable
            let chmodResult = runShellScript("chmod +x \(tempScript)")
            if !chmodResult.success {
                return (false, "Failed to make untrust script executable")
            }
        } catch {
            return (false, "Failed to create untrust script: \(error.localizedDescription)")
        }
        
        // Run via sudo
        let result = runWithSudo(tempScript)
        
        // Clean up
        try? FileManager.default.removeItem(atPath: tempScript)
        
        NSLog("[CertificateManager] ✅ Certificate removed from keychain")
        return (true, "Certificate removed from System keychain")
    }
    
    /// Run command with sudo privileges via AppleScript
    /// - Parameter command: Shell command or script path to run
    /// - Returns: Success status and output
    private func runWithSudo(_ command: String) -> (success: Bool, message: String) {
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
    
    // MARK: - Private Methods
    
    /// Run a shell script with proper error handling
    /// - Parameter script: Shell script to execute
    /// - Returns: Success status and output/error message
    private func runShellScript(_ script: String) -> (success: Bool, message: String) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
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
                return (false, error)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
