import Foundation
import Network

extension Notification.Name {
    static let fallbackTriggered = Notification.Name("fallbackTriggered")
}

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
    let proxyPort: UInt16 = AppConfig.ellProxyPort
    let targetPort: UInt16 = AppConfig.targetPort
    let targetHost = AppConfig.targetHost
    private(set) var isRunning = false
    private let stateQueue = DispatchQueue(label: "io.automaze.ellproxy.thinking-proxy-state")
    
    private enum Config {
        static let hardTokenCap = ThinkingConfig.hardTokenCap
        static let minimumHeadroom = ThinkingConfig.minimumHeadroom
        static let headroomRatio = ThinkingConfig.headroomRatio
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
     Processes the HTTP request, modifies it if needed, and forwards to CLIProxyAPI
     */
    func processRequest(data: Data, connection: NWConnection) {
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
        } else if !path.starts(with: "/v1/") && !path.starts(with: "/api/") {
            // Normalize paths for OpenCode and other clients (e.g., /chat/completions -> /v1/chat/completions)
            if path.starts(with: "/chat/completions") || path.starts(with: "/completions") || path.starts(with: "/messages") {
                rewrittenPath = "/v1" + path
                NSLog("[ThinkingProxy] Normalizing path for OpenCode: \(path) -> \(rewrittenPath)")
            }
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
        // IMPORTANT: Do this BEFORE any JSON modification to preserve Anthropic image format
        if rewrittenPath == "/v1/messages" && method == "POST" {
            NSLog("[ThinkingProxy] Anthropic API request detected, converting to OpenAI format")
            handleAnthropicRequest(headers: headers, body: bodyString, httpVersion: httpVersion, originalConnection: connection)
            return
        }
        
        // Check for sync test header and provider
        let isSyncTest = headers.contains { $0.0.lowercased() == "x-ellproxy-test" }
        let providerName = headers.first { $0.0.lowercased() == "x-ellproxy-provider" }?.1
        
        if isSyncTest {
             NSLog("[ThinkingProxy] Sync Test detected via header (Provider: %@)", providerName ?? "Unknown")
        }

        // Try to parse and modify JSON body for POST requests (NON-Anthropic only)
        var modifiedBody = bodyString
        var thinkingEnabled = false
        
        if method == "POST" && !bodyString.isEmpty {
            // Normalize image content formats (OpenCode, Trae, etc.)
            if let normalized = normalizeImageContent(in: bodyString) {
                modifiedBody = normalized
            }
            
            modifiedBody = fixOpenCodePayload(jsonString: modifiedBody)
            
            // Fix DeepSeek/Thinking missing reasoning_content error (400)
            // Clients like Droid/OpenAI SDKs drop unknown fields, causing validation errors on next turn
            modifiedBody = injectDummyReasoningContent(jsonString: modifiedBody)
            
            // VERIFY injection worked by re-parsing
            if let verifyData = modifiedBody.data(using: .utf8),
               let verifyJson = try? JSONSerialization.jsonObject(with: verifyData) as? [String: Any],
               let verifyMessages = verifyJson["messages"] as? [[String: Any]] {
                NSLog("[ThinkingProxy] 🔍 VERIFICATION: Re-checking messages AFTER injection (\(verifyMessages.count) total)")
                for (i, msg) in verifyMessages.enumerated() {
                    let role = msg["role"] as? String ?? "unknown"
                    let hasReasoning = msg["reasoning_content"] != nil
                    if role == "assistant" {
                        NSLog("[ThinkingProxy] 🔍 VERIFY Message[\(i)]: role=\(role), hasReasoning=\(hasReasoning)")
                    }
                }
            }
            
            // DEBUG LOG REMOVED: Logging huge request bodies (6000+ chars) causes NSLog to crash
            // with EXC_BAD_ACCESS in _platform_strlen. See crash report 2025-12-27-133800.
            // If debugging is needed, truncate the body first or log only the first 500 chars.
            
            if let result = processThinkingParameter(jsonString: modifiedBody, isSyncTest: isSyncTest, providerName: providerName) {
                modifiedBody = result.0
                thinkingEnabled = result.1
            }
            
            // CRITICAL FIX: Strip thinking mode for multi-turn DeepSeek conversations
            // Must be AFTER model routing so we can check the actual target model
            modifiedBody = stripThinkingForProblematicRequests(jsonString: modifiedBody)
        }
        
        forwardRequest(method: method, path: rewrittenPath, version: httpVersion, headers: headers, body: modifiedBody, thinkingEnabled: thinkingEnabled, originalConnection: connection)
    }
    
    /**
     Fixes incompatibility between OpenCode AI SDK and standard OpenAI format.
     Specifically handles cases where 'text' content is nested as an object instead of a string.
     */
    
    /**
     Sends an error response to the client
     */
    func sendError(to connection: NWConnection, statusCode: Int, message: String) {
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
