import Foundation
import Network

// MARK: - Anthropic API to OpenAI Conversion
extension ThinkingProxy {
    
    /**
     Handles Anthropic API requests (/v1/messages) by converting to OpenAI format
     and forwarding to CLIProxyAPI, then converting response back to Anthropic format
     */
    func handleAnthropicRequest(headers: [(String, String)], body: String, httpVersion: String, originalConnection: NWConnection) {
        guard let jsonData = body.data(using: .utf8),
              let anthropicRequest = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            NSLog("[ThinkingProxy] Failed to parse Anthropic request body")
            sendError(to: originalConnection, statusCode: 400, message: "Invalid JSON body")
            return
        }
        
        // Convert Anthropic request to OpenAI format
        guard let openAIRequest = convertAnthropicToOpenAI(anthropicRequest) else {
            NSLog("[ThinkingProxy] Failed to convert Anthropic request to OpenAI format")
            sendError(to: originalConnection, statusCode: 400, message: "Failed to convert request format")
            return
        }
        
        // Check if streaming is requested
        let isStreaming = anthropicRequest["stream"] as? Bool ?? false
        
        // Serialize OpenAI request
        guard let openAIData = try? JSONSerialization.data(withJSONObject: openAIRequest),
              let openAIBody = String(data: openAIData, encoding: .utf8) else {
            sendError(to: originalConnection, statusCode: 500, message: "Failed to serialize request")
            return
        }
        
        NSLog("[ThinkingProxy] Converted Anthropic request to OpenAI format, streaming: \(isStreaming)")
        
        // Forward to CLIProxyAPI with OpenAI format
        forwardAnthropicAsOpenAI(
            openAIBody: openAIBody,
            httpVersion: httpVersion,
            headers: headers,
            isStreaming: isStreaming,
            originalConnection: originalConnection
        )
    }
    
    /**
     Converts Anthropic API request format to OpenAI format
     */
    private func convertAnthropicToOpenAI(_ anthropic: [String: Any]) -> [String: Any]? {
        var openAI: [String: Any] = [:]
        
        // Model - apply routing if enabled
        if var model = anthropic["model"] as? String {
            let routedModel = ModelRouter.shared.rewriteModel(requestedModel: model)
            if routedModel != model {
                NSLog("[ThinkingProxy] Anthropic model routing: '%@' → '%@'", model, routedModel)
                model = routedModel
            }
            openAI["model"] = model
        }
        
        // Convert messages
        var openAIMessages: [[String: Any]] = []
        
        // Handle system prompt (Anthropic has it at top level)
        if let systemPrompt = anthropic["system"] as? String {
            openAIMessages.append(["role": "system", "content": systemPrompt])
        } else if let systemArray = anthropic["system"] as? [[String: Any]] {
            // System can also be an array of content blocks
            var systemText = ""
            for block in systemArray {
                if let text = block["text"] as? String {
                    systemText += text + "\n"
                }
            }
            if !systemText.isEmpty {
                openAIMessages.append(["role": "system", "content": systemText.trimmingCharacters(in: .whitespacesAndNewlines)])
            }
        }
        
        // Convert messages array
        if let messages = anthropic["messages"] as? [[String: Any]] {
            for msg in messages {
                guard let role = msg["role"] as? String else { continue }
                
                var openAIMsg: [String: Any] = ["role": role]
                
                // Handle content (can be string or array of content blocks)
                if let content = msg["content"] as? String {
                    openAIMsg["content"] = content
                } else if let contentArray = msg["content"] as? [[String: Any]] {
                    // Convert content blocks to OpenAI format
                    var openAIContent: [[String: Any]] = []
                    for block in contentArray {
                        if let blockType = block["type"] as? String {
                            switch blockType {
                            case "text":
                                if let text = block["text"] as? String {
                                    openAIContent.append(["type": "text", "text": text])
                                }
                            case "image":
                                // Handle image blocks
                                if let source = block["source"] as? [String: Any],
                                   let mediaType = source["media_type"] as? String,
                                   let data = source["data"] as? String {
                                    openAIContent.append([
                                        "type": "image_url",
                                        "image_url": ["url": "data:\(mediaType);base64,\(data)"]
                                    ])
                                }
                            case "tool_use":
                                // Tool use blocks - convert to tool_calls format
                                if let id = block["id"] as? String,
                                   let name = block["name"] as? String {
                                    let input = block["input"] ?? [:]
                                    let inputJSON = (try? JSONSerialization.data(withJSONObject: input))
                                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                    openAIMsg["tool_calls"] = [[
                                        "id": id,
                                        "type": "function",
                                        "function": ["name": name, "arguments": inputJSON]
                                    ]]
                                }
                            case "tool_result":
                                // Tool results - need special handling
                                if let toolUseId = block["tool_use_id"] as? String {
                                    openAIMsg["role"] = "tool"
                                    openAIMsg["tool_call_id"] = toolUseId
                                    if let content = block["content"] as? String {
                                        openAIMsg["content"] = content
                                    } else if let contentArr = block["content"] as? [[String: Any]] {
                                        var resultText = ""
                                        for c in contentArr {
                                            if let t = c["text"] as? String { resultText += t }
                                        }
                                        openAIMsg["content"] = resultText
                                    }
                                }
                            default:
                                break
                            }
                        }
                    }
                    if !openAIContent.isEmpty {
                        openAIMsg["content"] = openAIContent
                    }
                }
                
                // CRITICAL: Inject reasoning_content for assistant messages
                // DeepSeek Thinking Mode requires this field in ALL assistant messages
                if role == "assistant" {
                    openAIMsg["reasoning_content"] = ReasoningCache.shared.retrieve(for: (openAIMsg["content"] as? String) ?? "") 
                        ?? "I analyzed the request carefully before responding."
                    NSLog("[ThinkingProxy] 💉 Injected reasoning_content for assistant in Anthropic conversion")
                }
                
                openAIMessages.append(openAIMsg)
            }
        }
        
        openAI["messages"] = openAIMessages
        
        // Max tokens
        if let maxTokens = anthropic["max_tokens"] as? Int {
            openAI["max_tokens"] = maxTokens
        }
        
        // Temperature
        if let temp = anthropic["temperature"] as? Double {
            openAI["temperature"] = temp
        }
        
        // Top P
        if let topP = anthropic["top_p"] as? Double {
            openAI["top_p"] = topP
        }
        
        // Streaming
        if let stream = anthropic["stream"] as? Bool {
            openAI["stream"] = stream
        }
        
        // Stop sequences
        if let stop = anthropic["stop_sequences"] as? [String] {
            openAI["stop"] = stop
        }
        
        // Tools conversion
        if let tools = anthropic["tools"] as? [[String: Any]] {
            var openAITools: [[String: Any]] = []
            for tool in tools {
                if let name = tool["name"] as? String {
                    var funcDef: [String: Any] = ["name": name]
                    if let desc = tool["description"] as? String {
                        funcDef["description"] = desc
                    }
                    if let inputSchema = tool["input_schema"] as? [String: Any] {
                        funcDef["parameters"] = inputSchema
                    }
                    openAITools.append(["type": "function", "function": funcDef])
                }
            }
            if !openAITools.isEmpty {
                openAI["tools"] = openAITools
            }
        }
        
        return openAI
    }
    
    /**
     Forwards converted request to CLIProxyAPI and converts response back to Anthropic format
     */
    private func forwardAnthropicAsOpenAI(openAIBody: String, httpVersion: String, headers: [(String, String)], isStreaming: Bool, originalConnection: NWConnection) {
        guard let port = NWEndpoint.Port(rawValue: targetPort) else {
            sendError(to: originalConnection, statusCode: 500, message: "Internal Server Error")
            return
        }
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: port)
        let parameters = NWParameters.tcp
        let targetConnection = NWConnection(to: endpoint, using: parameters)
        
        targetConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                // Build OpenAI format request
                var request = "POST /v1/chat/completions \(httpVersion)\r\n"
                request += "Host: \(self.targetHost):\(self.targetPort)\r\n"
                request += "Content-Type: application/json\r\n"
                request += "Connection: close\r\n"
                
                // Forward authorization header
                for (name, value) in headers {
                    if name.lowercased() == "authorization" || name.lowercased() == "x-api-key" {
                        request += "Authorization: \(value)\r\n"
                        break
                    }
                }
                
                request += "Content-Length: \(openAIBody.utf8.count)\r\n"
                request += "\r\n"
                request += openAIBody
                
                if let requestData = request.data(using: .utf8) {
                    targetConnection.send(content: requestData, completion: .contentProcessed({ error in
                        if let error = error {
                            NSLog("[ThinkingProxy] Anthropic forward error: \(error)")
                            targetConnection.cancel()
                            originalConnection.cancel()
                        } else {
                            if isStreaming {
                                self.receiveOpenAIStreamingResponse(from: targetConnection, originalConnection: originalConnection)
                            } else {
                                self.receiveOpenAIResponse(from: targetConnection, originalConnection: originalConnection)
                            }
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Anthropic target connection failed: \(error)")
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
                targetConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global(qos: .userInitiated))
    }
    
    /**
     Receives non-streaming OpenAI response and converts to Anthropic format
     */
    private func receiveOpenAIResponse(from targetConnection: NWConnection, originalConnection: NWConnection, accumulatedData: Data = Data()) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive OpenAI response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            var newData = accumulatedData
            if let data = data {
                newData.append(data)
            }
            
            if isComplete {
                targetConnection.cancel()
                
                // Parse and convert the complete response
                if let responseString = String(data: newData, encoding: .utf8) {
                    // Find the JSON body (after headers)
                    if let bodyRange = responseString.range(of: "\r\n\r\n") {
                        let bodyStart = responseString[bodyRange.upperBound...]
                        if let jsonData = String(bodyStart).data(using: .utf8),
                           let openAIResponse = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let anthropicResponse = self.convertOpenAIToAnthropic(openAIResponse) {
                            
                            // Send Anthropic format response
                            self.sendAnthropicResponse(anthropicResponse, to: originalConnection)
                            return
                        }
                    }
                }
                
                // Fallback: forward raw response
                originalConnection.send(content: newData, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            } else {
                // Continue receiving
                self.receiveOpenAIResponse(from: targetConnection, originalConnection: originalConnection, accumulatedData: newData)
            }
        }
    }
    
    /**
     Receives streaming OpenAI response and converts to Anthropic SSE format
     */
    private func receiveOpenAIStreamingResponse(from targetConnection: NWConnection, originalConnection: NWConnection, headersSent: Bool = false, buffer: String = "") {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive streaming response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            var currentHeadersSent = headersSent
            var currentBuffer = buffer
            
            if let data = data, !data.isEmpty {
                if let chunk = String(data: data, encoding: .utf8) {
                    // If headers not sent yet, find and send them
                    if !currentHeadersSent {
                        if let headerEnd = chunk.range(of: "\r\n\r\n") {
                            // Send Anthropic-style headers
                            let headers = "HTTP/1.1 200 OK\r\n" +
                                        "Content-Type: text/event-stream\r\n" +
                                        "Cache-Control: no-cache\r\n" +
                                        "Connection: close\r\n" +
                                        "\r\n"
                            
                            // Send message_start event first
                            let messageStart = self.createAnthropicMessageStart()
                            let startEvent = "event: message_start\ndata: \(messageStart)\n\n"
                            
                            if let headerData = (headers + startEvent).data(using: .utf8) {
                                originalConnection.send(content: headerData, completion: .contentProcessed({ _ in }))
                            }
                            
                            currentHeadersSent = true
                            currentBuffer = String(chunk[headerEnd.upperBound...])
                        } else {
                            currentBuffer += chunk
                        }
                    } else {
                        currentBuffer += chunk
                    }
                    
                    // Process SSE events in buffer
                    let (processedBuffer, events) = self.parseSSEEvents(currentBuffer)
                    currentBuffer = processedBuffer
                    
                    // Convert and forward each event
                    for event in events {
                        if let anthropicEvent = self.convertOpenAIStreamEventToAnthropic(event) {
                            if let eventData = anthropicEvent.data(using: .utf8) {
                                originalConnection.send(content: eventData, completion: .contentProcessed({ _ in }))
                            }
                        }
                    }
                }
            }
            
            if isComplete {
                targetConnection.cancel()
                
                // Send message_stop event
                let stopEvent = "event: message_stop\ndata: {\"type\": \"message_stop\"}\n\n"
                if let stopData = stopEvent.data(using: .utf8) {
                    originalConnection.send(content: stopData, completion: .contentProcessed({ _ in
                        originalConnection.cancel()
                    }))
                } else {
                    originalConnection.cancel()
                }
            } else {
                self.receiveOpenAIStreamingResponse(from: targetConnection, originalConnection: originalConnection, headersSent: currentHeadersSent, buffer: currentBuffer)
            }
        }
    }
    
    /**
     Parses SSE events from buffer, returns remaining buffer and parsed events
     */
    private func parseSSEEvents(_ buffer: String) -> (String, [String]) {
        var events: [String] = []
        var remaining = buffer
        
        while let range = remaining.range(of: "\n\n") {
            let event = String(remaining[..<range.lowerBound])
            events.append(event)
            remaining = String(remaining[range.upperBound...])
        }
        
        return (remaining, events)
    }
    
    /**
     Creates Anthropic message_start event
     */
    private func createAnthropicMessageStart() -> String {
        let msg: [String: Any] = [
            "type": "message_start",
            "message": [
                "id": "msg_\(UUID().uuidString.prefix(24))",
                "type": "message",
                "role": "assistant",
                "content": [],
                "model": ModelRouter.shared.activeModel?.upstreamModel ?? "unknown",
                "stop_reason": NSNull(),
                "stop_sequence": NSNull(),
                "usage": ["input_tokens": 0, "output_tokens": 0]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: msg))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    
    /**
     Converts OpenAI streaming event to Anthropic format
     */
    private func convertOpenAIStreamEventToAnthropic(_ event: String) -> String? {
        // Parse data line
        guard let dataLine = event.components(separatedBy: "\n").first(where: { $0.starts(with: "data: ") }) else {
            return nil
        }
        
        let jsonStr = String(dataLine.dropFirst(6)) // Remove "data: "
        
        if jsonStr == "[DONE]" {
            return nil // Will send message_stop separately
        }
        
        guard let jsonData = jsonStr.data(using: .utf8),
              let openAI = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = openAI["choices"] as? [[String: Any]],
              let choice = choices.first,
              let delta = choice["delta"] as? [String: Any] else {
            return nil
        }
        
        // Convert to Anthropic content_block_delta
        if let content = delta["content"] as? String, !content.isEmpty {
            let anthropic: [String: Any] = [
                "type": "content_block_delta",
                "index": 0,
                "delta": [
                    "type": "text_delta",
                    "text": content
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: anthropic),
               let str = String(data: data, encoding: .utf8) {
                return "event: content_block_delta\ndata: \(str)\n\n"
            }
        }
        
        return nil
    }
    
    /**
     Converts OpenAI response to Anthropic format
     */
    private func convertOpenAIToAnthropic(_ openAI: [String: Any]) -> [String: Any]? {
        var anthropic: [String: Any] = [
            "id": "msg_\(UUID().uuidString.prefix(24))",
            "type": "message",
            "role": "assistant",
            "model": openAI["model"] as? String ?? "unknown"
        ]
        
        // Convert choices to content
        var content: [[String: Any]] = []
        if let choices = openAI["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any] {
                    // Text content
                    if let text = message["content"] as? String {
                        content.append(["type": "text", "text": text])
                    }
                    
                    // Tool calls
                    if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                        for tc in toolCalls {
                            if let id = tc["id"] as? String,
                               let function = tc["function"] as? [String: Any],
                               let name = function["name"] as? String {
                                var input: Any = [:]
                                if let args = function["arguments"] as? String,
                                   let argsData = args.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: argsData) {
                                    input = parsed
                                }
                                content.append([
                                    "type": "tool_use",
                                    "id": id,
                                    "name": name,
                                    "input": input
                                ])
                            }
                        }
                    }
                }
                
                // Stop reason
                if let finishReason = choice["finish_reason"] as? String {
                    switch finishReason {
                    case "stop": anthropic["stop_reason"] = "end_turn"
                    case "length": anthropic["stop_reason"] = "max_tokens"
                    case "tool_calls": anthropic["stop_reason"] = "tool_use"
                    default: anthropic["stop_reason"] = finishReason
                    }
                }
            }
        }
        
        anthropic["content"] = content
        
        // Usage
        if let usage = openAI["usage"] as? [String: Any] {
            anthropic["usage"] = [
                "input_tokens": usage["prompt_tokens"] ?? 0,
                "output_tokens": usage["completion_tokens"] ?? 0
            ]
        }
        
        return anthropic
    }
    
    /**
     Sends Anthropic format response
     */
    private func sendAnthropicResponse(_ response: [String: Any], to connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response) else {
            sendError(to: connection, statusCode: 500, message: "Failed to serialize response")
            return
        }
        
        let headers = "HTTP/1.1 200 OK\r\n" +
                     "Content-Type: application/json\r\n" +
                     "Content-Length: \(jsonData.count)\r\n" +
                     "Connection: close\r\n" +
                     "\r\n"
        
        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        var responseData = Data()
        responseData.append(headerData)
        responseData.append(jsonData)
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
