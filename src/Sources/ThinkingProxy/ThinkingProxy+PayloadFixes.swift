import Foundation

/**
 Extension for handling payload format fixes for various clients
 
 Different AI coding assistants may send malformed payloads that need correction
 before forwarding to the upstream API.
 */
extension ThinkingProxy {
    
    /**
     Fixes incompatibility between OpenCode AI SDK and standard OpenAI format.
     Specifically handles cases where 'text' content is nested as an object instead of a string.
     
     OpenCode bug: Sends `{"type": "text", "text": {"text": "actual value"}}`
     Expected format: `{"type": "text", "text": "actual value"}`
     */
    func fixOpenCodePayload(jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var messages = json["messages"] as? [[String: Any]] else {
            return jsonString
        }
        
        var modified = false
        
        for (i, message) in messages.enumerated() {
            guard var contentList = message["content"] as? [[String: Any]] else { continue }
            var messageModified = false
            
            for (j, content) in contentList.enumerated() {
                // Check if type is 'text' but 'text' field is an object/dictionary
                if content["type"] as? String == "text",
                   let textObj = content["text"] as? [String: Any],
                   let textValue = textObj["text"] as? String {
                    
                    // Found nested object: { "type": "text", "text": { "text": "actual value" } }
                    // Fix to: { "type": "text", "text": "actual value" }
                    var newContent = content
                    newContent["text"] = textValue
                    contentList[j] = newContent
                    messageModified = true
                    NSLog("[ThinkingProxy] Fixed nested text object in message \(i) content \(j)")
                }
            }
            
            if messageModified {
                var newMessage = message
                newMessage["content"] = contentList
                messages[i] = newMessage
                modified = true
            }
        }
        
        if modified {
            json["messages"] = messages
            if let newData = try? JSONSerialization.data(withJSONObject: json),
               let newString = String(data: newData, encoding: .utf8) {
                return newString
            }
        }
        
        return jsonString
    }
}
