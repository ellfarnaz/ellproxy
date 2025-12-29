import SwiftUI
import UserNotifications

// MARK: - Model Search Window

enum ModelSelectionMode {
    case defaultModel
    case thinkingModel
}

struct ModelSearchWindowView: View {
    @State private var searchText = ""
    @State private var mode: ModelSelectionMode  // Changed to @State for switching
    @ObservedObject private var modelRouter = ModelRouter.shared
    
    init(mode: ModelSelectionMode = .defaultModel) {
        _mode = State(initialValue: mode)
    }
    
    private var filteredModelsByProvider: [String: [ModelConfig]] {
        var baseModels = modelRouter.modelsByProvider
        
        // Filter by mode first
        if mode == .thinkingModel {
            // Only show thinking-capable models
            baseModels = Dictionary(grouping: modelRouter.thinkingModels, by: { $0.provider })
        }
        
        // Then filter by search text
        guard !searchText.isEmpty else {
            return baseModels
        }
        
        let searchLower = searchText.lowercased()
        var filtered: [String: [ModelConfig]] = [:]
        
        for (provider, models) in baseModels {
            let matchingModels = models.filter { model in
                model.name.lowercased().contains(searchLower) ||
                model.id.lowercased().contains(searchLower) ||
                provider.lowercased().contains(searchLower)
            }
            
            if !matchingModels.isEmpty {
                filtered[provider] = matchingModels
            }
        }
        
        return filtered
    }
    
    private var filteredProviders: [String] {
        let order = ["antigravity", "google", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        return order.filter { filteredModelsByProvider[$0] != nil }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ModeSelector(mode: $mode)
            Divider()
            
            // Search bar with Update button
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField(mode == .thinkingModel ? "Search thinking models..." : "Search models...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                
                // Update button (always visible at top)
                Button(action: {
                    // Update menu bar before closing
                    NotificationCenter.default.post(name: NSNotification.Name("UpdateMenuBar"), object: nil)
                    NSApp.keyWindow?.close()
                }) {
                    Text("Update")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Model list with Recent section
            ModelList(filteredProviders: filteredProviders, filteredModelsByProvider: filteredModelsByProvider, mode: mode)
        }
        .frame(width: 450)
    }
}

struct ModeSelector: View {
    @Binding var mode: ModelSelectionMode
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: { mode = .defaultModel }) {
                    VStack(spacing: 4) {
                        Text("⚡ Default Model")
                            .font(.system(size: 13, weight: mode == .defaultModel ? .semibold : .regular))
                            .foregroundColor(mode == .defaultModel ? .accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(mode == .defaultModel ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 30)
                
                Button(action: { mode = .thinkingModel }) {
                    VStack(spacing: 4) {
                        Text("🧠 Thinking Model")
                            .font(.system(size: 13, weight: mode == .thinkingModel ? .semibold : .regular))
                            .foregroundColor(mode == .thinkingModel ? .accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(mode == .thinkingModel ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ModelList: View {
    let filteredProviders: [String]
    let filteredModelsByProvider: [String: [ModelConfig]]
    var mode: ModelSelectionMode = .defaultModel
    @ObservedObject private var modelRouter = ModelRouter.shared
    @State private var collapsedProviders: Set<String> = []
    @State private var isInitialized = false
    
    // Initialize collapsed state based on active model
    private func initializeCollapsedState() {
        guard !isInitialized else { return }
        isInitialized = true
        
        // Collapse all providers initially
        collapsedProviders = Set(filteredProviders)
        
        // Auto-expand provider with active model
        let activeModelId = mode == .defaultModel ? modelRouter.activeModelId : modelRouter.defaultThinkingModelId
        
        if !activeModelId.isEmpty,
           let activeModel = modelRouter.findModel(byKey: activeModelId) {
            collapsedProviders.remove(activeModel.provider)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Recent Models Section (always at top)
                if !modelRouter.recentModels.isEmpty {
                    RecentModelsSection(mode: mode)
                    
                    // Separator
                    HStack {
                        Text("All Providers")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.separatorColor).opacity(0.2))
                }
                
                // None option (Only for Thinking Mode)
                if mode == .thinkingModel {
                    Button(action: {
                        modelRouter.defaultThinkingModelId = ""
                        NotificationCenter.default.post(name: NSNotification.Name("UpdateMenuBar"), object: nil)
                    }) {
                        HStack(spacing: 8) {
                            if modelRouter.defaultThinkingModelId.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                            Text("None (Disable Thinking Default)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(modelRouter.defaultThinkingModelId.isEmpty ? Color.accentColor.opacity(0.1) : Color.clear)
                    
                    Divider()
                }
                
                // All Providers (collapsible)
                ForEach(filteredProviders, id: \.self) { provider in
                    ProviderGroup(
                        provider: provider,
                        models: filteredModelsByProvider[provider] ?? [],
                        mode: mode,
                        isCollapsed: collapsedProviders.contains(provider),
                        toggleCollapse: {
                            if collapsedProviders.contains(provider) {
                                collapsedProviders.remove(provider)
                            } else {
                                collapsedProviders.insert(provider)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
            .onAppear {
                initializeCollapsedState()
            }
        }
        .frame(maxHeight: 400)
    }
}

// Recent Models Section
struct RecentModelsSection: View {
    var mode: ModelSelectionMode = .defaultModel
    @ObservedObject private var modelRouter = ModelRouter.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header (always expanded)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("Recent Models")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(modelRouter.recentModels.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Recent models (always visible)
            ForEach(modelRouter.recentModels) { model in
                ModelRowForSearch(model: model, mode: mode)
            }
        }
        .padding(.bottom, 8)
    }
}

struct ProviderGroup: View {
    let provider: String
    let models: [ModelConfig]
    var mode: ModelSelectionMode = .defaultModel
    let isCollapsed: Bool
    let toggleCollapse: () -> Void
    @ObservedObject private var modelRouter = ModelRouter.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Collapsible header
            Button(action: toggleCollapse) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    if let icon = IconCatalog.shared.image(named: modelRouter.providerIconName(provider), resizedTo: NSSize(width: 16, height: 16), template: true) {
                        Image(nsImage: icon)
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 16, height: 16)
                    }
                    
                    Text(modelRouter.providerDisplayName(provider))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(models.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Models (only show if not collapsed)
            if !isCollapsed {
                ForEach(models) { model in
                    ModelRowForSearch(model: model, mode: mode)
                }
            }
        }
        .padding(.bottom, 8)
    }
}


struct ModelRowForSearch: View {
    let model: ModelConfig
    var mode: ModelSelectionMode = .defaultModel
    @ObservedObject private var modelRouter = ModelRouter.shared
    
    var body: some View {
        Button(action: selectModel) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
                Text(model.name)
                    .font(.system(size: 13))
                if model.supportsThinking {
                    Text("🧠")
                        .font(.system(size: 11))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
    
    private var isSelected: Bool {
        let modelKey = ModelRouter.uniqueKey(for: model)
        switch mode {
        case .defaultModel:
            return modelKey == modelRouter.activeModelId
        case .thinkingModel:
            return modelKey == modelRouter.defaultThinkingModelId
        }
    }
    
    private func selectModel() {
        let modelKey = ModelRouter.uniqueKey(for: model)
        switch mode {
        case .defaultModel:
            modelRouter.activeModelId = modelKey
            // modelRouter.routingEnabled = true - REMOVED: User requests should not auto-enable routing
            modelRouter.addToRecentModels(modelKey)
            
            let content = UNMutableNotificationContent()
            content.title = "Model Selected"
            content.body = model.name
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
            
        case .thinkingModel:
            modelRouter.defaultThinkingModelId = modelKey
            modelRouter.addToRecentModels(modelKey)
            
            let content = UNMutableNotificationContent()
            content.title = "Thinking Model Selected"
            content.body = model.name
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
        
        // Notify menu bar to update
        NotificationCenter.default.post(name: NSNotification.Name("UpdateMenuBar"), object: nil)
        
        // Don't close window - let user click Done button instead
    }
}
