import SwiftUI
import AppKit

// QuickSetupView - Modular Version
// Core models and detection logic are in QuickSetup/ subdirectory

// MARK: - Quick Setup View

struct QuickSetupView: View {
    @StateObject private var detector = ToolDetector.shared
    @State private var expandedTool: String? = nil
    @State private var setupResult: (toolId: String, message: String, isError: Bool)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Quick Setup")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { detector.scan() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(detector.isScanning)

                Button(action: setupAllTools) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Setup All")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(detector.isScanning)
            }
            .padding()

            Divider()

            // Tools List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(detector.tools) { tool in
                        ToolRow(
                            tool: tool,
                            isExpanded: expandedTool == tool.id,
                            onToggle: {
                                withAnimation {
                                    expandedTool = expandedTool == tool.id ? nil : tool.id
                                }
                            },
                            onSetup: { setupTool(tool.id) },
                            onClear: { clearTool(tool.id) },
                            onCopyConfig: { SetupManager.shared.copyConfig(for: tool.id) }
                        )
                        Divider()
                    }
                }
            }

            // Result Banner
            if let result = setupResult {
                Divider()
                HStack {
                    Image(systemName: result.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(result.isError ? .red : .green)
                    Text(result.message)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Button("Dismiss") {
                        setupResult = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(result.isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
            }
        }
    }

    private func setupTool(_ toolId: String) {
        let result: SetupManager.SetupResult

        switch toolId {
        case "claude-cli":
            result = SetupManager.shared.setupClaudeCLI()
        case "vscode-cline":
            result = SetupManager.shared.setupCline()
        case "zed":
            result = SetupManager.shared.setupZed()
        case "droid-cli":
            result = SetupManager.shared.setupDroid()
        case "opencode-cli":
            result = SetupManager.shared.setupOpencodeCLI()
        case "trae-ide":
            let handler = TraeSetupHandler()
            result = handler.setup()
        default:
            setupResult = (toolId, "Setup not implemented for this tool", true)
            return
        }

        handleResult(result, for: toolId)
        detector.scan()
    }

    private func clearTool(_ toolId: String) {
        let result: SetupManager.SetupResult

        switch toolId {
        case "claude-cli":
            result = SetupManager.shared.clearClaudeCLI()
        case "vscode-cline":
            result = SetupManager.shared.clearCline()
        case "zed":
            result = SetupManager.shared.clearZed()
        case "droid-cli":
            result = SetupManager.shared.clearDroid()
        case "opencode-cli":
            result = SetupManager.shared.clearOpencodeCLI()
        case "trae-ide":
            let handler = TraeSetupHandler()
            result = handler.clear()
        default:
            setupResult = (toolId, "Clear not implemented for this tool", true)
            return
        }

        handleResult(result, for: toolId)
        detector.scan()
    }

    private func setupAllTools() {
        var results: [String] = []
        
        for tool in detector.tools where tool.status != .notInstalled {
            let result: SetupManager.SetupResult
            switch tool.id {
            case "claude-cli":
                result = SetupManager.shared.setupClaudeCLI()
            case "vscode-cline":
                result = SetupManager.shared.setupCline()
            case "zed":
                result = SetupManager.shared.setupZed()
            case "droid-cli":
                result = SetupManager.shared.setupDroid()
            case "opencode-cli":
                result = SetupManager.shared.setupOpencodeCLI()
            default:
                continue
            }
            
            switch result {
            case .success(let msg):
                results.append("✓ \(tool.name): \(msg)")
            case .alreadyConfigured:
                results.append("→ \(tool.name): Already configured")
            case .failure(let error):
                results.append("✗ \(tool.name): \(error)")
            }
        }
        
        setupResult = (
            "all",
            results.isEmpty ? "No tools to setup" : results.joined(separator: "\n"),
            false
        )
        detector.scan()
    }

    private func handleResult(_ result: SetupManager.SetupResult, for toolId: String) {
        switch result {
        case .success(let message):
            setupResult = (toolId, message, false)
        case .alreadyConfigured:
            setupResult = (toolId, "Already configured", false)
        case .failure(let error):
            setupResult = (toolId, error, true)
        }
    }
}

// MARK: - Tool Row

struct ToolRow: View {
    let tool: DetectedTool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSetup: () -> Void
    let onClear: () -> Void
    let onCopyConfig: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: tool.icon)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.name)
                            .font(.headline)
                        Text(tool.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    StatusBadge(status: tool.status, message: tool.statusMessage)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Expanded Detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tool.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if tool.status != .notInstalled {
                        HStack(spacing: 8) {
                            if canAutoSetup(tool.id) {
                                if tool.status == .configured {
                                    Button(action: onClear) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                            Text("Clear Setup")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button(action: onSetup) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "wand.and.stars")
                                            Text("Auto Setup")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            Button(action: onCopyConfig) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy Config")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Configuration Instructions:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Text(tool.configInstructions)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(4)
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
    }

    private func canAutoSetup(_ toolId: String) -> Bool {
        ["claude-cli", "vscode-cline", "zed", "droid-cli", "opencode-cli", "trae-ide"].contains(toolId)
    }
}

// MARK: -Status Badge

struct StatusBadge: View {
    let status: ToolStatus
    let message: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var statusColor: Color {
        switch status {
        case .notInstalled:
            return .gray
        case .installed:
            return .orange
        case .configured:
            return .green
        }
    }
}

// MARK: - Preview

struct QuickSetupView_Previews: PreviewProvider {
    static var previews: some View {
        QuickSetupView()
            .frame(width: 600, height: 500)
    }
}
