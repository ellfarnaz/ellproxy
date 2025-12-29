import Foundation

/// Manages persistent storage for discovered models in Application Support
class DiscoveredModelsStore {
    static let shared = DiscoveredModelsStore()
    
    /// Application Support directory for EllProxy
    private var appSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("EllProxy")
        return appSupport
    }
    
    /// Directory for discovered models
    private var discoveredModelsURL: URL {
        return appSupportURL.appendingPathComponent("discovered_models")
    }
    
    private init() {
        // Ensure directories exist
        createDirectoriesIfNeeded()
    }
    
    /// Create necessary directories
    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        
        do {
            if !fm.fileExists(atPath: discoveredModelsURL.path) {
                try fm.createDirectory(at: discoveredModelsURL, withIntermediateDirectories: true)
                NSLog("[DiscoveredModelsStore] Created directory: %@", discoveredModelsURL.path)
            }
        } catch {
            NSLog("[DiscoveredModelsStore] Failed to create directory: %@", error.localizedDescription)
        }
    }
    
    /// Get file URL for a provider's discovered models
    private func fileURL(for provider: String) -> URL {
        return discoveredModelsURL.appendingPathComponent("discovered_\(provider).json")
    }
    
    // MARK: - Load/Save
    
    /// Load discovered models for a specific provider
    /// - Parameter provider: Provider name (e.g., "iflow", "antigravity")
    /// - Returns: Array of discovered ModelConfig
    func loadDiscoveredModels(for provider: String) -> [ModelConfig] {
        let url = fileURL(for: provider)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // decoder.keyDecodingStrategy = .convertFromSnakeCase // Rely on CodingKeys
            decoder.dateDecodingStrategy = .iso8601
            let container = try decoder.decode(DiscoveredModelsContainer.self, from: data)
            
            NSLog("[DiscoveredModelsStore] Loaded %d discovered models for %@", container.models.count, provider)
            return container.models
        } catch {
            NSLog("[DiscoveredModelsStore] Failed to load discovered models for %@: %@", provider, error.localizedDescription)
            return []
        }
    }
    
    /// Save discovered models for a specific provider
    /// - Parameters:
    ///   - models: Array of ModelConfig to save
    ///   - provider: Provider name
    func saveDiscoveredModels(_ models: [ModelConfig], for provider: String) throws {
        let url = fileURL(for: provider)
        
        let container = DiscoveredModelsContainer(
            provider: provider,
            models: models,
            lastSync: Date()
        )
        
        let encoder = JSONEncoder()
        // encoder.keyEncodingStrategy = .convertToSnakeCase // Rely on CodingKeys
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(container)
        try data.write(to: url)
        
        NSLog("[DiscoveredModelsStore] Saved %d discovered models for %@", models.count, provider)
    }
    
    /// Load all discovered models across all providers
    func loadAllDiscoveredModels() -> [ModelConfig] {
        var allModels: [ModelConfig] = []
        
        let providers = ["antigravity", "google", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        
        for provider in providers {
            let models = loadDiscoveredModels(for: provider)
            allModels.append(contentsOf: models)
        }
        
        return allModels
    }
    
    /// Get last sync date for a provider
    func lastSyncDate(for provider: String) -> Date? {
        let url = fileURL(for: provider)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // decoder.keyDecodingStrategy = .convertFromSnakeCase // Rely on CodingKeys
            decoder.dateDecodingStrategy = .iso8601
            let container = try decoder.decode(DiscoveredModelsContainer.self, from: data)
            return container.lastSync
        } catch {
            return nil
        }
    }
    
    /// Merge bundled and discovered models, removing duplicates
    /// - Parameters:
    ///   - bundled: Models from bundled JSON files
    ///   - discovered: Models from sync
    /// - Returns: Merged array where DISCOVERED models override BUNDLED models (per provider+id)
    func mergedModels(bundled: [ModelConfig], discovered: [ModelConfig]) -> [ModelConfig] {
        var result: [ModelConfig] = []
        var processedKeys: Set<String> = []
        
        // Helper to create unique key: provider + id
        func uniqueKey(_ model: ModelConfig) -> String {
            return "\(model.provider):\(model.id)"
        }
        
        // 1. Add ALL discovered models first (they take priority as user overrides/latest sync)
        for model in discovered {
            let key = uniqueKey(model)
            if !processedKeys.contains(key) {
                result.append(model)
                processedKeys.insert(key)
            }
        }
        
        // 2. Add bundled models ONLY if they haven't been added yet (per provider+id)
        for model in bundled {
            let key = uniqueKey(model)
            if !processedKeys.contains(key) {
                result.append(model)
                processedKeys.insert(key)
            }
        }
        
        return result
    }
    
    /// Update or add a single model to the discovered store
    /// - Parameter model: The model to update
    func updateModel(_ model: ModelConfig) throws {
        // 1. Load existing models for this provider
        var models = loadDiscoveredModels(for: model.provider)
        
        // 2. Remove existing entry if any
        models.removeAll { $0.id == model.id }
        
        // 3. Add updated model
        models.append(model)
        
        // 4. Save back to file
        try saveDiscoveredModels(models, for: model.provider)
        
        NSLog("[DiscoveredModelsStore] Updated model '%@' in discovered store", model.name)
    }
    
    /// Clear all discovered models for a provider
    func clearDiscoveredModels(for provider: String) {
        let url = fileURL(for: provider)
        
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                NSLog("[DiscoveredModelsStore] Cleared discovered models for %@", provider)
            }
        } catch {
            NSLog("[DiscoveredModelsStore] Failed to clear discovered models: %@", error.localizedDescription)
        }
    }
    
    /// Clear all discovered models
    func clearAllDiscoveredModels() {
        let providers = ["antigravity", "google", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        for provider in providers {
            clearDiscoveredModels(for: provider)
        }
    }
}

// MARK: - Container

/// Container for discovered models JSON file
struct DiscoveredModelsContainer: Codable {
    let provider: String
    let models: [ModelConfig]
    let lastSync: Date
}
