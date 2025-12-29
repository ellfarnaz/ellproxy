import Foundation

/// Processes thinking parameter transformation for Claude models
class ThinkingProcessor {
    
    /// Configuration constants
    private enum Config {
        static let hardTokenCap = ThinkingConfig.hardTokenCap
        static let minimumHeadroom = ThinkingConfig.minimumHeadroom
        static let headroomRatio = ThinkingConfig.headroomRatio
    }
    
    /**
     Processes the JSON body to add thinking parameter if model name has a thinking suffix,
     and applies model routing if enabled.
     Returns tuple of (modifiedJSON, needsTransformation)
     */
    func processThinkingParameter(jsonString: String) -> (String, Bool)? {
        guard let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? JSONDictionary,
              var model = json["model"] as? String else {
            return nil
        }
        
        var wasModified = false
        
        // Apply model routing if enabled
        let routedModel = ModelRouter.shared.rewriteModel(requestedModel: model)
        if routedModel != model {
            json["model"] = routedModel
            model = routedModel
            wasModified = true
            NSLog("[ThinkingProxy] Model routing: applied route to '%@'", routedModel)
        }
        
        // Only process Claude models with thinking suffix
        guard model.starts(with: "claude-") else {
            // Return modified JSON if routing was applied
            if wasModified {
                if let modifiedData = try? JSONSerialization.data(withJSONObject: json),
                   let modifiedString = String(data: modifiedData, encoding: .utf8) {
                    return (modifiedString, false)
                }
            }
            return (jsonString, false)  // Not Claude, pass through
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
                let effectiveBudget = min(budget, Config.hardTokenCap - 1)
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
                let tokenHeadroom = max(Config.minimumHeadroom, Int(Double(effectiveBudget) * Config.headroomRatio))
                let desiredMaxTokens = effectiveBudget + tokenHeadroom
                var requiredMaxTokens = min(desiredMaxTokens, Config.hardTokenCap)
                if requiredMaxTokens <= effectiveBudget {
                    requiredMaxTokens = min(effectiveBudget + 1, Config.hardTokenCap)
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
