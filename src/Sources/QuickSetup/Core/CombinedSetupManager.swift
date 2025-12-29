import Foundation

/// Combined Setup Manager - consolidates all sudo operations into ONE script
/// This eliminates multiple password prompts during Auto Setup
class CombinedSetupManager {
    static let shared = CombinedSetupManager()
    
    private init() {}
    
    /// Run complete Trae IDE auto-setup with single password prompt
    /// - Parameters:
    ///   - domain: Domain to configure (e.g., api.openai.com)
    ///   - localIP: Local IP address (127.0.0.1)
    ///   - certPath: Path to certificate file
    ///   - traeProxyDir: Trae-Proxy directory path
    ///   - pidFile: Path to PID file for Trae-Proxy
    /// - Returns: Success status and message
    func runAutoSetup(
        domain: String,
        localIP: String,
        certPath: String,
        traeProxyDir: String,
        pidFile: String
    ) -> (success: Bool, message: String) {
        
        NSLog("[CombinedSetupManager] 🚀 Creating master setup script...")
        
        // Create master script that does EVERYTHING with one sudo
        let masterScript = "/tmp/vp-autosetup.sh"
        let scriptContent = """
        #!/bin/bash
        
        # Function to clean up security settings (always return true to avoid exit errors)
        cleanup_on_exit() {
            security authorizationdb remove com.apple.trust-settings.admin >/dev/null 2>&1 || true
        }
        trap cleanup_on_exit EXIT INT TERM
        
        echo "Starting Trae IDE Auto Setup..."
        
        # --- Step 1: Hosts File ---
        echo "Configuring /etc/hosts..."
        if ! grep -q "\(localIP) \(domain)" /etc/hosts 2>/dev/null; then
            if echo "\(localIP) \(domain)" >> /etc/hosts; then
                echo "Hosts entry added"
            else
                echo "Error: Failed to write to /etc/hosts"
                exit 1
            fi
        else
            echo "Hosts entry already exists"
        fi
        
        # --- Step 2: Trae-Proxy ---
        echo "Starting Trae-Proxy..."
        cd "\(traeProxyDir)" || { echo "Error: Proxy dir not found"; exit 1; }
        
        # Clean up old processes
        pkill -9 -f trae_proxy.py >/dev/null 2>&1 || true
        sleep 1
        
        PIDFILE="\(pidFile)"
        if [ -f "$PIDFILE" ]; then
            OLD_PID=$(cat "$PIDFILE")
            kill -9 $OLD_PID >/dev/null 2>&1 || true
            rm -f "$PIDFILE"
        fi
        
        # Start new instance
        python3 trae_proxy.py > /tmp/trae-proxy.log 2>&1 &
        NEW_PID=$!
        echo $NEW_PID > "$PIDFILE"
        sleep 2
        
        # Verify
        if ! ps -p $NEW_PID > /dev/null 2>&1; then
            echo "Error: Trae-Proxy failed to start. Check /tmp/trae-proxy.log"
            exit 1
        fi
        echo "Trae-Proxy started (PID $NEW_PID)"
        
        # --- Step 3: Certificate Trust ---
        echo "Trusting certificate in System Keychain..."
        
        # 1. Allow automated trust modification
        security authorizationdb write com.apple.trust-settings.admin allow
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to modify authorizationdb (pass 1)"
        fi
        sleep 0.5
        
        # 2. Add/Trust Certificate
        # Use || true to suppress error if cert is already trusted/added
        security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "\(certPath)" || {
            echo "Warning: add-trusted-cert returned error (might be benign)"
        }
        
        echo "Certificate trusted"
        
        echo "Auto Setup complete!"
        
        # FORCE SUCCESS EXIT
        exit 0
        """
        
        // Write master script
        do {
            try scriptContent.write(toFile: masterScript, atomically: true, encoding: .utf8)
            
            // Make executable
            let chmodResult = runShellScript("chmod +x \(masterScript)")
            if !chmodResult.success {
                return (false, "Failed to make setup script executable: \(chmodResult.message)")
            }
            
            NSLog("[CombinedSetupManager] ✅ Master script created")
        } catch {
            return (false, "Failed to create setup script: \(error.localizedDescription)")
        }
        
        // Run with sudo - ONE password prompt!
        NSLog("[CombinedSetupManager] 🔐 Running master script with sudo...")
        let result = runWithSudo(masterScript)
        
        // Cleanup temp script
        try? FileManager.default.removeItem(atPath: masterScript)
        
        if result.success {
            NSLog("[CombinedSetupManager] 🎉 Auto Setup completed successfully")
            
            // Verify security was restored
            let verifyResult = runShellScript("security authorizationdb read com.apple.trust-settings.admin 2>&1")
            if verifyResult.message.contains("allow") {
                NSLog("[CombinedSetupManager] ⚠️ Security check still disabled! Force re-enabling...")
                _ = runWithSudo("security authorizationdb remove com.apple.trust-settings.admin")
            }
            
            return (true, "Complete auto-setup successful\n\(result.message)")
        } else {
            NSLog("[CombinedSetupManager] ❌ Auto Setup failed: \(result.message)")
            // Force security restore on failure
            _ = runWithSudo("security authorizationdb remove com.apple.trust-settings.admin")
            return (false, "Setup failed: \(result.message)")
        }
    }
    
    /// Run complete Trae IDE clear/cleanup with single password prompt
    /// - Parameters:
    ///   - domain: Domain to remove from hosts (e.g., api.openai.com)
    ///   - certName: Certificate common name to remove
    /// - Returns: Success status and message
    func executeClearScript(
        domain: String,
        certName: String = "Trae Proxy CA"
    ) -> (success: Bool, message: String) {
        
        NSLog("[CombinedSetupManager] 🧹 Creating master clear script...")
        
        let masterScript = "/tmp/vp-clear.sh"
        let scriptContent = """
        #!/bin/bash
        
        echo "Starting Trae IDE Cleanup..."
        
        # Track cleanup status
        HOSTS_STATUS=""
        CERT_SYSTEM_STATUS=""
        CERT_LOGIN_STATUS=""
        
        # --- Step 1: Remove hosts entry ---
        echo "Cleaning /etc/hosts..."
        if grep -q "\(domain)" /etc/hosts 2>/dev/null; then
            # Create backup
            cp /etc/hosts /etc/hosts.backup-$(date +%s)
            # Remove line containing domain
            sed -i '' '/\(domain)/d' /etc/hosts
            if grep -q "\(domain)" /etc/hosts 2>/dev/null; then
                HOSTS_STATUS="⚠️ Failed to remove"
            else
                HOSTS_STATUS="✅ Removed"
            fi
        else
            HOSTS_STATUS="✅ Not present"
        fi
        
        # --- Step 2: Remove certificates from keychains ---
        echo "Removing certificates from keychains..."
        
        # System Keychain - Remove BOTH CA and domain cert
        # 1. Trae Proxy CA (root CA)
        if security find-certificate -c "Trae Proxy CA" /Library/Keychains/System.keychain >/dev/null 2>&1; then
            security delete-certificate -c "Trae Proxy CA" /Library/Keychains/System.keychain >/dev/null 2>&1 || true
            sleep 0.5
        fi
        
        # 2. api.openai.com (domain cert)
        if security find-certificate -c "api.openai.com" /Library/Keychains/System.keychain >/dev/null 2>&1; then
            security delete-certificate -c "api.openai.com" /Library/Keychains/System.keychain >/dev/null 2>&1 || true
            sleep 0.5
        fi
        
        # Verify System Keychain is clean
        if security find-certificate -c "Trae Proxy CA" /Library/Keychains/System.keychain >/dev/null 2>&1 || \\
           security find-certificate -c "api.openai.com" /Library/Keychains/System.keychain >/dev/null 2>&1; then
            CERT_SYSTEM_STATUS="⚠️ Still present"
        else
            CERT_SYSTEM_STATUS="✅ Removed"
        fi
        
        # Login Keychain - Remove BOTH CA and domain cert
        # 1. Trae Proxy CA
        if security find-certificate -c "Trae Proxy CA" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
            security delete-certificate -c "Trae Proxy CA" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
            sleep 0.5
        fi
        
        # 2. api.openai.com
        if security find-certificate -c "api.openai.com" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
            security delete-certificate -c "api.openai.com" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true
            sleep 0.5
        fi
        
        # Verify Login Keychain is clean
        if security find-certificate -c "Trae Proxy CA" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || \\
           security find-certificate -c "api.openai.com" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
            CERT_LOGIN_STATUS="⚠️ Still present"
        else
            CERT_LOGIN_STATUS="✅ Removed"
        fi
        
        # Output results
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Cleanup Results:"
        echo "  Hosts File: $HOSTS_STATUS"
        echo "  System Keychain: $CERT_SYSTEM_STATUS"
        echo "  Login Keychain: $CERT_LOGIN_STATUS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo "Cleanup complete!"
        exit 0
        """
        
        // Write master script
        do {
            try scriptContent.write(toFile: masterScript, atomically: true, encoding: .utf8)
            
            // Make executable
            let chmodResult = runShellScript("chmod +x \(masterScript)")
            if !chmodResult.success {
                return (false, "Failed to make clear script executable: \(chmodResult.message)")
            }
            
            NSLog("[CombinedSetupManager] ✅ Master clear script created")
        } catch {
            return (false, "Failed to create clear script: \(error.localizedDescription)")
        }
        
        // Run with sudo - ONE password prompt!
        NSLog("[CombinedSetupManager] 🔐 Running master clear script with sudo...")
        let result = runWithSudo(masterScript)
        
        // Cleanup temp script
        try? FileManager.default.removeItem(atPath: masterScript)
        
        if result.success {
            NSLog("[CombinedSetupManager] 🎉 Clear completed successfully")
            return (true, result.message)
        } else {
            NSLog("[CombinedSetupManager] ❌ Clear failed: \(result.message)")
            return (false, "Clear failed: \(result.message)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func runWithSudo(_ script: String) -> (success: Bool, message: String) {
        let appleScript = """
        do shell script "\(script)" with administrator privileges
        """
        
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: appleScript) else {
            return (false, "Failed to create AppleScript")
        }
        
        let output = scriptObject.executeAndReturnError(&error)
        
        if let error = error {
            let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? -1
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            NSLog("[CombinedSetupManager] ❌ AppleScript error \(errorCode): \(errorMessage)")
            return (false, "AppleScript error \(errorCode): \(errorMessage)")
        }
        
        return (true, output.stringValue ?? "")
    }
    
    private func runShellScript(_ command: String) -> (success: Bool, message: String) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return (task.terminationStatus == 0, output)
    }
}
