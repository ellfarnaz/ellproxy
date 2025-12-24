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

/// Container for the models JSON file
struct ModelsFile: Codable {
    let models: [ModelConfig]
}

/// Manages model routing and selection
class ModelRouter: ObservableObject {
    static let shared = ModelRouter()
    
    @Published private(set) var models: [ModelConfig] = []
    @Published var activeModelId: String {
        didSet {
            UserDefaults.standard.set(activeModelId, forKey: "vibeproxy.activeModelId")
            NSLog("[ModelRouter] Active model changed to: %@", activeModelId)
        }
    }
    @Published var routingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(routingEnabled, forKey: "vibeproxy.routingEnabled")
            NSLog("[ModelRouter] Routing enabled: %@", routingEnabled ? "true" : "false")
        }
    }
    
    /// Currently active model configuration
    var activeModel: ModelConfig? {
        models.first { $0.id == activeModelId }
    }
    
    /// Group models by provider
    var modelsByProvider: [String: [ModelConfig]] {
        Dictionary(grouping: models, by: { $0.provider })
    }
    
    /// Available providers in order
    var providers: [String] {
        let order = ["antigravity", "gemini", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        return order.filter { modelsByProvider[$0] != nil }
    }
    
    private init() {
        // Load saved preferences
        self.activeModelId = UserDefaults.standard.string(forKey: "vibeproxy.activeModelId") ?? ""
        self.routingEnabled = UserDefaults.standard.bool(forKey: "vibeproxy.routingEnabled")
        loadModels()
    }
    
    /// Loads models from the bundled JSON file
    func loadModels() {
        // Try to load from bundle
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json") else {
            NSLog("[ModelRouter] models.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let config = try decoder.decode(ModelsFile.self, from: data)
            
            DispatchQueue.main.async { [weak self] in
                self?.models = config.models
                NSLog("[ModelRouter] Loaded %d models from config", config.models.count)
                
                // Set default active model if not set
                if self?.activeModelId.isEmpty == true, let firstModel = config.models.first {
                    self?.activeModelId = firstModel.id
                }
            }
        } catch {
            NSLog("[ModelRouter] Failed to load models.json: %@", error.localizedDescription)
        }
    }
    
    /// Rewrites a model name to its upstream equivalent
    /// - Parameter requestedModel: The model name from the request
    /// - Returns: The upstream model name to use
    func rewriteModel(requestedModel: String) -> String {
        // If routing is disabled, pass through unchanged
        guard routingEnabled else {
            return requestedModel
        }

        // 1) Exact match
        if let model = models.first(where: { $0.id == requestedModel }) {
            NSLog("[ModelRouter] Mapped model '%@' → '%@'", requestedModel, model.upstreamModel)
            return model.upstreamModel
        }

        // 2) Normalized match: strip trailing date suffixes like -YYYYMMDD
        //    e.g., claude-sonnet-4-5-20250929 -> claude-sonnet-4-5
        let normalized = requestedModel.replacingOccurrences(of: "-\\d{8}$", with: "", options: .regularExpression)
        if normalized != requestedModel, let model = models.first(where: { $0.id == normalized }) {
            NSLog("[ModelRouter] Normalized model '%@' -> '%@' -> '%@'", requestedModel, normalized, model.upstreamModel)
            return model.upstreamModel
        }

        // 3) Prefix match: handle cases like 'claude-sonnet-4-5-20250929-suffix' where model id starts with known id
        if let model = models.first(where: { requestedModel.hasPrefix($0.id + "-") || requestedModel.hasPrefix($0.id + "_") }) {
            NSLog("[ModelRouter] Prefix matched model '%@' -> '%@' -> '%@'", requestedModel, model.id, model.upstreamModel)
            return model.upstreamModel
        }

        // 4) Fallback to active model
        if let active = activeModel {
            NSLog("[ModelRouter] Using active model '%@' → '%@' for request '%@'", active.id, active.upstreamModel, requestedModel)
            return active.upstreamModel
        }

        // Final fallback: pass through unchanged
        return requestedModel
    }
    
    /// Gets provider display name
    func providerDisplayName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "antigravity": return "AntiGravity"
        case "gemini": return "Google Gemini"
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
        case "gemini": return "icon-gemini.png"
        case "qwen": return "icon-qwen.png"
        case "iflow": return "icon-iflow.png"
        case "codex": return "icon-codex.png"
        case "claude": return "icon-claude.png"
        case "copilot": return "icon-copilot.png"
        case "kiro": return "icon-kiro.png"
        default: return "icon-claude.png"
        }
    }
}
