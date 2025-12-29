import Foundation

/**
 Extension for handling image format normalization across different API clients
 
 Different clients (OpenCode, Trae, etc.) may send images in non-standard formats.
 This extension normalizes them to OpenAI's standard format:
 `{"type": "image_url", "image_url": {"url": "data:..."}}`
 */
extension ThinkingProxy {
    
    /**
     Normalizes image content in messages to standard OpenAI format
     
     - Parameter bodyString: The raw request body string
     - Returns: Modified body string if normalization occurred, nil otherwise
     */
    func normalizeImageContent(in bodyString: String) -> String? {
        guard let bodyData = bodyString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any],
              var messages = json["messages"] as? [[String: Any]] else {
            return nil
        }
        
        var messagesChanged = false
        
        for (i, msg) in messages.enumerated() {
            guard let contentArray = msg["content"] as? [[String: Any]] else {
                continue
            }
            
            var newContent = contentArray
            var contentChanged = false
            
            for (j, item) in contentArray.enumerated() {
                guard let type = item["type"] as? String else {
                    continue
                }
                
                // Handle type="text" containing base64 image data URLs
                // Some clients incorrectly mark images as text content
                if type == "text", let text = item["text"] as? String {
                    if text.hasPrefix("data:image/") && text.contains(";base64,") {
                        newContent[j] = ["type": "image_url", "image_url": ["url": text]]
                        contentChanged = true
                        continue
                    }
                }
                
                // Handle type="image" or missing "image_url" wrapper
                // Normalize to standard OpenAI format
                if type == "image" || type == "image_url" {
                    if item["image_url"] == nil {
                        if let url = item["url"] as? String {
                            newContent[j] = ["type": "image_url", "image_url": ["url": url]]
                            contentChanged = true
                        }
                    }
                }
            }
            
            if contentChanged {
                messages[i]["content"] = newContent
                messagesChanged = true
            }
        }
        
        guard messagesChanged else {
            return nil
        }
        
        json["messages"] = messages
        
        guard let newData = try? JSONSerialization.data(withJSONObject: json, options: []),
              let newBody = String(data: newData, encoding: .utf8) else {
            return nil
        }
        
        return newBody
    }
}
