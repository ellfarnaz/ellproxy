import Foundation

/// Service for syncing models from API and determining thinking support via shell script
class ModelSyncService: ObservableObject {
    static let shared = ModelSyncService()
    
    @Published var isSyncing: Bool = false
    @Published var lastError: String?
    @Published var syncProgress: SyncProgress?
    
    private let store = DiscoveredModelsStore.shared
    
    /// Path to the thinking support test script
    private var scriptPath: String {
        // Try bundled path first
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = "\(resourcePath)/sync_thinking_support.sh"
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        // Development fallback
        return "/Users/ellfarnaz/Documents/vibeproxy/scripts/sync_thinking_support.sh"
    }
    
    private init() {}
    
    // MARK: - Sync Provider
    
    /// Sync models for a specific provider
    /// - Parameters:
    ///   - provider: Provider name (e.g., "iflow", "antigravity")
    /// - Returns: Sync result with new models found
    func syncProvider(_ provider: String) async throws -> SyncResult {
        NSLog("[ModelSync] Syncing provider: %@", provider)
        
        // Notify UI that sync started
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .init("routingNotification"),
                object: nil,
                userInfo: ["message": "Syncing \(provider.capitalized)..."]
            )
        }
        
        // 1. Fetch from localhost:8317/v1/modelsr.run {
        await MainActor.run {
            isSyncing = true
            lastError = nil
            syncProgress = SyncProgress(provider: provider, current: 0, total: 0, status: "Fetching models...")
        }
        
        defer {
            Task { @MainActor in
                isSyncing = false
                syncProgress = nil
            }
        }
        
        do {
            // 1. Fetch ALL models from API for this provider (API is source of truth)
            let apiModels = try await fetchModelsFromAPI(provider: provider)
            let apiModelIds = Set(apiModels.map { $0.id })
            
            NSLog("[ModelSyncService] API returned %d models for provider %@", apiModels.count, provider)
            
            // 2. Load existing discovered models for this provider
            let existingDiscovered = store.loadDiscoveredModels(for: provider)
            let existingDiscoveredIds = Set(existingDiscovered.map { $0.id })
            
            // 3. CRITICAL: Remove discovered models that NO LONGER exist in API
            let modelsToRemove = existingDiscovered.filter { !apiModelIds.contains($0.id) }
            if !modelsToRemove.isEmpty {
                NSLog("[ModelSyncService] Removing %d models no longer in API: %@", 
                      modelsToRemove.count, 
                      modelsToRemove.map { $0.id }.joined(separator: ", "))
            }
            
            // 4. Keep discovered models that STILL exist in API
            let modelsToKeep = existingDiscovered.filter { apiModelIds.contains($0.id) }
            
            // 5. Find NEW models that need to be tested (in API but not yet discovered)
            let newApiModels = apiModels.filter { !existingDiscoveredIds.contains($0.id) }
            
            if newApiModels.isEmpty && modelsToRemove.isEmpty {
                NSLog("[ModelSyncService] No changes needed for %@", provider)
                return SyncResult(provider: provider, newModels: [], updatedCount: 0, errors: [])
            }
            
            NSLog("[ModelSyncService] Found %d new models for %@", newApiModels.count, provider)
            
            await MainActor.run {
                syncProgress = SyncProgress(
                    provider: provider,
                    current: 0,
                    total: newApiModels.count,
                    status: "Syncing models for thinking support..."
                )
            }
            
            // 6. For each new model, determine thinking support using script
            var newConfigs: [ModelConfig] = []
            var errors: [String] = []
            
            for (index, apiModel) in newApiModels.enumerated() {
                await MainActor.run {
                    syncProgress = SyncProgress(
                        provider: provider,
                        current: index + 1,
                        total: newApiModels.count,
                        status: "Sync: \(apiModel.id)"
                    )
                }
                
                do {
                    let supportsThinking = try await determineThinkingSupport(for: apiModel.id)
                    
                    let config = ModelConfig(
                        id: apiModel.id,
                        name: humanizeName(apiModel.id),
                        provider: provider,
                        upstreamModel: apiModel.id,
                        supportsThinking: supportsThinking
                    )
                    
                    newConfigs.append(config)
                    NSLog("[ModelSyncService] %@ supports_thinking: %@", apiModel.id, supportsThinking ? "true" : "false")
                    
                } catch {
                    NSLog("[ModelSyncService] Error testing %@: %@", apiModel.id, error.localizedDescription)
                    
                    // Default to inferred value on error
                    let config = ModelConfig(
                        id: apiModel.id,
                        name: humanizeName(apiModel.id),
                        provider: provider,
                        upstreamModel: apiModel.id,
                        supportsThinking: inferFromName(apiModel.id)
                    )
                    newConfigs.append(config)
                    errors.append("\(apiModel.id): \(error.localizedDescription)")
                }
                
                // Small delay between tests to avoid overwhelming the server
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            // 7. Save discovered models: keep valid existing + add new tested
            let combined = modelsToKeep + newConfigs
            
            // Deduplicate by ID (keep last occurrence - new overrides old)
            var uniqueModels: [String: ModelConfig] = [:]
            for model in combined {
                uniqueModels[model.id] = model
            }
            let allDiscovered = Array(uniqueModels.values)
            
            try store.saveDiscoveredModels(allDiscovered, for: provider)
            NSLog("[ModelSyncService] Saved %d discovered models for %@ (kept: %d, new: %d, removed: %d)", 
                  allDiscovered.count, provider, modelsToKeep.count, newConfigs.count, modelsToRemove.count)
            
            // 8. Reload models in ModelRouter
            await MainActor.run {
                ModelRouter.shared.loadModels()
            }
            
            NSLog("[ModelSyncService] Sync complete for %@: %d new models", provider, newConfigs.count)
            
            return SyncResult(
                provider: provider,
                newModels: newConfigs,
                updatedCount: newConfigs.count,
                errors: errors
            )
            
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - API Fetch
    
    /// Model info from API
    struct APIModel: Codable {
        let id: String
        let object: String?
        let owned_by: String?
    }
    
    struct APIModelsResponse: Codable {
        let data: [APIModel]
    }
    
    /// Fetch models from the local proxy API
    private func fetchModelsFromAPI(provider: String? = nil) async throws -> [APIModel] {
        let urlString = "http://localhost:8317/v1/models"
        
        guard let url = URL(string: urlString) else {
            throw SyncError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SyncError.apiError("Failed to fetch models from API")
        }
        
        let decoder = JSONDecoder()
        let modelsResponse = try decoder.decode(APIModelsResponse.self, from: data)
        
        // Filter by provider if specified
        guard let provider = provider else {
            NSLog("[ModelSyncService] Fetched %d total models from API", modelsResponse.data.count)
            return modelsResponse.data
        }
        
        // Map provider names to owned_by values
        let providerMapping: [String: String] = [
            "copilot": "github-copilot",
            "claude": "anthropic",
            "gemini": "google",
            "qwen": "qwen",
            "iflow": "iflow",
            "antigravity": "antigravity",
            "codex": "openai",
            "kiro": "kiro"
        ]
        
        let ownedBy = providerMapping[provider.lowercased()] ?? provider
        let searchTerms = [
            ownedBy.lowercased(),
            provider.lowercased(),
            "trae-proxy",
            "vibeproxy",
            "user",
            "system"
        ]
        
        let filtered = modelsResponse.data.filter { model in
            let modelOwner = model.owned_by?.lowercased() ?? ""
            // Relaxed check: accept if owner contains any of the valid terms
            return searchTerms.contains { term in
                modelOwner.contains(term)
            }
        }
        
        NSLog("[ModelSyncService] Fetched %d models from API (filtered to %d for provider '%@')", 
              modelsResponse.data.count, filtered.count, provider)
        return filtered
    }
    
    // MARK: - Thinking Support Detection
    
    /// Determine if a model supports thinking by testing with the shell script
    private func determineThinkingSupport(for modelId: String) async throws -> Bool {
        NSLog("[ModelSyncService] Testing thinking support for: %@", modelId)
        
        struct TestConfig {
            let name: String
            let params: String
        }
        
        // Define test configurations to try in order
        let tests = [
            // 1. Standard (DeepSeek R1, GLM, o1, etc.)
            TestConfig(name: "Standard", params: ""),
            
            // 2. Google / Gemini (requires reasoning_effort)
            TestConfig(name: "Google/Gemini", params: ", \"reasoning_effort\": \"medium\""),
            
            // 3. Anthropic / Claude (requires thinking param)
            TestConfig(name: "Anthropic/Claude", params: ", \"thinking\": { \"type\": \"enabled\", \"budget_tokens\": 1024 }")
        ]
        
        // Try each configuration until one works
        for config in tests {
            // NSLog("[ModelSyncService] Testing %@ with config: %@", modelId, config.name)
            
            let supportsThinking = try await runThinkingTest(for: modelId, params: config.params)
            if supportsThinking {
                NSLog("[ModelSyncService] Verified %@ supports thinking (Config: %@)", modelId, config.name)
                return true
            }
        }
        
        NSLog("[ModelSyncService] %@ - No thinking support detected after %d tests", modelId, tests.count)
        return false
    }
    
    /// Run a single curl test with specific parameters
    private func runThinkingTest(for modelId: String, params: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    
                    // Inject params into the JSON payload
                    let command = """
                    curl -s --max-time 120 http://localhost:8317/v1/chat/completions \
                    -H "Content-Type: application/json" \
                    -H "X-EllProxy-Test: true" \
                    -H "X-EllProxy-Provider: \(ModelRouter.shared.matchModel(for: modelId)?.provider ?? "Unknown")" \
                    -d '{"model": "\(modelId)", "messages": [{"role": "user", "content": "Why is sky blue?"}]\(params)}'
                    """
                    
                    process.arguments = ["-c", command]
                    
                    let outputPipe = Pipe()
                    process.standardOutput = outputPipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    
                    // Parse JSON response
                    if let jsonData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        
                        // Check usage.completion_tokens_details.reasoning_tokens
                        if let usage = json["usage"] as? [String: Any],
                           let details = usage["completion_tokens_details"] as? [String: Any],
                           let reasoningTokens = details["reasoning_tokens"] as? Int,
                           reasoningTokens > 0 {
                            // NSLog("[ModelSyncService] %@ has reasoning_tokens: %d", modelId, reasoningTokens)
                            continuation.resume(returning: true)
                            return
                        }
                        
                        if let choices = json["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let message = firstChoice["message"] as? [String: Any] {
                            
                            // Check reasoning_content
                            if let reasoningContent = message["reasoning_content"] as? String, !reasoningContent.isEmpty {
                                continuation.resume(returning: true)
                                return
                            }
                            
                            // Check thinkingResult
                            if let thinkingResult = message["thinkingResult"] as? [String: Any], thinkingResult["summary"] != nil {
                                continuation.resume(returning: true)
                                return
                            }
                            
                            // Check reasoning_details
                            if let reasoningDetails = message["reasoning_details"] as? [[String: Any]], !reasoningDetails.isEmpty {
                                continuation.resume(returning: true)
                                return
                            }
                            
                            // Check <think> tags in content
                            if let content = message["content"] as? String {
                                if content.contains("<think>") || content.contains("</think>") {
                                    continuation.resume(returning: true)
                                    return
                                }
                            }
                        }
                    }
                    
                    continuation.resume(returning: false)
                    
                } catch {
                    // Log error but treat as false for this specific test run
                    // NSLog("[ModelSyncService] Error in test run for %@: %@", modelId, error.localizedDescription)
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Humanize model ID to display name
    private func humanizeName(_ modelId: String) -> String {
        let parts = modelId.split(separator: "-")
        return parts.map { part in
            let str = String(part)
            if str.first?.isNumber == true {
                return str.uppercased()
            }
            let abbreviations = ["gpt", "glm", "vl", "ai", "llm"]
            if abbreviations.contains(str.lowercased()) {
                return str.uppercased()
            }
            return str.prefix(1).uppercased() + str.dropFirst()
        }.joined(separator: " ")
    }
    
    /// Infer thinking support from model name (fallback when test fails)
    private func inferFromName(_ modelId: String) -> Bool {
        let lowercased = modelId.lowercased()
        
        let explicitThinkingIndicators = [
            "thinking", "reasoner", "reason", "o1", "o3", "o4", 
            "-r1-", "-r1",
            "qvq", "qwq"
        ]
        for indicator in explicitThinkingIndicators {
            if lowercased.contains(indicator) {
                return true
            }
        }
        
        let nonThinkingIndicators = [
            "mini", "flash", "nano", "lite", 
            "vision", "-vl", "embed", "whisper"
        ]
        for indicator in nonThinkingIndicators {
            if lowercased.contains(indicator) {
                return false
            }
        }
        
        return false
    }
}

// MARK: - Types

struct SyncResult {
    let provider: String
    let newModels: [ModelConfig]
    let updatedCount: Int
    let errors: [String]
}

struct SyncProgress {
    let provider: String
    let current: Int
    let total: Int
    let status: String
}

enum SyncError: LocalizedError {
    case invalidURL
    case apiError(String)
    case testError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let message):
            return "API Error: \(message)"
        case .testError(let message):
            return "Test Error: \(message)"
        }
    }
}
