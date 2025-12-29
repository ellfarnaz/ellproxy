import Foundation

/**
 Extension for handling DeepSeek-specific fixes and workarounds
 
 DeepSeek R1 and Reasoner models have strict validation requirements
 that cause errors with standard OpenAI-compatible clients.
 */
extension ThinkingProxy {
    
    /**
     Strips thinking parameters from requests to DeepSeek when there are existing assistant messages.
     DeepSeek's thinking mode validation is too strict - it requires reasoning_content for ALL
     previous assistant messages, which CLI clients don't preserve. Disabling thinking mode
     for multi-turn conversations avoids the 400 error while still allowing first-turn thinking.
     */
    func stripThinkingForProblematicRequests(jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let model = json["model"] as? String else {
            return jsonString
        }
        
        // Check if this is a DeepSeek reasoner model
        let isDeepSeekReasoner = model.lowercased().contains("deepseek") && 
                                  (model.lowercased().contains("reasoner") || model.lowercased().contains("r1"))
        
        if !isDeepSeekReasoner {
            return jsonString
        }
        
        // Count assistant messages in history
        let assistantCount = messages.filter { $0["role"] as? String == "assistant" }.count
        
        // If there are existing assistant messages, strip thinking mode
        // to avoid the reasoning_content validation error
        if assistantCount > 0 {
            // Use the user's selected Default Model from UI settings
            // This respects user preference instead of hardcoding a fallback
            if let defaultModel = ModelRouter.shared.activeModel {
                var defaultUpstream = defaultModel.upstreamModel
                
                // CRITICAL CHECK: Ensure the fallback model itself is NOT a reasoner!
                // If user selected DeepSeek R1 as default, we must NOT use it for fallback here
                if defaultUpstream.lowercased().contains("reasoner") || defaultUpstream.lowercased().contains("r1") {
                   NSLog("[ThinkingProxy] ⚠️ CAUTION: Default model '\(defaultUpstream)' is also a reasoner! Forcing safe fallback to 'deepseek-chat'")
                   defaultUpstream = "deepseek-chat"
                }
                
                json["model"] = defaultUpstream
                
                // Show notification for model switch
                ModelRouter.shared.notifyRouting(
                    model: defaultModel.name,
                    provider: defaultModel.provider,
                    isForce: false
                )
                
                NSLog("[ThinkingProxy] ⚡️ DEEPSEEK FIX: Multi-turn detected (found \(assistantCount) assistant messages). Routing to Safe Model: \(model) → \(defaultUpstream)")
            } else {
                // Fallback: just strip -reasoner suffix
                let nonReasonerModel = model
                    .replacingOccurrences(of: "-reasoner", with: "-chat")
                    .replacingOccurrences(of: "-r1", with: "")
                json["model"] = nonReasonerModel
                
                NSLog("[ThinkingProxy] ⚡️ DEEPSEEK FIX: Multi-turn detected (found \(assistantCount) assistant messages). Fallback: \(model) → \(nonReasonerModel)")
            }
            
            // Remove thinking parameters
            json.removeValue(forKey: "thinking")
            json.removeValue(forKey: "thinking_budget")
            
            // Also clamp max_tokens for DeepSeek (max 8192)
            if let maxTokens = json["max_tokens"] as? Int, maxTokens > 8192 {
                json["max_tokens"] = 8192
                NSLog("[ThinkingProxy] ⚡️ DEEPSEEK FIX: Clamped max_tokens from \(maxTokens) to 8192")
            }
            
            if let newData = try? JSONSerialization.data(withJSONObject: json),
               let newString = String(data: newData, encoding: .utf8) {
                return newString
            }
        }
        
        // Clamp max_tokens for ALL DeepSeek models (even first turn)
        // DeepSeek has a max limit of 8192 tokens
        if let maxTokens = json["max_tokens"] as? Int, maxTokens > 8192 {
            json["max_tokens"] = 8192
            NSLog("[ThinkingProxy] ⚡️ DEEPSEEK FIX: Clamped max_tokens from \(maxTokens) to 8192 (first turn)")
            
            if let newData = try? JSONSerialization.data(withJSONObject: json),
               let newString = String(data: newData, encoding: .utf8) {
                return newString
            }
        }
        
        return jsonString
    }
    
    /**
     DeepSeek and other reasoning models enforce that if 'reasoning_content' was generated,
     it must be preserved in the conversation history.
     Standard clients (OpenAI SDK, Droid, Claude CLI) often drop unknown fields from history.
     
     BULLETPROOF FIX: Always inject reasoning_content with a non-empty value
     for ALL assistant messages. DeepSeek requires this field to be present and non-empty.
     */
    func injectDummyReasoningContent(jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var messages = json["messages"] as? [[String: Any]] else {
            return jsonString
        }
        
        var modified = false
        var assistantCount = 0
        
        NSLog("[ThinkingProxy] 💪 BULLETPROOF: Processing \(messages.count) messages")
        
        for (i, message) in messages.enumerated() {
            if message["role"] as? String == "assistant" {
                assistantCount += 1
                var newMessage = message
                
                // Get existing content for cache lookup
                let contentString = (message["content"] as? String) ?? ""
                
                // Try cache first, then fallback to meaningful dummy
                var reasoning = ReasoningCache.shared.retrieve(for: contentString) ?? "I analyzed the request carefully before responding."
                
                // ENSURE reasoning is never empty
                if reasoning.isEmpty {
                    reasoning = "Thinking process not preserved by client."
                }
                
                // ALWAYS set reasoning_content (overwrite if exists)
                newMessage["reasoning_content"] = reasoning
                messages[i] = newMessage
                modified = true
                
                NSLog("[ThinkingProxy] 💪 Set reasoning for assistant #\(assistantCount) at index \(i)")
            }
        }
        
        if modified {
            json["messages"] = messages
            if let newData = try? JSONSerialization.data(withJSONObject: json),
               let newString = String(data: newData, encoding: .utf8) {
                NSLog("[ThinkingProxy] 💪 Processed \(assistantCount) assistant messages")
                return newString
            }
        }
        
        return jsonString
    }
}
