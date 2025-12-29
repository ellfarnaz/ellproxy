import Foundation
import Network

// MARK: - Response Handling
extension ThinkingProxy {
    
    /**
     Receives response and inspects for errors (404, 429) to trigger retries/fallbacks
     */
    func receiveResponseWithInspection(from targetConnection: NWConnection, originalConnection: NWConnection, 
                                             method: String, path: String, version: String, 
                                             headers: [(String, String)], body: String, 
                                             thinkingEnabled: Bool = false, retryCount: Int = 0) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Parse headers to check status code
                if let responseString = String(data: data, encoding: .utf8) {
                    // Check for 404 (Not Found)
                    let is404 = responseString.contains("HTTP/1.1 404") || 
                               responseString.contains("HTTP/1.0 404") ||
                               responseString.contains("404 page not found")
                    
                    if is404 {
                        // Check if path doesn't already start with /api/
                        if !path.starts(with: "/api/") && !path.starts(with: "/v1/") {
                            NSLog("[ThinkingProxy] Got 404 for \(path), retrying with /api prefix")
                            targetConnection.cancel()
                            
                            // Retry with /api/ prefix
                            let newPath = "/api" + path
                            self.forwardRequest(method: method, path: newPath, version: version, headers: headers, 
                                              body: body, thinkingEnabled: thinkingEnabled, originalConnection: originalConnection, retryWithApiPrefix: false, retryCount: retryCount)
                            return
                        }
                    }
                    
                    // Check for 429 (Rate Limit)
                    let is429 = responseString.contains("HTTP/1.1 429") || responseString.contains("HTTP/1.0 429")
                    
                    // DUAL-TRACK FALLBACK LOGIC:
                    // - Thinking Request: try Fallback Thinking first, then Fallback Model
                    // - Non-Thinking Request: try Fallback Model
                    let maxRetries = thinkingEnabled ? 2 : 1
                    
                    if is429 && retryCount < maxRetries {
                        NSLog("[ThinkingProxy] 429 Rate Limit. Retry: \(retryCount + 1)/\(maxRetries)")
                        
                        var fallbackId: String?
                        var isThinkingFallback = false
                        
                        if thinkingEnabled {
                            if retryCount == 0 {
                                // First retry: Use user-configured Fallback Thinking
                                let fallbackThinkingId = ModelRouter.shared.fallbackThinkingModelId
                                if !fallbackThinkingId.isEmpty {
                                    fallbackId = fallbackThinkingId
                                    isThinkingFallback = true
                                    NSLog("[ThinkingProxy] DUAL-TRACK: Trying Fallback Thinking: \(fallbackId!)")
                                } else {
                                    // No fallback thinking configured, skip to default fallback
                                    fallbackId = ModelRouter.shared.fallbackModelId.isEmpty ? nil : ModelRouter.shared.fallbackModelId
                                    NSLog("[ThinkingProxy] DUAL-TRACK: No Fallback Thinking configured. Skipping to Default Fallback.")
                                }
                            } else {
                                // Second retry: Use standard Fallback Model
                                fallbackId = ModelRouter.shared.fallbackModelId.isEmpty ? nil : ModelRouter.shared.fallbackModelId
                                NSLog("[ThinkingProxy] DUAL-TRACK: Fallback Thinking exhausted. Switching to Default Fallback: \(fallbackId ?? "none")")
                            }
                        } else {
                            // Non-thinking request: use standard Fallback Model
                            fallbackId = ModelRouter.shared.fallbackModelId.isEmpty ? nil : ModelRouter.shared.fallbackModelId
                        }
                        
                        if let targetId = fallbackId {
                            // Parse original body to replace model
                            if let bodyData = body.data(using: .utf8),
                               var json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                                
                                // Get fallback model config
                                let fallbackParams = ModelRouter.shared.models.first(where: { $0.id == targetId })
                                let targetModelId = fallbackParams?.upstreamModel ?? targetId
                                
                                json["model"] = targetModelId
                                
                                // If thinking fallback: keep thinking params
                                // If standard fallback: strip thinking if not supported
                                if isThinkingFallback {
                                    if json["thinking"] == nil {
                                        json["thinking"] = ["type": "enabled", "budget_tokens": 16000]
                                    }
                                } else {
                                    if let config = fallbackParams, !config.supportsThinking {
                                        json.removeValue(forKey: "thinking")
                                    }
                                }
                                
                                if let newBodyData = try? JSONSerialization.data(withJSONObject: json),
                                   let newBody = String(data: newBodyData, encoding: .utf8) {
                                    
                                    let message = isThinkingFallback 
                                        ? "Rate Limit! Trying Thinking Backup: \(fallbackParams?.name ?? targetId)"
                                        : "Rate Limit! Switched to Default: \(fallbackParams?.name ?? targetId)"
                                        
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(
                                            name: .init("routingNotification"),
                                            object: nil,
                                            userInfo: ["message": message]
                                        )
                                    }
                                    
                                    targetConnection.cancel()
                                    // Retry with new body
                                    self.forwardRequest(method: method, path: path, version: version, headers: headers, 
                                                      body: newBody, thinkingEnabled: isThinkingFallback || (fallbackParams?.supportsThinking ?? false),
                                                      originalConnection: originalConnection, retryWithApiPrefix: false, retryCount: retryCount + 1)
                                    return
                                }
                            }
                        }
                    }
                }
                
                // Normal forwarding
                // Check for SSE stream to transform reasoning_content -> content
                let isSSE = headers.contains { $0.0.lowercased() == "content-type" && $0.1.lowercased().contains("text/event-stream") }
                
                if isSSE && thinkingEnabled {
                    // Use transformer stream
                    self.streamNextChunkWithTransformation(from: targetConnection, to: originalConnection)
                } else {
                    // Standard stream
                    originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                        if let sendError = sendError {
                            NSLog("[ThinkingProxy] Send error: \(sendError)")
                        }
                        
                        if isComplete {
                            targetConnection.cancel()
                            originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                                originalConnection.cancel()
                            }))
                        } else {
                            // Continue streaming
                            self.streamNextChunk(from: targetConnection, to: originalConnection)
                        }
                    }))
                }
            } else if isComplete {
                targetConnection.cancel()
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }
    
    /**
     Receives response from CLIProxyAPI
     Starts the streaming loop for response data
     */
    func receiveResponse(from targetConnection: NWConnection, originalConnection: NWConnection) {
        // Start the streaming loop
        streamNextChunk(from: targetConnection, to: originalConnection)
    }
    
    /**
     Streams response chunks iteratively (uses async scheduling instead of recursion to avoid stack buildup)
     */
    private func streamNextChunk(from targetConnection: NWConnection, to originalConnection: NWConnection) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Forward response chunk to original client
                originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                    if let sendError = sendError {
                        NSLog("[ThinkingProxy] Send response error: \(sendError)")
                    }
                    
                    if isComplete {
                        targetConnection.cancel()
                        // Always close client connection - no keep-alive/pipelining support
                        originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                            originalConnection.cancel()
                        }))
                    } else {
                        // Schedule next iteration of the streaming loop
                        self.streamNextChunk(from: targetConnection, to: originalConnection)
                    }
                }))
            } else if isComplete {
                targetConnection.cancel()
                // Always close client connection - no keep-alive/pipelining support
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }
    
    /**
     Streams SSE chunks and replaces "reasoning_content" with "content" so typical clients display it
     */
    /**
     Streams SSE chunks and replicates "reasoning_content" into "content" using robust JSON parsing
     to ensure correct spacing and escaping.
     Also caches the accumulated reasoning_content for replay in subsequent requests.
     */
    private func streamNextChunkWithTransformation(from targetConnection: NWConnection, to originalConnection: NWConnection,
                                                    accumulatedReasoning: String = "", accumulatedContent: String = "") {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            var currentReasoning = accumulatedReasoning
            var currentContent = accumulatedContent
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                var finalData = data
                
                // Decode chunk to string (utf8)
                if let stringData = String(data: data, encoding: .utf8) {
                    var modifiedString = ""
                    let lines = stringData.components(separatedBy: "\n")
                    
                    for (index, line) in lines.enumerated() {
                        // Check if line is an SSE data event
                        if line.starts(with: "data: ") {
                            let jsonString = String(line.dropFirst(6)) // Remove "data: "
                            
                            // Skip special messages like [DONE]
                            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                                // Stream complete - cache the accumulated reasoning if we have both
                                if !currentContent.isEmpty && !currentReasoning.isEmpty {
                                    ReasoningCache.shared.store(content: currentContent, reasoning: currentReasoning)
                                    NSLog("[ThinkingProxy] 💾 Cached reasoning for content (len: \(currentContent.prefix(50))...)")
                                }
                                modifiedString += line
                            } else if let jsonData = jsonString.data(using: .utf8),
                                      var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                
                                // Check deeply for choices[0].delta.reasoning_content
                                if let choices = json["choices"] as? [[String: Any]],
                                   !choices.isEmpty,
                                   var delta = choices[0]["delta"] as? [String: Any],
                                   let reasoningContent = delta["reasoning_content"] as? String {
                                    
                                    // Found reasoning content - accumulate for caching
                                    currentReasoning += reasoningContent
                                    
                                    // Also duplicate it into "content" so standard clients display it
                                    delta["content"] = reasoningContent
                                    
                                    // Reconstruct JSON hierarchy
                                    var newChoices = choices
                                    var newChoice = newChoices[0]
                                    newChoice["delta"] = delta
                                    newChoices[0] = newChoice
                                    json["choices"] = newChoices
                                    
                                    // Re-serialize
                                    if let newData = try? JSONSerialization.data(withJSONObject: json),
                                       let newJsonString = String(data: newData, encoding: .utf8) {
                                        modifiedString += "data: " + newJsonString
                                    } else {
                                        modifiedString += line // Fallback if serialization fails
                                    }
                                } else {
                                    // No reasoning content - might have regular content, accumulate it
                                    if let choices = json["choices"] as? [[String: Any]],
                                       !choices.isEmpty,
                                       let delta = choices[0]["delta"] as? [String: Any],
                                       let content = delta["content"] as? String {
                                        currentContent += content
                                    }
                                    modifiedString += line
                                }
                            } else {
                                modifiedString += line // Not valid JSON or parse error
                            }
                        } else {
                            modifiedString += line // Not a data line
                        }
                        
                        // Add newline back if it wasn't the last line
                        if index < lines.count - 1 {
                            modifiedString += "\n"
                        }
                    }
                    
                    if let newData = modifiedString.data(using: .utf8) {
                        finalData = newData
                    }
                }
                
                // Forward transformed chunk
                originalConnection.send(content: finalData, completion: .contentProcessed({ sendError in
                    if let sendError = sendError {
                        NSLog("[ThinkingProxy] Send response error: \(sendError)")
                    }
                    
                    if isComplete {
                        // Stream complete - cache if we have accumulated data
                        if !currentContent.isEmpty && !currentReasoning.isEmpty {
                            ReasoningCache.shared.store(content: currentContent, reasoning: currentReasoning)
                            NSLog("[ThinkingProxy] 💾 Final cache: reasoning for content (len: \(currentContent.count))")
                        }
                        targetConnection.cancel()
                        originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                            originalConnection.cancel()
                        }))
                    } else {
                        // Continue streaming with accumulated values
                        self.streamNextChunkWithTransformation(from: targetConnection, to: originalConnection,
                                                               accumulatedReasoning: currentReasoning, accumulatedContent: currentContent)
                    }
                }))
            } else if isComplete {
                targetConnection.cancel()
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }
}
