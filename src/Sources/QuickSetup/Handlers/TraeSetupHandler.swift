import Foundation
import AppKit

// MARK: - Trae IDE Setup Handler

class TraeSetupHandler: ToolSetupHandler {
    let toolId = "trae-ide"
    let toolName = "Trae IDE"
    
    private let domain = "api.openai.com"
    private let localIP = "127.0.0.1"
    
    func detect() -> DetectedTool {
        var tool = DetectedTool(
            id: toolId,
            name: toolName,
            icon: "laptopcomputer",
            description: "Trae AI IDE with OpenAI API proxy support",
            status: .notInstalled,
            statusMessage: "Not configured",
            configInstructions: """
            Trae IDE Setup Instructions:
            
            1. Click "Auto Setup" to configure the MITM proxy
            2. Install the generated certificate (instructions will be shown)
            3. Add a model in Trae:
               - Provider: OpenAI
               - Model ID: gpt-4o
               - API Key: vp-dummy-key
            
            ⚠️ This setup modifies /etc/hosts and requires certificate installation.
            """
        )
        
        // Check if Trae is installed
        let traeApplications = [
            "/Applications/Trae.app",
            "\(AppConfig.Paths.homeDir)/Applications/Trae.app"
        ]
        
        let traeInstalled = traeApplications.contains { FileManager.default.fileExists(atPath: $0) }
        
        if !traeInstalled {
            tool.status = .notInstalled
            tool.statusMessage = "Trae IDE not found"
            return tool
        }
        
        tool.status = .installed
        tool.statusMessage = "Installed, not configured"
        
        // Check if MITM proxy is configured
        let hostsConfigured = HostsFileManager.shared.hasEntry(domain: domain)
        let certExists = CertificateManager.shared.certificateExists()
        
        if hostsConfigured && certExists {
            tool.status = .configured
            tool.statusMessage = "MITM proxy configured (hosts file + certificate)"
        } else if hostsConfigured {
            tool.status = .installed
            tool.statusMessage = "Hosts file configured, certificate missing"
        } else if certExists {
            tool.status = .installed
            tool.statusMessage = "Certificate exists, hosts file not configured"
        }
        
        return tool
    }
    
    func setup() -> SetupManager.SetupResult {
        NSLog("[TraeSetupHandler] 🚀 Starting Trae IDE MITM proxy setup")
        
        var messages: [String] = []
        var success = true
        
        // Step 1: Generate SSL certificate (no sudo needed)
        let certResult = CertificateManager.shared.generateSelfSignedCertificate()
        messages.append("📜 Certificate: \(certResult.message)")
        
        if !certResult.success {
            success = false
            return .failure(messages.joined(separator: "\n"))
        }
        
        // Step 2: Run COMBINED setup - hosts + proxy + trust (ONE sudo!)
        NSLog("[TraeSetupHandler] 🔐 Running combined setup...")
        
        let certPath = CertificateManager.shared.getCertificatePath()
        let traeProxyDir = TraeProxyManager.shared.proxyDirectory
        let pidFile = TraeProxyManager.shared.pidFile
        
        let setupResult = CombinedSetupManager.shared.runAutoSetup(
            domain: domain,
            localIP: localIP,
            certPath: certPath,
            traeProxyDir: traeProxyDir,
            pidFile: pidFile
        )
        
        if setupResult.success {
            messages.append("\n🎉 Setup complete! (Only 1 password!)")
            messages.append("   ✅ Certificate generated and trusted")
            messages.append("   ✅ Hosts file configured")
            messages.append("   ✅ Trae-Proxy running on port 443")
            messages.append("\n⚠️  Note: This setup used temporary security modification")
            messages.append("   (authorizationdb) to automate certificate trust.")
            messages.append("\n🚀 Ready to use Trae IDE:")
            messages.append("   - Provider: OpenAI")
            messages.append("   - Model: gpt-4o")
            messages.append("   - API Key: your real API key")
        } else {
            messages.append("\n❌ Setup failed: \(setupResult.message)")
            success = false
        }
        
        return success 
            ? .success(messages.joined(separator: "\n"))
            : .failure(messages.joined(separator: "\n"))
    }
    
    
    func clear() -> SetupManager.SetupResult {
        NSLog("[TraeSetupHandler] 🧹 Clearing Trae IDE MITM proxy setup")
        
        var messages: [String] = []
        var success = true
        
        // Step 1: Stop Trae-Proxy subprocess
        let proxyResult = TraeProxyManager.shared.stop()
        messages.append("🛑 Trae-Proxy: \(proxyResult.message)")
        
        if !proxyResult.success {
            success = false
        }
        
        // Step 2 & 3: Remove hosts + certificates with SINGLE password prompt
        NSLog("[TraeSetupHandler] 🔐 Running consolidated clear script...")
        let cleanupResult = CombinedSetupManager.shared.executeClearScript(domain: domain)
        
        if cleanupResult.success {
            messages.append("✅ Cleanup completed successfully")
            messages.append(cleanupResult.message)
        } else {
            messages.append("❌ Cleanup encountered issues:")
            messages.append(cleanupResult.message)
            success = false
        }
        
        return success 
            ? .success(messages.joined(separator: "\n"))
            : .failure(messages.joined(separator: "\n"))
    }
    
    func copyConfig() -> String {
        let crtPath = CertificateManager.shared.getCertificatePath()
        
        return """
        # Trae IDE Configuration
        
        ## Step 1: Install Certificate
        1. Open: \(crtPath)
        2. Add to System Keychain
        3. Trust for SSL
        
        ## Step 2: Verify Hosts File
        Entry should exist in /etc/hosts:
        \(localIP) \(domain)
        
        ## Step 3: Configure Trae
        Add model with:
        - Provider: OpenAI
        - Model: gpt-4o
        - API Key: vp-dummy-key
        
        ## Test Connection
        curl https://api.openai.com/v1/models
        """
    }
}
