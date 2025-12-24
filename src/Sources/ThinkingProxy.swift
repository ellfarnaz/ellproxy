import Foundation
import Network

/**
 A lightweight HTTP proxy that intercepts requests to add extended thinking parameters
 for Claude models based on model name suffixes.
 
 Model name pattern:
 - `*-thinking-NUMBER` → Custom token budget (e.g., claude-sonnet-4-5-20250929-thinking-5000)
 
 The proxy strips the suffix and adds the `thinking` parameter to the request body
 before forwarding to CLIProxyAPI.
 
 Examples:
 - claude-sonnet-4-5-20250929-thinking-2000 → 2,000 token budget
 - claude-sonnet-4-5-20250929-thinking-8000 → 8,000 token budget
 */
class ThinkingProxy {
    private var listener: NWListener?
    let proxyPort: UInt16 = 8317
    private let targetPort: UInt16 = 8318
    private let targetHost = "127.0.0.1"
    private(set) var isRunning = false
    private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.thinking-proxy-state")
    
    private enum Config {
        static let hardTokenCap = 32000
        static let minimumHeadroom = 1024
        static let headroomRatio = 0.1
    }
    
    /**
     Starts the thinking proxy server on port 8317
     */
    func start() {
        guard !isRunning else {
            NSLog("[ThinkingProxy] Already running")
            return
        }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            guard let port = NWEndpoint.Port(rawValue: proxyPort) else {
                NSLog("[ThinkingProxy] Invalid port: %d", proxyPort)
                return
            }
            listener = try NWListener(using: parameters, on: port)
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self?.isRunning = true
                    }
                    NSLog("[ThinkingProxy] Listening on port \(self?.proxyPort ?? 0)")
                case .failed(let error):
                    NSLog("[ThinkingProxy] Failed: \(error)")
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                case .cancelled:
                    NSLog("[ThinkingProxy] Cancelled")
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            
        } catch {
            NSLog("[ThinkingProxy] Failed to start: \(error)")
        }
    }
    
    /**
     Stops the thinking proxy server
     */
    func stop() {
        stateQueue.sync {
            guard isRunning else { return }
            
            listener?.cancel()
            listener = nil
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
            NSLog("[ThinkingProxy] Stopped")
        }
    }
    
    /**
     Handles an incoming connection from a client
     */
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(from: connection)
    }
    
    /**
     Receives the HTTP request from the client
     Accumulates data until full request is received (handles large payloads)
     */
    private func receiveRequest(from connection: NWConnection, accumulatedData: Data = Data()) {
        // Start the iterative receive loop
        receiveNextChunk(from: connection, accumulatedData: accumulatedData)
    }
    
    /**
     Receives request data iteratively (uses async scheduling instead of recursion to avoid stack buildup)
     */
    private func receiveNextChunk(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            var newAccumulatedData = accumulatedData
            newAccumulatedData.append(data)
            
            // Check if we have a complete HTTP request
            if let requestString = String(data: newAccumulatedData, encoding: .utf8),
               let headerEndRange = requestString.range(of: "\r\n\r\n") {
                
                // Extract Content-Length if present
                let headerEndIndex = requestString.distance(from: requestString.startIndex, to: headerEndRange.upperBound)
                let headerPart = String(requestString.prefix(headerEndIndex))
                
                if let contentLengthLine = headerPart.components(separatedBy: "\r\n").first(where: { $0.lowercased().starts(with: "content-length:") }) {
                    let contentLengthStr = contentLengthLine.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                    if let contentLength = Int(contentLengthStr) {
                        let bodyStartIndex = headerEndIndex
                        let currentBodyLength = newAccumulatedData.count - bodyStartIndex
                        
                        // If we haven't received the full body yet, schedule next iteration
                        if currentBodyLength < contentLength {
                            self.receiveNextChunk(from: connection, accumulatedData: newAccumulatedData)
                            return
                        }
                    }
                }
                
                // We have a complete request, process it
                self.processRequest(data: newAccumulatedData, connection: connection)
            } else if !isComplete {
                // Haven't found header end yet, schedule next iteration
                self.receiveNextChunk(from: connection, accumulatedData: newAccumulatedData)
            } else {
                // Complete but malformed, process what we have
                self.processRequest(data: newAccumulatedData, connection: connection)
            }
        }
    }
    
    /**
     Processes the HTTP request, modifies it if needed, and forwards to CLIProxyAPI
     */
    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendError(to: connection, statusCode: 400, message: "Invalid request")
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(to: connection, statusCode: 400, message: "Invalid request line")
            return
        }
        
        // Extract method, path, and HTTP version
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            sendError(to: connection, statusCode: 400, message: "Invalid request format")
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        let httpVersion = parts[2]

        // Collect headers while preserving original casing
        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            headers.append((name, value))
        }
        
        // Find the body start
        guard let bodyStartRange = requestString.range(of: "\r\n\r\n") else {
            NSLog("[ThinkingProxy] Error: Could not find body separator in request")
            sendError(to: connection, statusCode: 400, message: "Invalid request format - no body separator")
            return
        }
        
        let bodyStart = requestString.distance(from: requestString.startIndex, to: bodyStartRange.upperBound)
        let bodyString = String(requestString[requestString.index(requestString.startIndex, offsetBy: bodyStart)...])
        
        // Rewrite Amp CLI paths
        var rewrittenPath = path
        if path.starts(with: "/auth/cli-login") {
            rewrittenPath = "/api" + path
            NSLog("[ThinkingProxy] Rewriting Amp CLI login: \(path) -> \(rewrittenPath)")
        } else if path.starts(with: "/provider/") {
            // Rewrite /provider/* to /api/provider/*
            rewrittenPath = "/api" + path
            NSLog("[ThinkingProxy] Rewriting Amp provider path: \(path) -> \(rewrittenPath)")
        }
        
        // Check if this is an Amp management API request (not provider routes)
        // Management routes: /api/auth, /api/user, /api/meta, /api/threads, /api/telemetry, /api/internal
        // Provider routes like /api/provider/* should pass through to CLIProxyAPI
        if rewrittenPath.starts(with: "/api/") && !rewrittenPath.starts(with: "/api/provider/") {
            let ampPath = String(rewrittenPath.dropFirst(4)) // Remove "/api" prefix
            NSLog("[ThinkingProxy] Amp management request detected, forwarding to ampcode.com: \(ampPath)")
            forwardToAmp(method: method, path: ampPath, version: httpVersion, headers: headers, body: bodyString, originalConnection: connection)
            return
        }
        
        // Check if this is an Anthropic API request (Claude CLI uses this format)
        if rewrittenPath == "/v1/messages" && method == "POST" {
            NSLog("[ThinkingProxy] Anthropic API request detected, converting to OpenAI format")
            handleAnthropicRequest(headers: headers, body: bodyString, httpVersion: httpVersion, originalConnection: connection)
            return
        }
        
        // Try to parse and modify JSON body for POST requests
        var modifiedBody = bodyString
        var thinkingEnabled = false
        
        if method == "POST" && !bodyString.isEmpty {
            if let result = processThinkingParameter(jsonString: bodyString) {
                modifiedBody = result.0
                thinkingEnabled = result.1
            }
        }
        
        forwardRequest(method: method, path: rewrittenPath, version: httpVersion, headers: headers, body: modifiedBody, thinkingEnabled: thinkingEnabled, originalConnection: connection)
    }
    
    /**
     Processes the JSON body to add thinking parameter if model name has a thinking suffix,
     and applies model routing if enabled.
     Returns tuple of (modifiedJSON, needsTransformation)
     */
    private func processThinkingParameter(jsonString: String) -> (String, Bool)? {
        guard let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
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
    
    // MARK: - Anthropic API to OpenAI Conversion
    
    /**
     Handles Anthropic API requests (/v1/messages) by converting to OpenAI format
     and forwarding to CLIProxyAPI, then converting response back to Anthropic format
     */
    private func handleAnthropicRequest(headers: [(String, String)], body: String, httpVersion: String, originalConnection: NWConnection) {
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
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
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
    
    /**
     Forwards Amp API requests to ampcode.com, stripping the /api/ prefix
     */
    private func forwardToAmp(method: String, path: String, version: String, headers: [(String, String)], body: String, originalConnection: NWConnection) {
        // Create TLS parameters for HTTPS
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        
        // Create connection to ampcode.com:443
        let endpoint = NWEndpoint.hostPort(host: "ampcode.com", port: 443)
        let targetConnection = NWConnection(to: endpoint, using: parameters)
        
        targetConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Build the forwarded request
                var forwardedRequest = "\(method) \(path) \(version)\r\n"
                
                // Forward most headers, excluding some that need to be overridden
                let excludedHeaders: Set<String> = ["host", "content-length", "connection", "transfer-encoding"]
                for (name, value) in headers {
                    if !excludedHeaders.contains(name.lowercased()) {
                        forwardedRequest += "\(name): \(value)\r\n"
                    }
                }
                
                // Override Host header for ampcode.com
                forwardedRequest += "Host: ampcode.com\r\n"
                forwardedRequest += "Connection: close\r\n"
                
                let contentLength = body.utf8.count
                forwardedRequest += "Content-Length: \(contentLength)\r\n"
                forwardedRequest += "\r\n"
                forwardedRequest += body
                
                // Send to ampcode.com
                if let requestData = forwardedRequest.data(using: .utf8) {
                    targetConnection.send(content: requestData, completion: .contentProcessed({ error in
                        if let error = error {
                            NSLog("[ThinkingProxy] Send error to ampcode.com: \(error)")
                            targetConnection.cancel()
                            originalConnection.cancel()
                        } else {
                            // Receive response from ampcode.com and rewrite Location headers
                            self.receiveAmpResponse(from: targetConnection, originalConnection: originalConnection)
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Connection to ampcode.com failed: \(error)")
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway - Could not connect to ampcode.com")
                targetConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global(qos: .userInitiated))
    }
    
    /**
     Receives response from ampcode.com and rewrites Location headers to add /api/ prefix
     */
    private func receiveAmpResponse(from targetConnection: NWConnection, originalConnection: NWConnection) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive Amp response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Convert to string to rewrite headers
                if var responseString = String(data: data, encoding: .utf8) {
                    // Rewrite Location headers to prepend /api/
                    responseString = responseString.replacingOccurrences(
                        of: "\r\nlocation: /",
                        with: "\r\nlocation: /api/",
                        options: .caseInsensitive
                    )
                    responseString = responseString.replacingOccurrences(
                        of: "\r\nLocation: /",
                        with: "\r\nLocation: /api/"
                    )
                    
                    if let modifiedData = responseString.data(using: .utf8) {
                        originalConnection.send(content: modifiedData, completion: .contentProcessed({ sendError in
                            if let sendError = sendError {
                                NSLog("[ThinkingProxy] Send Amp response error: \(sendError)")
                            }
                            
                            if isComplete {
                                targetConnection.cancel()
                                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                                    originalConnection.cancel()
                                }))
                            } else {
                                // Continue receiving more data
                                self.receiveAmpResponse(from: targetConnection, originalConnection: originalConnection)
                            }
                        }))
                    }
                } else {
                    // Not UTF-8, forward as-is
                    originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                        if let sendError = sendError {
                            NSLog("[ThinkingProxy] Send Amp response error: \(sendError)")
                        }
                        
                        if isComplete {
                            targetConnection.cancel()
                            originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                                originalConnection.cancel()
                            }))
                        } else {
                            self.receiveAmpResponse(from: targetConnection, originalConnection: originalConnection)
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
    
    private enum BetaHeaders {
        static let interleavedThinking = "interleaved-thinking-2025-05-14"
    }
    
    /**
     Forwards the request to CLIProxyAPI on port 8318 (pass-through for non-thinking requests)
     */
    private func forwardRequest(method: String, path: String, version: String, headers: [(String, String)], body: String, thinkingEnabled: Bool = false, originalConnection: NWConnection, retryWithApiPrefix: Bool = false) {
        // Create connection to CLIProxyAPI
        guard let port = NWEndpoint.Port(rawValue: targetPort) else {
            NSLog("[ThinkingProxy] Invalid target port: %d", targetPort)
            sendError(to: originalConnection, statusCode: 500, message: "Internal Server Error")
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: port)
        let parameters = NWParameters.tcp
        let targetConnection = NWConnection(to: endpoint, using: parameters)
        
        targetConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Build the forwarded request
                var forwardedRequest = "\(method) \(path) \(version)\r\n"
                let excludedHeaders: Set<String> = ["content-length", "host", "transfer-encoding"]
                var existingBetaHeader: String? = nil
                
                for (name, value) in headers {
                    let lowercasedName = name.lowercased()
                    if excludedHeaders.contains(lowercasedName) {
                        continue
                    }
                    // Capture existing anthropic-beta header for merging
                    if lowercasedName == "anthropic-beta" {
                        existingBetaHeader = value
                        continue
                    }
                    forwardedRequest += "\(name): \(value)\r\n"
                }
                
                // Add/merge anthropic-beta header when thinking is enabled
                if thinkingEnabled {
                    var betaValue = BetaHeaders.interleavedThinking
                    if let existing = existingBetaHeader {
                        // Merge with existing header if not already present
                        if !existing.contains(BetaHeaders.interleavedThinking) {
                            betaValue = "\(existing),\(BetaHeaders.interleavedThinking)"
                        } else {
                            betaValue = existing
                        }
                    }
                    forwardedRequest += "anthropic-beta: \(betaValue)\r\n"
                    NSLog("[ThinkingProxy] Added interleaved thinking beta header")
                } else if let existing = existingBetaHeader {
                    // Pass through existing header when thinking not enabled
                    forwardedRequest += "anthropic-beta: \(existing)\r\n"
                }
                
                // Override Host header
                forwardedRequest += "Host: \(self.targetHost):\(self.targetPort)\r\n"
                // Always close connections - this proxy doesn't support keep-alive/pipelining
                forwardedRequest += "Connection: close\r\n"
                
                let contentLength = body.utf8.count
                forwardedRequest += "Content-Length: \(contentLength)\r\n"
                forwardedRequest += "\r\n"
                forwardedRequest += body
                
                // Send to CLIProxyAPI
                if let requestData = forwardedRequest.data(using: .utf8) {
                    targetConnection.send(content: requestData, completion: .contentProcessed({ error in
                        if let error = error {
                            NSLog("[ThinkingProxy] Send error: \(error)")
                            targetConnection.cancel()
                            originalConnection.cancel()
                        } else {
                            // Receive response from CLIProxyAPI (with 404 retry capability)
                            if retryWithApiPrefix {
                                self.receiveResponseWith404Retry(from: targetConnection, originalConnection: originalConnection, 
                                                                 method: method, path: path, version: version, 
                                                                 headers: headers, body: body)
                            } else {
                                self.receiveResponse(from: targetConnection, originalConnection: originalConnection)
                            }
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Target connection failed: \(error)")
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
                targetConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global(qos: .userInitiated))
    }
    
    /**
     Receives response and retries with /api/ prefix on 404
     */
    private func receiveResponseWith404Retry(from targetConnection: NWConnection, originalConnection: NWConnection, 
                                             method: String, path: String, version: String, 
                                             headers: [(String, String)], body: String) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Check if response is a 404
                if let responseString = String(data: data, encoding: .utf8) {
                    // Log first 200 chars to debug
                    let preview = String(responseString.prefix(200))
                    NSLog("[ThinkingProxy] Response preview for \(path): \(preview)")
                    
                    // Check for 404 in status line OR in body
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
                                              body: body, originalConnection: originalConnection, retryWithApiPrefix: false)
                            return
                        }
                    }
                }
                
                // Not a 404 or already has /api/, forward response as-is
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
    private func receiveResponse(from targetConnection: NWConnection, originalConnection: NWConnection) {
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
     Sends an error response to the client
     */
    private func sendError(to connection: NWConnection, statusCode: Int, message: String) {
        // Build response with proper CRLF line endings and correct byte count
        guard let bodyData = message.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        let headers = "HTTP/1.1 \(statusCode) \(message)\r\n" +
                     "Content-Type: text/plain\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
                     "Connection: close\r\n" +
                     "\r\n"
        
        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        var responseData = Data()
        responseData.append(headerData)
        responseData.append(bodyData)
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
