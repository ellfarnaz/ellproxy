import Foundation
import Combine

/// Represents a single model configuration
struct ModelConfig: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let upstreamModel: String
    let supportsThinking: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, provider
        case upstreamModel = "upstream_model"
        case supportsThinking = "supports_thinking"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ModelConfig, rhs: ModelConfig) -> Bool {
        lhs.id == rhs.id
    }
}



/// Manages model routing and selection
class ModelRouter: ObservableObject {
    static let shared = ModelRouter()
    
    @Published private(set) var models: [ModelConfig] = [] {
        didSet {
            NSLog("[ModelRouter] Models updated: %d models available", models.count)
        }
    }
    @Published var activeModelId: String = "google:gemini-2.5-flash" {
        didSet {
            UserDefaults.standard.set(activeModelId, forKey: "activeModelId")
            NSLog("[ModelRouter] Active model changed to: %@", activeModelId)
        }
    }
    
    @Published var routingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(routingEnabled, forKey: "routingEnabled")
            NSLog("[ModelRouter] Routing enabled: %@", routingEnabled ? "true" : "false")
        }
    }
    
    @Published var notifyOnRouting: Bool = true {
        didSet {
            UserDefaults.standard.set(notifyOnRouting, forKey: "notifyOnRouting")
            NSLog("[ModelRouter] Notify on routing: %@", notifyOnRouting ? "true" : "false")
        }
    }
    
    @Published var fallbackModelId: String = "" {
        didSet {
            UserDefaults.standard.set(fallbackModelId, forKey: "fallbackModelId")
            NSLog("[ModelRouter] Fallback model changed to: %@", fallbackModelId)
        }
    }
    
    // MARK: - Thinking Track
    
    @Published var defaultThinkingModelId: String = "" {
        didSet {
            UserDefaults.standard.set(defaultThinkingModelId, forKey: "defaultThinkingModelId")
            NSLog("[ModelRouter] Default Thinking model changed to: %@", defaultThinkingModelId)
        }
    }
    
    @Published var fallbackThinkingModelId: String = "" {
        didSet {
            UserDefaults.standard.set(fallbackThinkingModelId, forKey: "fallbackThinkingModelId")
            NSLog("[ModelRouter] Fallback Thinking model changed to: %@", fallbackThinkingModelId)
        }
    }
    
    // MARK: - Reasoning Effort Control
    
    /// Reasoning effort level for thinking models (low/medium/high)
    @Published var reasoningLevel: String = "medium" {
        didSet {
            UserDefaults.standard.set(reasoningLevel, forKey: "reasoningLevel")
            NSLog("[ModelRouter] Reasoning level changed to: %@", reasoningLevel)
        }
    }
    
    // MARK: - Provider:ID Helpers
    
    /// Creates a unique key from provider and id (format: "provider:id")
    static func uniqueKey(for model: ModelConfig) -> String {
        return "\(model.provider):\(model.id)"
    }
    
    /// Creates a unique key from provider and id strings
    static func uniqueKey(provider: String, id: String) -> String {
        return "\(provider):\(id)"
    }
    
    /// Parses a unique key into (provider, id) tuple
    static func parseKey(_ key: String) -> (provider: String, id: String)? {
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
    
    /// Finds a model by its unique key (provider:id format)
    func findModel(byKey key: String) -> ModelConfig? {
        guard let (provider, id) = ModelRouter.parseKey(key) else {
            // Fallback: try legacy ID-only match (for backwards compatibility)
            return models.first { $0.id == key }
        }
        return models.first { $0.provider == provider && $0.id == id }
    }
    
    /// Currently active model configuration
    var activeModel: ModelConfig? {
        findModel(byKey: activeModelId)
    }
    
    /// Fallback model configuration
    var fallbackModel: ModelConfig? {
        guard !fallbackModelId.isEmpty else { return nil }
        return findModel(byKey: fallbackModelId)
    }
    
    /// Default thinking model configuration
    var defaultThinkingModel: ModelConfig? {
        guard !defaultThinkingModelId.isEmpty else { return nil }
        return findModel(byKey: defaultThinkingModelId)
    }
    
    /// Fallback thinking model configuration
    var fallbackThinkingModel: ModelConfig? {
        guard !fallbackThinkingModelId.isEmpty else { return nil }
        return findModel(byKey: fallbackThinkingModelId)
    }
    
    /// All models that support thinking
    var thinkingModels: [ModelConfig] {
        models.filter { $0.supportsThinking }
    }
    
    // MARK: - Recent Models Tracking
    
    /// Recently used model IDs (max 5)
    private(set) var recentModelIds: [String] = [] {
        didSet {
            UserDefaults.standard.set(recentModelIds, forKey: "recentModelIds")
        }
    }
    
    /// Recently used model configurations
    var recentModels: [ModelConfig] {
        recentModelIds.compactMap { modelId in
            models.first { $0.id == modelId }
        }
    }
    
    /// Group models by provider
    var modelsByProvider: [String: [ModelConfig]] {
        Dictionary(grouping: models, by: { $0.provider })
    }
    
    /// Available providers in order
    var providers: [String] {
        let order = ["antigravity", "google", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        return order.filter { modelsByProvider[$0] != nil }
    }
    
    private init() {
        // Load saved preferences
        self.activeModelId = UserDefaults.standard.string(forKey: "activeModelId") ?? "google:gemini-2.5-flash"
        self.routingEnabled = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
        self.notifyOnRouting = UserDefaults.standard.object(forKey: "notifyOnRouting") as? Bool ?? true
        self.fallbackModelId = UserDefaults.standard.string(forKey: "fallbackModelId") ?? ""
        self.defaultThinkingModelId = UserDefaults.standard.string(forKey: "defaultThinkingModelId") ?? ""
        self.fallbackThinkingModelId = UserDefaults.standard.string(forKey: "fallbackThinkingModelId") ?? ""
        self.reasoningLevel = UserDefaults.standard.string(forKey: "reasoningLevel") ?? "medium"
        self.recentModelIds = UserDefaults.standard.stringArray(forKey: "recentModelIds") ?? []
        loadModels()
    }
    
    /// Container for a single provider's models JSON file
    struct ProviderModelsFile: Codable {
        let provider: String
        let models: [ModelConfig]
    }
    
    /// Loads models from the bundled JSON files (one per provider)
    func loadModels() {
        // Define provider files in order
        let providerFiles = ["antigravity", "google", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        var allModels: [ModelConfig] = []
        
        for providerName in providerFiles {
            // Try to load from bundle's models/ subdirectory
            if let url = Bundle.main.url(forResource: providerName, withExtension: "json", subdirectory: "models") {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let providerData = try decoder.decode(ProviderModelsFile.self, from: data)
                    allModels.append(contentsOf: providerData.models)
                    NSLog("[ModelRouter] Loaded %d models from %@.json", providerData.models.count, providerName)
                } catch {
                    NSLog("[ModelRouter] Failed to load %@.json: %@", providerName, error.localizedDescription)
                }
            }
        }
        
        // Fallback: try loading from legacy single models.json if no provider files found
        if allModels.isEmpty {
            NSLog("[ModelRouter] No model files found in bundle")
        }
        
        // Load discovered models from Application Support (from sync)
        let discoveredModels = DiscoveredModelsStore.shared.loadAllDiscoveredModels()
        if !discoveredModels.isEmpty {
            NSLog("[ModelRouter] Found %d discovered models from sync", discoveredModels.count)
            // Merge discovered models (avoiding duplicates)
            allModels = DiscoveredModelsStore.shared.mergedModels(bundled: allModels, discovered: discoveredModels)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.models = allModels
            NSLog("[ModelRouter] Total loaded: %d models (incl. discovered)", allModels.count)
            
            // Set default active model if not set or if current model not found
            if self?.activeModelId.isEmpty == true || self?.findModel(byKey: self?.activeModelId ?? "") == nil,
               let firstModel = allModels.first {
                self?.activeModelId = ModelRouter.uniqueKey(for: firstModel)
            }
        }
    }
    
    /// Clear discovered models for a specific provider
    func clearDiscoveredModels(for provider: String) {
        DiscoveredModelsStore.shared.clearDiscoveredModels(for: provider)
        // Reload all models to reflect changes
        loadModels()
    }
    
    /// Rewrites a model name to its upstream equivalent
    /// - Parameter requestedModel: The model name from the request
    /// - Returns: The upstream model name to use
    /// Finds the matching model configuration for a requested model string
    /// - Parameter requestedModel: The model name from the request
    /// - Returns: The matching ModelConfig, or nil if no match found (unless fallback to active is used)
    func matchModel(for requestedModel: String) -> ModelConfig? {
        // 1) Exact match
        if let model = models.first(where: { $0.id == requestedModel }) {
            return model
        }

        // 2) Normalized match: strip trailing date suffixes like -YYYYMMDD
        //    e.g., claude-sonnet-4-5-20250929 -> claude-sonnet-4-5
        let normalized = requestedModel.replacingOccurrences(of: "-\\d{8}$", with: "", options: .regularExpression)
        if normalized != requestedModel, let model = models.first(where: { $0.id == normalized }) {
            return model
        }

        // 3) Prefix match: handle cases like 'claude-sonnet-4-5-20250929-suffix' where model id starts with known id
        if let model = models.first(where: { requestedModel.hasPrefix($0.id + "-") || requestedModel.hasPrefix($0.id + "_") }) {
            return model
        }

        // 4) Fallback to active model (only if routing is generally enabled, this might be debatably part of rewrite logic vs match logic. 
        //    For capability check, we probably want to know *which* model it routed to.)
        // 4) Fallback to active model - This causes sync issues for new models!
        if let active = activeModel {
            NSLog("[ModelRouter] matchModel: No match for '%@', falling back to Active Model: '%@'", requestedModel, active.id)
            return active
        }
        
        return nil
    }

    /// Rewrites a model name to its upstream equivalent
    /// - Parameter requestedModel: The model name from the request
    /// - Returns: The upstream model name to use
    func rewriteModel(requestedModel: String) -> String {
        // Panic Mode: If routing is disabled, FORCE the default model
        guard routingEnabled else {
            guard let active = activeModel else { return requestedModel }
            
            // Notify user of force mode
            notifyRouting(model: active.upstreamModel, provider: active.provider, isForce: true)
            
            NSLog("[ModelRouter] PAUSED/PANIC MODE: Forced '%@' → '%@'", requestedModel, active.upstreamModel)
            return active.upstreamModel
        }

        // Smart Mode: Check for matches
        if let model = matchModel(for: requestedModel) {
            NSLog("[ModelRouter] Mapped model '%@' → '%@'", requestedModel, model.upstreamModel)
            
            // Notify user of smart routing decision
            notifyRouting(model: model.upstreamModel, provider: model.provider, isForce: false)
            
            return model.upstreamModel
        }
        
        // Handle "auto" strings from OpenCode/clients - map to Active Default Model
        if requestedModel.lowercased().contains("auto") {
            if let active = activeModel {
                NSLog("[ModelRouter] 'Auto' model requested ('%@') → Mapped to Default: '%@'", requestedModel, active.upstreamModel)
                
                // Notify user of auto mapping
                notifyRouting(model: active.upstreamModel, provider: active.provider, isForce: false)
                
                return active.upstreamModel
            }
        }

        // Final fallback: pass through unchanged
        return requestedModel
    }
    
    func notifyRouting(model: String, provider: String, isForce: Bool = false) {
        guard notifyOnRouting else { return }
        
        let message = isForce 
            ? "Default Model: \(model) (\(provider))"
            : "Using Model: \(model) (\(provider))"
            
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .init("routingNotification"),
                object: nil,
                userInfo: ["message": message]
            )
        }
    }
    
    /// Adds a model ID to recent models list (max 5, most recent first)
    func addToRecentModels(_ modelId: String) {
        // Remove if already exists
        recentModelIds.removeAll { $0 == modelId }
        // Insert at front
        recentModelIds.insert(modelId, at: 0)
        // Keep only last 5
        if recentModelIds.count > 5 {
            recentModelIds = Array(recentModelIds.prefix(5))
        }
        NSLog("[ModelRouter] Added to recent models: %@", modelId)
    }
    
    /// Gets provider display name
    func providerDisplayName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "antigravity": return "AntiGravity"
        case "google": return "Google Gemini"
        case "qwen": return "Qwen"
        case "iflow": return "iFlow"
        case "codex": return "Codex (OpenAI)"
        case "claude": return "Claude"
        case "copilot": return "GitHub Copilot"
        case "kiro": return "Kiro"
        default: return provider.capitalized
        }
    }
    
    /// Gets provider icon name
    func providerIconName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "antigravity": return "icon-antigravity.png"
        case "google": return "icon-gemini.png"
        case "qwen": return "icon-qwen.png"
        case "iflow": return "icon-iflow.png"
        case "codex": return "icon-codex.png"
        case "claude": return "icon-claude.png"
        case "copilot": return "icon-copilot.png"
        case "kiro": return "icon-kiro.png"
        default: return "icon-claude.png"
        }
    }
    
    /**
     Adds a new model to the list and saves to JSON
     */
    func addModel(_ model: ModelConfig) throws {
        // Validate model doesn't already exist
        guard !models.contains(where: { $0.id == model.id }) else {
            throw NSError(domain: "ModelRouter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Model with ID '\(model.id)' already exists"
            ])
        }
        
        // Add to models array
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.models.append(model)
            NSLog("[ModelRouter] Added model: %@", model.id)
            
            // Save to file
            do {
                try self.saveModels()
            } catch {
                NSLog("[ModelRouter] Failed to save models: %@", error.localizedDescription)
            }
        }
    }
    
    /**
     Saves the current models array to the bundle's models.json file
     */
    func saveModels() throws {
        // Saving is disabled as we moved to provider-specific files and deleted models.json
        NSLog("[ModelRouter] saveModels called but disabled (models.json removed)")
    }
    
    /**
     Deletes a model from the list and saves to JSON
     */
    func deleteModel(_ model: ModelConfig) throws {
        // Remove from models array
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let modelKey = ModelRouter.uniqueKey(for: model)
            
            // Find and remove by provider:id
            if let index = self.models.firstIndex(where: { ModelRouter.uniqueKey(for: $0) == modelKey }) {
                self.models.remove(at: index)
                NSLog("[ModelRouter] Deleted model: %@", modelKey)
                
                // If deleted model was active, reset to first available
                if self.activeModelId == modelKey, let firstModel = self.models.first {
                    self.activeModelId = ModelRouter.uniqueKey(for: firstModel)
                }
                
                // If deleted model was fallback, clear it
                if self.fallbackModelId == modelKey {
                    self.fallbackModelId = ""
                }
                
                // CRITICAL: Also remove from DiscoveredModelsStore so sync can re-add it
                self.removeFromDiscoveredModels(model)
                
                // Save to file
                do {
                    try self.saveModels()
                } catch {
                    NSLog("[ModelRouter] Failed to save after delete: %@", error.localizedDescription)
                }
            }
        }
    }
    
    /// Removes a model from the discovered models store
    private func removeFromDiscoveredModels(_ model: ModelConfig) {
        let store = DiscoveredModelsStore.shared
        var discoveredModels = store.loadDiscoveredModels(for: model.provider)
        
        // Remove the model from discovered list
        discoveredModels.removeAll { $0.id == model.id }
        
        // Save back to file
        do {
            try store.saveDiscoveredModels(discoveredModels, for: model.provider)
            NSLog("[ModelRouter] Removed '%@' from discovered models for %@", model.id, model.provider)
        } catch {
            NSLog("[ModelRouter] Failed to remove from discovered models: %@", error.localizedDescription)
        }
    }

    
    /**
     Updates the thinking support status for a model and persists it as a user override
     */
    func updateModelThinking(model: ModelConfig, supportsThinking: Bool) {
        // Create updated copy
        let updatedModel = ModelConfig(
            id: model.id,
            name: model.name,
            provider: model.provider,
            upstreamModel: model.upstreamModel,
            supportsThinking: supportsThinking
        )
        
        // Save to DiscoveredModelsStore (which now acts as overrides)
        do {
            try DiscoveredModelsStore.shared.updateModel(updatedModel)
            
            // Reload all models to reflect changes (merging bundled + discovered)
            loadModels()
            
            NSLog("[ModelRouter] Updated thinking support for '%@' to %d", model.name, supportsThinking)
        } catch {
            NSLog("[ModelRouter] Failed to update model thinking: %@", error.localizedDescription)
        }
    }
}
