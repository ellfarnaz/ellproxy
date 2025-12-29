import SwiftUI

/// View for managing model routing configuration
struct ModelsView: View {
    @ObservedObject private var modelRouter = ModelRouter.shared
    @State private var expandedProviders: Set<String> = []
    @State private var copiedModel: String? = nil
    @State private var showingAddModel = false
    @State private var showingFallbackPicker = false
    @State private var showingDefaultThinkingPicker = false
    @State private var showingFallbackThinkingPicker = false

    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                // Routing Toggle Section
                Section {
                    Toggle("Enable Model Routing", isOn: $modelRouter.routingEnabled)
                        .help("ON = Smart Routing (follows guides), OFF = Force Default (Panic Mode)")
                    
                    Toggle("Notify on Routing", isOn: $modelRouter.notifyOnRouting)
                        .help("Show notifications when models are routed or fallback occurs")
                } header: {
                    Text("Model Routing")
                }
                
                // ⚡ Fast Track Section
                Section {
                    HStack {
                        Text("Default Model")
                        Spacer()
                        if let activeModel = modelRouter.activeModel {
                            Text(activeModel.name)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not set")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Fallback Model")
                        Spacer()
                        Button(action: { showingFallbackPicker = true }) {
                            HStack(spacing: 4) {
                                if let fallback = modelRouter.fallbackModel {
                                    Text(fallback.name)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("None")
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 100, alignment: .trailing)
                        .popover(isPresented: $showingFallbackPicker, arrowEdge: .bottom) {
                            FallbackModelPickerPopover()
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("Fast Track (Non-Thinking Requests)")
                    }
                } footer: {
                    Text("Used for standard requests without thinking parameters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 🧠 Thinking Track Section
                Section {
                    HStack {
                        Text("Default Thinking")
                        Spacer()
                        Button(action: { showingDefaultThinkingPicker = true }) {
                            HStack(spacing: 4) {
                                if let defaultThinking = modelRouter.defaultThinkingModel {
                                    Text(defaultThinking.name)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Not set")
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 100, alignment: .trailing)
                        .popover(isPresented: $showingDefaultThinkingPicker, arrowEdge: .bottom) {
                            ThinkingModelPickerPopover(
                                selectedModelId: $modelRouter.defaultThinkingModelId,
                                title: "Default Thinking Model"
                            )
                        }
                    }
                    
                    HStack {
                        Text("Fallback Thinking")
                        Spacer()
                        Button(action: { showingFallbackThinkingPicker = true }) {
                            HStack(spacing: 4) {
                                if let fallbackThinking = modelRouter.fallbackThinkingModel {
                                    Text(fallbackThinking.name)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("None")
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 100, alignment: .trailing)
                        .popover(isPresented: $showingFallbackThinkingPicker, arrowEdge: .bottom) {
                            ThinkingModelPickerPopover(
                                selectedModelId: $modelRouter.fallbackThinkingModelId,
                                title: "Fallback Thinking Model"
                            )
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "brain.fill")
                            .foregroundColor(.pink)
                        Text("Thinking Track (Thinking Requests)")
                    }
                } footer: {
                    Text("Used when requests include 'thinking' parameters. Only thinking-capable models are shown.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 🎛️ Reasoning Effort Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $modelRouter.reasoningLevel) {
                            Text("⚡ Low").tag("low")
                            Text("⚖️ Medium").tag("medium")
                            Text("🔥 High").tag("high")
                        }
                        .pickerStyle(.segmented)
                        
                        // Description based on selected level
                        Group {
                            switch modelRouter.reasoningLevel {
                            case "low":
                                Text("Fast & efficient - Minimal reasoning depth for simple tasks")
                            case "high":
                                Text("Maximum reasoning - Deep analysis for complex problems (slower)")
                            default:
                                Text("Balanced - Good reasoning quality with reasonable speed")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } header: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                        Text("Reasoning Effort")
                    }
                } footer: {
                    Text("Controls thinking depth for Gemini (native API) and other models (via token budget). Changes apply to all future requests.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Models List by Provider
                Section {
                    ForEach(modelRouter.providers, id: \.self) { provider in
                            ProviderSection(
                                provider: provider,
                                models: modelRouter.modelsByProvider[provider] ?? [],
                                isExpanded: expandedProviders.contains(provider),
                                activeModelId: modelRouter.activeModelId,
                                copiedModel: copiedModel,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedProviders.contains(provider) {
                                            expandedProviders.remove(provider)
                                        } else {
                                            expandedProviders.insert(provider)
                                        }
                                    }
                                },
                                onSelectModel: { model in
                                    modelRouter.activeModelId = ModelRouter.uniqueKey(for: model)
                                },
                                onCopyModel: { model in
                                    copyModelToClipboard(model)
                                },
                                onDeleteModel: { model in
                                    do {
                                        try ModelRouter.shared.deleteModel(model)
                                    } catch {
                                        NSLog("[ModelsView] Failed to delete model: %@", error.localizedDescription)
                                    }
                                }
                            )
                    }
                } header: {
                    HStack {
                        Text("Available Models")
                        
                        Spacer()
                        Button(action: { showingAddModel = true }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Add custom model")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            // Expand provider of active model by default
            if let activeModel = modelRouter.activeModel {
                expandedProviders.insert(activeModel.provider)
            }
        }
        .sheet(isPresented: $showingAddModel) {
            AddModelView()
        }
    }
    
    private func copyModelToClipboard(_ model: ModelConfig) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.id, forType: .string)
        
        withAnimation {
            copiedModel = model.id
        }
        
        // Reset copied state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedModel == model.id {
                    copiedModel = nil
                }
            }
        }
    }
}

/// A collapsible section showing models for a provider
struct ProviderSection: View {
    let provider: String
    let models: [ModelConfig]
    let isExpanded: Bool
    let activeModelId: String
    let copiedModel: String?
    let onToggleExpand: () -> Void
    let onSelectModel: (ModelConfig) -> Void
    let onCopyModel: (ModelConfig) -> Void
    let onDeleteModel: (ModelConfig) -> Void
    
    private var modelRouter: ModelRouter { ModelRouter.shared }
    
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var syncSuccess: Int?
    @ObservedObject private var syncService = ModelSyncService.shared
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Provider Header
            HStack {
                // LEFT: Provider Icon & Name (Clickable for Expand)
                HStack {
                    if let icon = IconCatalog.shared.image(named: modelRouter.providerIconName(provider), resizedTo: NSSize(width: 18, height: 18), template: true) {
                        Image(nsImage: icon)
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 18, height: 18)
                    }
                    Text(modelRouter.providerDisplayName(provider))
                        .fontWeight(.medium)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleExpand()
                }
                
                Spacer()
                
                // RIGHT: Sync Button & Expand Info
                HStack(spacing: 12) {
                    // Sync button (Custom Tap Gesture to avoid List/Form eating clicks)
                    Group {
                        if isSyncing {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(360))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSyncing)
                        } else if let count = syncSuccess {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                Text("+\(count)")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.green)
                            .transition(.opacity)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundColor(.accentColor)
                    .contentShape(Rectangle()) // Hit testable area
                    .onTapGesture {
                        guard !isSyncing else { return }
                        NSLog("[ProviderSection] Sync tapped (gesture) for %@", provider)
                        syncModels()
                    }
                    .help("Sync new models from API")
                    
                    // Model Count & Chevron (Clickable for Expand)
                    HStack(spacing: 4) {
                        Text("\(models.count) models")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onToggleExpand()
                    }
                }
            }
            
            // Sync progress indicator
            if let progress = syncService.syncProgress, progress.provider == provider {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text(progress.status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if progress.total > 0 {
                        Text("(\(progress.current)/\(progress.total))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 26)
            }
            
            // Sync error message
            if let error = syncError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.leading, 26)
            }
            
            // Models List
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(models) { model in
                        ModelRow(
                            model: model,
                            isActive: ModelRouter.uniqueKey(for: model) == activeModelId,
                            isCopied: copiedModel == model.id,
                            onSelect: { onSelectModel(model) },
                            onCopy: { onCopyModel(model) },
                            onDelete: { onDeleteModel(model) }
                        )
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    /// Perform model sync for this provider
    private func syncModels() {
        NSLog("[ProviderSection] syncModels() called for provider: %@", provider)
        
        NSLog("[ProviderSection] Starting sync")
        
        isSyncing = true
        syncError = nil
        syncSuccess = nil
        
        Task {
            do {
                let result = try await ModelSyncService.shared.syncProvider(provider)
                
                // CRITICAL: Reload models from disk after sync updates the JSON files
                ModelRouter.shared.loadModels()
                
                await MainActor.run {
                    isSyncing = false
                    if result.newModels.isEmpty {
                        syncSuccess = 0
                    } else {
                        syncSuccess = result.newModels.count
                    }
                    
                    // Clear success indicator after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        syncSuccess = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncError = error.localizedDescription
                    
                     // Clear error after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        syncError = nil
                    }
                }
            }
        }
    }
}

/// A single model row with selection, copy, and delete buttons
struct ModelRow: View {
    let model: ModelConfig
    let isActive: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Selection indicator
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .accentColor : .secondary)
                .font(.system(size: 12))
            
            // Model name
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .primary : .secondary)
                
                // Thinking Toggle
                Button(action: {
                    ModelRouter.shared.updateModelThinking(model: model, supportsThinking: !model.supportsThinking)
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: model.supportsThinking ? "brain.head.profile" : "brain")
                            .font(.system(size: 10))
                        Text(model.supportsThinking ? "Thinking ON" : "Thinking OFF")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(model.supportsThinking ? .orange : .secondary.opacity(0.7))
                    .padding(.vertical, 1)
                    .padding(.horizontal, 4)
                    .background(model.supportsThinking ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Click to toggle Thinking capability for this model")
            }
            
            Spacer()
            
            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 2) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(isCopied ? "Copied!" : "Copy")
                        .font(.system(size: 10))
                }
                .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            
            // Delete button
            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete model")
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .alert("Delete Model", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(model.name)'? This action cannot be undone.")
        }
    }
}

// MARK: - Default Model Picker
struct DefaultModelPickerView: View {
    @Binding var selectedModelId: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    private var modelRouter: ModelRouter { ModelRouter.shared }
    
    /// Filtered models based on search text
    private var filteredModelsByProvider: [String: [ModelConfig]] {
        guard !searchText.isEmpty else {
            return modelRouter.modelsByProvider
        }
        
        let searchLower = searchText.lowercased()
        var filtered: [String: [ModelConfig]] = [:]
        
        for (provider, models) in modelRouter.modelsByProvider {
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
        NavigationStack {
            List {
                ForEach(filteredProviders, id: \.self) { provider in
                    Section(modelRouter.providerDisplayName(provider)) {
                        ForEach(filteredModelsByProvider[provider] ?? []) { model in
                            Button(action: {
                                selectedModelId = model.id
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    if model.id == selectedModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                            .font(.caption)
                                    }
                                    Text(model.name)
                                        .font(.system(size: 13))
                                    if model.supportsThinking {
                                        Text("⚡")
                                            .font(.caption)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search models...")
            .navigationTitle("Select Default Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
    }
}

// MARK: - Fallback Model Picker
struct FallbackModelPickerView: View {
    @Binding var selectedModelId: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    private var modelRouter: ModelRouter { ModelRouter.shared }
    
    /// Filtered models based on search text
    private var filteredModelsByProvider: [String: [ModelConfig]] {
        guard !searchText.isEmpty else {
            return modelRouter.modelsByProvider
        }
        
        let searchLower = searchText.lowercased()
        var filtered: [String: [ModelConfig]] = [:]
        
        for (provider, models) in modelRouter.modelsByProvider {
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
        NavigationStack {
            List {
                // None option
                Button(action: {
                    selectedModelId = ""
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        if selectedModelId.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                        }
                        Text("None")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Provider sections
                ForEach(filteredProviders, id: \.self) { provider in
                    Section(modelRouter.providerDisplayName(provider)) {
                        ForEach(filteredModelsByProvider[provider] ?? []) { model in
                            Button(action: {
                                selectedModelId = model.id
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    if model.id == selectedModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                            .font(.caption)
                                    }
                                    Text(model.name)
                                        .font(.system(size: 13))
                                    if model.supportsThinking {
                                        Text("⚡")
                                            .font(.caption)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search fallback models...")
            .navigationTitle("Select Fallback Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
    }
}

// MARK: - Fallback Model Picker Sheet Wrapper
struct FallbackModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String = ModelRouter.shared.fallbackModelId
    
    var body: some View {
        FallbackModelPickerView(selectedModelId: $selectedId)
            .onDisappear {
                ModelRouter.shared.fallbackModelId = selectedId
            }
    }
}

#Preview {
    ModelsView()
}

// MARK: - Thinking Model Picker Popover
/// Popover for selecting thinking-capable models only
struct ThinkingModelPickerPopover: View {
    @Binding var selectedModelId: String
    let title: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    private var modelRouter: ModelRouter { ModelRouter.shared }
    
    /// Filter to ONLY thinking-capable models
    private var thinkingModelsByProvider: [String: [ModelConfig]] {
        let thinkingModels = modelRouter.models.filter { $0.supportsThinking }
        return Dictionary(grouping: thinkingModels, by: { $0.provider })
    }
    
    /// Filtered models based on search text (within thinking models only)
    private var filteredModelsByProvider: [String: [ModelConfig]] {
        guard !searchText.isEmpty else {
            return thinkingModelsByProvider
        }
        
        let searchLower = searchText.lowercased()
        var filtered: [String: [ModelConfig]] = [:]
        
        for (provider, models) in thinkingModelsByProvider {
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
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Search
            TextField("Search thinking models...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            // Model List
            List {
                // None option
                Button(action: {
                    selectedModelId = ""
                    NotificationCenter.default.post(name: NSNotification.Name("UpdateMenuBar"), object: nil)
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        if selectedModelId.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                        }
                        Text("None")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Provider sections (only thinking models)
                ForEach(filteredProviders, id: \.self) { provider in
                    Section(modelRouter.providerDisplayName(provider)) {
                        ForEach(filteredModelsByProvider[provider] ?? []) { model in
                            Button(action: {
                                selectedModelId = model.id
                                NotificationCenter.default.post(name: NSNotification.Name("UpdateMenuBar"), object: nil)
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    if model.id == selectedModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                            .font(.caption)
                                    }
                                    Text(model.name)
                                        .font(.system(size: 13))
                                    Image(systemName: "brain")
                                        .font(.caption2)
                                        .foregroundColor(.pink)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 320, height: 400)
    }
}
