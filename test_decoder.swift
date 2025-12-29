import Foundation

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
}

struct DiscoveredModelsContainer: Codable {
    let provider: String
    let models: [ModelConfig]
    let lastSync: Date
}

let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/EllProxy/discovered_models/discovered_copilot.json")

do {
    let data = try Data(contentsOf: path)
    let decoder = JSONDecoder()
    // decoder.keyDecodingStrategy = .convertFromSnakeCase // Simulate our current code
    
    // We need to handle Date decoding ISO8601 as typically used
    decoder.dateDecodingStrategy = .iso8601
    
    let container = try decoder.decode(DiscoveredModelsContainer.self, from: data)
    print("Success! Loaded \(container.models.count) models")
    for model in container.models {
        print("- \(model.name) (\(model.id))")
    }
} catch {
    print("Error decoding: \(error)")
}
