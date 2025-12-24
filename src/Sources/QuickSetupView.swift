import SwiftUI
import AppKit

// MARK: - Tool Detection

enum ToolStatus: Equatable {
    case notInstalled
    case installed
    case configured
}

struct DetectedTool: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    var status: ToolStatus
    var statusMessage: String
    let configInstructions: String
}

class ToolDetector: ObservableObject {
    static let shared = ToolDetector()

    @Published var tools: [DetectedTool] = []
    @Published var isScanning = false

    private let vibeProxyPort = "8317"
    private let vibeProxyPortOpenAI = "4141"

    init() {
        scan()
    }

    func scan() {
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let detectedTools = [
                self.detectClaudeCLI(),
                self.detectVSCodeCline(),
                self.detectCursor(),
                self.detectWindsurf(),
                self.detectZed()
            ]

            DispatchQueue.main.async {
                self.tools = detectedTools
                self.isScanning = false
            }
        }
    }

    // MARK: - Claude CLI Detection

    private func detectClaudeCLI() -> DetectedTool {
        var tool = DetectedTool(
            id: "claude-cli",
            name: "Claude CLI",
            icon: "terminal",
            description: "Anthropic's Claude Code CLI",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Add to ~/.zshrc:
            export ANTHROPIC_BASE_URL="http://127.0.0.1:\(vibeProxyPort)"
            export ANTHROPIC_API_KEY="dummy"
            """
        )

        // Check if claude is installed
        let whichResult = runCommand("/usr/bin/which", arguments: ["claude"])
        if whichResult.isEmpty || whichResult.contains("not found") {
            return tool
        }

        tool.status = .installed
        tool.statusMessage = "Installed, not configured"

        // Check if configured in .zshrc or .bashrc
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let zshrcPath = "\(homeDir)/.zshrc"
        let bashrcPath = "\(homeDir)/.bashrc"

        if let zshrc = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
           zshrc.contains("ANTHROPIC_BASE_URL") && zshrc.contains("127.0.0.1:\(vibeProxyPort)") {
            tool.status = .configured
            tool.statusMessage = "Configured in ~/.zshrc"
        } else if let bashrc = try? String(contentsOfFile: bashrcPath, encoding: .utf8),
                  bashrc.contains("ANTHROPIC_BASE_URL") && bashrc.contains("127.0.0.1:\(vibeProxyPort)") {
            tool.status = .configured
            tool.statusMessage = "Configured in ~/.bashrc"
        }

        return tool
    }

    // MARK: - VS Code + Cline Detection

    private func detectVSCodeCline() -> DetectedTool {
        var tool = DetectedTool(
            id: "vscode-cline",
            name: "VS Code + Cline",
            icon: "chevron.left.forwardslash.chevron.right",
            description: "Cline AI extension for VS Code",
            status: .notInstalled,
            statusMessage: "VS Code not found",
            configInstructions: """
            In Cline settings:
            • API Provider: OpenAI Compatible
            • Base URL: http://127.0.0.1:\(vibeProxyPort)/v1
            • API Key: dummy
            • Model: gpt-4
            """
        )

        // Check if VS Code is installed
        let vscodeApps = [
            "/Applications/Visual Studio Code.app",
            "/Applications/VSCodium.app",
            "/Applications/Cursor.app" // Cursor also supports Cline
        ]

        var vsCodeInstalled = false
        for app in vscodeApps {
            if FileManager.default.fileExists(atPath: app) {
                vsCodeInstalled = true
                break
            }
        }

        if !vsCodeInstalled {
            return tool
        }

        tool.status = .installed
        tool.statusMessage = "Cline extension status unknown"

        // Check VS Code settings.json for Cline config
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPaths = [
            "\(homeDir)/Library/Application Support/Code/User/settings.json",
            "\(homeDir)/Library/Application Support/VSCodium/User/settings.json"
        ]

        for settingsPath in settingsPaths {
            if let settings = try? String(contentsOfFile: settingsPath, encoding: .utf8) {
                // Check for Cline/Claude Dev configuration pointing to VibeProxy
                if (settings.contains("cline") || settings.contains("claude-dev")) &&
                   settings.contains("127.0.0.1:\(vibeProxyPort)") {
                    tool.status = .configured
                    tool.statusMessage = "Configured for VibeProxy"
                    break
                } else if settings.contains("cline") || settings.contains("claude-dev") {
                    tool.statusMessage = "Cline installed, not configured for VibeProxy"
                }
            }
        }

        return tool
    }

    // MARK: - Cursor Detection

    private func detectCursor() -> DetectedTool {
        var tool = DetectedTool(
            id: "cursor",
            name: "Cursor",
            icon: "cursorarrow",
            description: "AI-first code editor",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            In Cursor settings:
            • OpenAI API Base: http://127.0.0.1:\(vibeProxyPortOpenAI)/v1
            • API Key: dummy
            """
        )

        if FileManager.default.fileExists(atPath: "/Applications/Cursor.app") {
            tool.status = .installed
            tool.statusMessage = "Installed"

            // Check Cursor settings
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let cursorSettingsPath = "\(homeDir)/Library/Application Support/Cursor/User/settings.json"

            if let settings = try? String(contentsOfFile: cursorSettingsPath, encoding: .utf8) {
                if settings.contains("127.0.0.1:\(vibeProxyPortOpenAI)") ||
                   settings.contains("127.0.0.1:\(vibeProxyPort)") {
                    tool.status = .configured
                    tool.statusMessage = "Configured for VibeProxy"
                }
            }
        }

        return tool
    }

    // MARK: - Windsurf Detection

    private func detectWindsurf() -> DetectedTool {
        var tool = DetectedTool(
            id: "windsurf",
            name: "Windsurf",
            icon: "wind",
            description: "Codeium's AI editor",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            Windsurf uses its own AI backend.
            Manual proxy configuration may be limited.
            """
        )

        if FileManager.default.fileExists(atPath: "/Applications/Windsurf.app") {
            tool.status = .installed
            tool.statusMessage = "Installed"
        }

        return tool
    }

    // MARK: - Zed Detection

    private func detectZed() -> DetectedTool {
        var tool = DetectedTool(
            id: "zed",
            name: "Zed",
            icon: "bolt",
            description: "High-performance code editor",
            status: .notInstalled,
            statusMessage: "Not found",
            configInstructions: """
            In Zed settings.json, add:
            {
              "language_models": {
                "openai": {
                  "api_url": "http://127.0.0.1:\(vibeProxyPortOpenAI)/v1",
                  "api_key": "dummy"
                }
              }
            }
            """
        )

        if FileManager.default.fileExists(atPath: "/Applications/Zed.app") {
            tool.status = .installed
            tool.statusMessage = "Installed"

            // Check Zed settings
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let zedSettingsPath = "\(homeDir)/.config/zed/settings.json"

            if let settings = try? String(contentsOfFile: zedSettingsPath, encoding: .utf8) {
                if settings.contains("127.0.0.1:\(vibeProxyPortOpenAI)") ||
                   settings.contains("127.0.0.1:\(vibeProxyPort)") {
                    tool.status = .configured
                    tool.statusMessage = "Configured for VibeProxy"
                }
            }
        }

        return tool
    }

    // MARK: - Helper

    private func runCommand(_ command: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}

// MARK: - Setup Manager

class SetupManager {
    static let shared = SetupManager()

    private let vibeProxyPort = "8317"
    private let vibeProxyPortOpenAI = "4141"

    enum SetupResult {
        case success(String)
        case failure(String)
        case alreadyConfigured
    }

    // MARK: - Claude CLI Setup

    func setupClaudeCLI(shell: String = "zsh") -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let rcFile = shell == "zsh" ? "\(homeDir)/.zshrc" : "\(homeDir)/.bashrc"

        // Check if already configured
        if let content = try? String(contentsOfFile: rcFile, encoding: .utf8),
           content.contains("ANTHROPIC_BASE_URL") && content.contains("127.0.0.1:\(vibeProxyPort)") {
            return .alreadyConfigured
        }

        let config = """

        # VibeProxy - Claude CLI
        export ANTHROPIC_BASE_URL="http://127.0.0.1:\(vibeProxyPort)"
        export ANTHROPIC_API_KEY="dummy"
        """

        do {
            let existingContent = (try? String(contentsOfFile: rcFile, encoding: .utf8)) ?? ""
            try (existingContent + config).write(toFile: rcFile, atomically: true, encoding: .utf8)
            return .success("Added to ~/.\(shell)rc. Restart terminal to apply.")
        } catch {
            return .failure("Failed to write to ~/.\(shell)rc: \(error.localizedDescription)")
        }
    }

    // MARK: - VS Code / Cline Setup

    func setupCline() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(homeDir)/Library/Application Support/Code/User/settings.json"

        // Ensure directory exists
        let settingsDir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]

        // Read existing settings
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Check if already configured
        if let baseUrl = settings["cline.openaiBaseUrl"] as? String,
           baseUrl.contains("127.0.0.1:\(vibeProxyPort)") {
            return .alreadyConfigured
        }

        // Add Cline settings
        settings["cline.apiProvider"] = "openai"
        settings["cline.openaiBaseUrl"] = "http://127.0.0.1:\(vibeProxyPort)/v1"
        settings["cline.openaiApiKey"] = "dummy"
        settings["cline.openaiModelId"] = "gpt-4"

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: settingsPath))
            return .success("Cline configured. Restart VS Code to apply.")
        } catch {
            return .failure("Failed to update VS Code settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Zed Setup

    func setupZed() -> SetupResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let settingsPath = "\(homeDir)/.config/zed/settings.json"

        // Ensure directory exists
        let settingsDir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]

        // Read existing settings
        if let data = FileManager.default.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Check if already configured
        if let languageModels = settings["language_models"] as? [String: Any],
           let openai = languageModels["openai"] as? [String: Any],
           let apiUrl = openai["api_url"] as? String,
           apiUrl.contains("127.0.0.1") {
            return .alreadyConfigured
        }

        // Add language models config
        var languageModels = settings["language_models"] as? [String: Any] ?? [:]
        languageModels["openai"] = [
            "api_url": "http://127.0.0.1:\(vibeProxyPortOpenAI)/v1",
            "api_key": "dummy"
        ]
        settings["language_models"] = languageModels

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: settingsPath))
            return .success("Zed configured. Restart Zed to apply.")
        } catch {
            return .failure("Failed to update Zed settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Copy to Clipboard

    func copyConfig(for toolId: String) {
        let config: String

        switch toolId {
        case "claude-cli":
            config = """
            # Add to ~/.zshrc or ~/.bashrc
            export ANTHROPIC_BASE_URL="http://127.0.0.1:\(vibeProxyPort)"
            export ANTHROPIC_API_KEY="dummy"
            """
        case "vscode-cline":
            config = """
            Cline Settings:
            • API Provider: OpenAI Compatible
            • Base URL: http://127.0.0.1:\(vibeProxyPort)/v1
            • API Key: dummy
            • Model: gpt-4
            """
        case "cursor":
            config = """
            Cursor Settings:
            • OpenAI API Base: http://127.0.0.1:\(vibeProxyPortOpenAI)/v1
            • API Key: dummy
            """
        case "zed":
            config = """
            Add to ~/.config/zed/settings.json:
            {
              "language_models": {
                "openai": {
                  "api_url": "http://127.0.0.1:\(vibeProxyPortOpenAI)/v1",
                  "api_key": "dummy"
                }
              }
            }
            """
        default:
            config = "No configuration available"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
}

// MARK: - Quick Setup View

struct QuickSetupView: View {
    @StateObject private var detector = ToolDetector.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingSetupAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Detected Tools")
                    .font(.headline)
                Spacer()
                Button(action: { detector.scan() }) {
                    HStack(spacing: 4) {
                        if detector.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Scan")
                    }
                }
                .controlSize(.small)
                .disabled(detector.isScanning)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Tools List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(detector.tools) { tool in
                        ToolRow(
                            tool: tool,
                            onSetup: { setupTool(tool) },
                            onCopy: { copyConfig(tool) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider()
                .padding(.top, 12)

            // Setup All Button
            VStack(spacing: 8) {
                let configurableTools = detector.tools.filter {
                    $0.status == .installed && canAutoSetup($0.id)
                }

                if !configurableTools.isEmpty {
                    Button(action: { showingSetupAllConfirm = true }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Setup All Detected Tools (\(configurableTools.count))")
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }

                Text("VibeProxy endpoints: :8317 (Anthropic) | :4141 (OpenAI)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Setup All Tools", isPresented: $showingSetupAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Setup All") { setupAllTools() }
        } message: {
            let tools = detector.tools.filter { $0.status == .installed && canAutoSetup($0.id) }
            Text("This will configure the following tools:\n\n\(tools.map { "• \($0.name)" }.joined(separator: "\n"))\n\nContinue?")
        }
    }

    private func canAutoSetup(_ toolId: String) -> Bool {
        ["claude-cli", "vscode-cline", "zed"].contains(toolId)
    }

    private func setupTool(_ tool: DetectedTool) {
        let result: SetupManager.SetupResult

        switch tool.id {
        case "claude-cli":
            result = SetupManager.shared.setupClaudeCLI()
        case "vscode-cline":
            result = SetupManager.shared.setupCline()
        case "zed":
            result = SetupManager.shared.setupZed()
        default:
            // Copy config for tools without auto-setup
            copyConfig(tool)
            return
        }

        switch result {
        case .success(let message):
            alertTitle = "Setup Complete"
            alertMessage = message
            detector.scan() // Refresh status
        case .failure(let error):
            alertTitle = "Setup Failed"
            alertMessage = error
        case .alreadyConfigured:
            alertTitle = "Already Configured"
            alertMessage = "\(tool.name) is already configured for VibeProxy."
        }
        showingAlert = true
    }

    private func copyConfig(_ tool: DetectedTool) {
        SetupManager.shared.copyConfig(for: tool.id)
        alertTitle = "Copied!"
        alertMessage = "Configuration for \(tool.name) copied to clipboard."
        showingAlert = true
    }

    private func setupAllTools() {
        var results: [String] = []

        for tool in detector.tools where tool.status == .installed && canAutoSetup(tool.id) {
            let result: SetupManager.SetupResult

            switch tool.id {
            case "claude-cli":
                result = SetupManager.shared.setupClaudeCLI()
            case "vscode-cline":
                result = SetupManager.shared.setupCline()
            case "zed":
                result = SetupManager.shared.setupZed()
            default:
                continue
            }

            switch result {
            case .success:
                results.append("✅ \(tool.name)")
            case .failure(let error):
                results.append("❌ \(tool.name): \(error)")
            case .alreadyConfigured:
                results.append("✓ \(tool.name) (already configured)")
            }
        }

        detector.scan() // Refresh status

        alertTitle = "Setup Complete"
        alertMessage = results.joined(separator: "\n") + "\n\nRestart the apps to apply changes."
        showingAlert = true
    }
}

// MARK: - Tool Row

struct ToolRow: View {
    let tool: DetectedTool
    let onSetup: () -> Void
    let onCopy: () -> Void

    @State private var isExpanded = false

    private var statusColor: Color {
        switch tool.status {
        case .notInstalled: return .gray
        case .installed: return .orange
        case .configured: return .green
        }
    }

    private var statusIcon: String {
        switch tool.status {
        case .notInstalled: return "xmark.circle"
        case .installed: return "exclamationmark.circle"
        case .configured: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: tool.icon)
                    .frame(width: 24)
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .fontWeight(.medium)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                    Text(tool.status == .notInstalled ? "Not Found" :
                         tool.status == .installed ? "Not Configured" : "Configured")
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
            }

            // Status message
            if tool.status != .notInstalled {
                HStack(spacing: 4) {
                    Text(tool.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Expand button for instructions
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 28)
            }

            // Expanded instructions
            if isExpanded && tool.status != .notInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tool.configInstructions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)

                    HStack(spacing: 8) {
                        if tool.status == .installed && canAutoSetup(tool.id) {
                            Button("Auto Setup") {
                                onSetup()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                        }

                        Button("Copy Config") {
                            onCopy()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func canAutoSetup(_ toolId: String) -> Bool {
        ["claude-cli", "vscode-cline", "zed"].contains(toolId)
    }
}

#Preview {
    QuickSetupView()
        .frame(width: 520, height: 600)
}
