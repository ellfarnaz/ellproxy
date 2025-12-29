import Foundation

/**
 Extension for handling thinking mode parameter processing
 
 Processes model routing, thinking budget parameters, and model capability checks.
 Handles Claude thinking mode, Gemini reasoning levels, and dual-track routing.
 */
extension ThinkingProxy {
    
    /**
     Processes the JSON body to add thinking parameter if model name has a thinking suffix,
     and applies model routing if enabled.
     Returns tuple of (modifiedJSON, needsTransformation)
     */
    func processThinkingParameter(jsonString: String, isSyncTest: Bool = false, providerName: String? = nil) -> (String, Bool)? {
        guard let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              var model = json["model"] as? String else {
            return nil
        }
        
        var wasModified = false
        
        // If this is a sync test, bypass all routing and force the requested model
        if isSyncTest {
            // No routing, no Droid fixes, just pass through (or minimal processing)
            // Actually, we still want to apply thinking params if the test requested them!
            // But we definitely want to SKIP rewriteModel.
            NSLog("[ThinkingProxy] Sync Test detected for model: %@ - Bypassing routing", model)
            
            // Notify user of sync progress (if UI listens to it)
            DispatchQueue.main.async {
                let providerInfo = providerName != nil ? "\(providerName!): " : ""
                NotificationCenter.default.post(
                    name: .init("routingNotification"),
                    object: nil,
                    userInfo: ["message": "Syncing \(providerInfo)\(model)"]
                )
            }
        } else {
            // Special handling for Droid CLI EllProxy models
            if model == "ellproxy-default" {
                // Route to active default model
                if let activeModel = ModelRouter.shared.activeModel {
                    json["model"] = activeModel.upstreamModel
                    model = activeModel.upstreamModel
                    wasModified = true
                    NSLog("[ThinkingProxy] Droid 'ellproxy-default' → Routed to Default: %@", activeModel.upstreamModel)
                    
                    // Notify user
                    ModelRouter.shared.notifyRouting(
                        model: activeModel.upstreamModel, 
                        provider: activeModel.provider, 
                        isForce: false
                    )
                }
            } else if model == "ellproxy-thinking" {
                // Route to active thinking model
                if let thinkingModel = ModelRouter.shared.defaultThinkingModel {
                    json["model"] = thinkingModel.upstreamModel
                    model = thinkingModel.upstreamModel
                    wasModified = true
                    NSLog("[ThinkingProxy] Droid 'ellproxy-thinking' → Routed to Thinking: %@", thinkingModel.upstreamModel)
                    
                    // Notify user
                    ModelRouter.shared.notifyRouting(
                        model: thinkingModel.upstreamModel, 
                        provider: thinkingModel.provider, 
                        isForce: false
                    )
                }
            }
            
            // Apply model routing if enabled (for other models)
            if !wasModified {
                let routedModel = ModelRouter.shared.rewriteModel(requestedModel: model)
                if routedModel != model {
                    json["model"] = routedModel
                    model = routedModel
                    wasModified = true
                    NSLog("[ThinkingProxy] Model routing: applied route to '%@'", routedModel)
                }
            }
        }
        
        // Check if model capabilities mismatch: thinking requested but model doesn't support it
        if let config = ModelRouter.shared.matchModel(for: model), !config.supportsThinking {
            if json.keys.contains("thinking") {
                // DUAL-TRACK ROUTING: Use user-configured Default Thinking Model
                guard let defaultThinkingConfig = ModelRouter.shared.defaultThinkingModel else {
                    // No thinking model configured - strip thinking params and continue
                    json.removeValue(forKey: "thinking")
                    wasModified = true
                    NSLog("[ThinkingProxy] No Default Thinking Model configured. Stripped thinking params.")
                    
                    if let modifiedData = try? JSONSerialization.data(withJSONObject: json),
                       let modifiedString = String(data: modifiedData, encoding: .utf8) {
                        return (modifiedString, false)
                    }
                    return nil
                }
                
                // Switch to user's configured Default Thinking Model
                let thinkingUpstream = defaultThinkingConfig.upstreamModel
                json["model"] = thinkingUpstream
                model = thinkingUpstream
                wasModified = true
                
                NSLog("[ThinkingProxy] DUAL-TRACK: Thinking request detected. Routing to Default Thinking: '%@' (upstream: '%@')", defaultThinkingConfig.id, thinkingUpstream)
                
                // Notify user of thinking routing
                ModelRouter.shared.notifyRouting(model: defaultThinkingConfig.name, provider: defaultThinkingConfig.provider, isForce: false)
            }
        }
        
        // Only process Claude models or mapped thinking models
        if model.starts(with: "claude-") || model.starts(with: "gemini-claude-") {
            
            // --- MAPPING LOGIC START ---
            // If it's a "gemini-claude" model, we might want to OVERRIDE the native thinkingLevel
            // with a manual token budget if the user wants "High Power".
            // Or if it's a pure Claude model without suffix, we inject params based on UI.
            
            var needsMapping = false
            
            // 1. Pure Claude models (e.g. claude-sonnet-4)
            if model.starts(with: "claude-") && !model.contains("-thinking-") {
                needsMapping = true
            }
            
            // 2. Gemini-Claude models (e.g. gemini-claude-sonnet-4-5) - Optional: Enforce token budget?
            // For now, we trust Gemini native param, UNLESS it's the specific "thinking" variant
            if model.contains("gemini-claude-") && model.contains("-thinking") {
                 needsMapping = true
            }

            if needsMapping {
                 // Prefer specific request param, fallback to global setting
                 let reasoningLevel = (json["thinkingLevel"] as? String) ?? ModelRouter.shared.reasoningLevel
                 var budget = 16000 // Default Medium
                 
                 switch reasoningLevel {
                 case "low":
                     budget = 4096
                 case "high":
                     budget = 32000
                 default:
                     budget = 16000
                 }
                 
                 // Inject thinking param
                 json["thinking"] = [
                     "type": "enabled",
                     "budget_tokens": budget
                 ]
                 
                 // Adjust max_tokens to ensure headroom
                 let effectiveBudget = budget
                 let tokenHeadroom = max(ThinkingConfig.minimumHeadroom, Int(Double(effectiveBudget) * ThinkingConfig.headroomRatio))
                 let requiredMaxTokens = min(effectiveBudget + tokenHeadroom, ThinkingConfig.hardTokenCap)

                 json["max_tokens"] = requiredMaxTokens
                 
                 wasModified = true
                 NSLog("[ThinkingProxy] MAPPING APPLIED: %@ -> Budget: %d (Level: %@)", model, budget, reasoningLevel)
                 
                 if let modifiedData = try? JSONSerialization.data(withJSONObject: json),
                    let modifiedString = String(data: modifiedData, encoding: .utf8) {
                     return (modifiedString, true)
                 }
            }
            // --- MAPPING LOGIC END ---

            // For Gemini models (that didn't hit mapping), inject native thinkingLevel parameter
            if model.starts(with: "gemini-") {
                // Check if thinking is supported/enabled for this model
                if let config = ModelRouter.shared.matchModel(for: model), config.supportsThinking {
                    let reasoningLevel = ModelRouter.shared.reasoningLevel
                    json["thinkingLevel"] = reasoningLevel
                    NSLog("[ThinkingProxy] Injected Gemini thinkingLevel: %@", reasoningLevel)
                    wasModified = true
                }
            }
            
            // Return modified JSON if routing was applied
            if wasModified {
                if let modifiedData = try? JSONSerialization.data(withJSONObject: json),
                   let modifiedString = String(data: modifiedData, encoding: .utf8) {
                    
                    // CRITICAL FIX: If we switched to a known thinking fallback (like gemini-claude...), 
                    // we MUST return true for thinkingEnabled so the rate limiter knows to use the thinking fallback chain.
                    if model == "gemini-claude-sonnet-4-5-thinking" || model.contains("-thinking") {
                        return (modifiedString, true)
                    }
                    
                    return (modifiedString, false)
                }
            }
            
            // If it was a Claude model but no mapping/suffix handling applied, pass through
            if model.starts(with: "claude-") && !wasModified {
                 return (jsonString, false)
            }
        }
        
        // Check for thinking suffix pattern: -thinking-NUMBER
        let thinkingPrefix = "-thinking-"
        if let thinkingRange = model.range(of: thinkingPrefix, options: .backwards),
           thinkingRange.upperBound < model.endIndex {
            
            // Extract the number after "-thinking-"
            let budgetString = String(model[thinkingRange.upperBound...])
            
            // Strip the thinking suffix from model name regardless
            let cleanModel = String(model[..<thinkingRange.lowerBound])
            json["model"] = cleanModel
            
            // Only add thinking parameter if it's a valid integer
            if let budget = Int(budgetString), budget > 0 {
                let effectiveBudget = min(budget, ThinkingConfig.hardTokenCap - 1)
                if effectiveBudget != budget {
                    NSLog("[ThinkingProxy] Adjusted thinking budget from \(budget) to \(effectiveBudget) to stay within limits")
                }
                // Add thinking parameter
                json["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": effectiveBudget
                ]
                
                // Ensure max token limits are greater than the thinking budget
                // Claude requires: max_output_tokens (or legacy max_tokens) > thinking.budget_tokens
                let tokenHeadroom = max(ThinkingConfig.minimumHeadroom, Int(Double(effectiveBudget) * ThinkingConfig.headroomRatio))
                let desiredMaxTokens = effectiveBudget + tokenHeadroom
                var requiredMaxTokens = min(desiredMaxTokens, ThinkingConfig.hardTokenCap)
                if requiredMaxTokens <= effectiveBudget {
                    requiredMaxTokens = min(effectiveBudget + 1, ThinkingConfig.hardTokenCap)
                }
                
                let hasMaxOutputTokensField = json.keys.contains("max_output_tokens")
                var adjusted = false
                
                if let currentMaxTokens = json["max_tokens"] as? Int {
                    if currentMaxTokens <= effectiveBudget {
                        json["max_tokens"] = requiredMaxTokens
                    }
                    adjusted = true
                }
                
                if let currentMaxOutputTokens = json["max_output_tokens"] as? Int {
                    if currentMaxOutputTokens <= effectiveBudget {
                        json["max_output_tokens"] = requiredMaxTokens
                    }
                    adjusted = true
                }
                
                if !adjusted {
                    if hasMaxOutputTokensField {
                        json["max_output_tokens"] = requiredMaxTokens
                    } else {
                        json["max_tokens"] = requiredMaxTokens
                    }
                }
                
                NSLog("[ThinkingProxy] Transformed model '\(model)' → '\(cleanModel)' with thinking budget \(effectiveBudget)")
            } else {
                // Invalid number - just strip suffix and use vanilla model
                NSLog("[ThinkingProxy] Stripped invalid thinking suffix from '\(model)' → '\(cleanModel)' (no thinking)")
            }
            
            // Convert back to JSON
            if let modifiedData = try? JSONSerialization.data(withJSONObject: json),
               let modifiedString = String(data: modifiedData, encoding: .utf8) {
                return (modifiedString, true)
            }
        }
        
        return (jsonString, false)  // No transformation needed
    }
}
