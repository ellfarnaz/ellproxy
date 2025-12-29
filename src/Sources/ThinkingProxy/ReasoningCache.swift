import Foundation

/**
 Singleton cache for storing reasoning_content from DeepSeek responses.
 
 When DeepSeek returns a response with reasoning_content, we cache it keyed by
 a hash of the assistant's content. This allows us to replay the exact reasoning
 when Claude CLI sends back the message history without preserving the field.
 */
class ReasoningCache {
    static let shared = ReasoningCache()
    
    private var cache: [String: String] = [:]
    private let queue = DispatchQueue(label: "io.automaze.ellproxy.reasoning-cache")
    private let maxEntries = 100  // Prevent unbounded growth
    
    private init() {}
    
    /**
     Generates a cache key from assistant message content.
     Uses content hash to match messages across requests.
     */
    private func cacheKey(for content: String) -> String {
        // Use first 100 chars + length as a simple but effective key
        let prefix = String(content.prefix(100))
        return "\(prefix.hashValue)_\(content.count)"
    }
    
    /**
     Stores reasoning_content for a given assistant message content.
     */
    func store(content: String, reasoning: String) {
        guard !content.isEmpty, !reasoning.isEmpty else { return }
        
        let key = cacheKey(for: content)
        queue.sync {
            // Evict oldest entries if cache is full
            if cache.count >= maxEntries {
                // Simple eviction: remove first half of entries
                let keysToRemove = Array(cache.keys.prefix(maxEntries / 2))
                for k in keysToRemove {
                    cache.removeValue(forKey: k)
                }
                NSLog("[ReasoningCache] Evicted \(keysToRemove.count) entries")
            }
            
            cache[key] = reasoning
            NSLog("[ReasoningCache] Stored reasoning for key: \(key.prefix(20))... (total: \(cache.count))")
        }
    }
    
    /**
     Retrieves cached reasoning_content for a given assistant message content.
     Returns nil if not found.
     */
    func retrieve(for content: String) -> String? {
        guard !content.isEmpty else { return nil }
        
        let key = cacheKey(for: content)
        return queue.sync {
            if let reasoning = cache[key] {
                NSLog("[ReasoningCache] Cache HIT for key: \(key.prefix(20))...")
                return reasoning
            }
            NSLog("[ReasoningCache] Cache MISS for key: \(key.prefix(20))...")
            return nil
        }
    }
    
    /**
     Clears all cached entries.
     */
    func clear() {
        queue.sync {
            cache.removeAll()
            NSLog("[ReasoningCache] Cache cleared")
        }
    }
    
    /**
     Returns the current cache size.
     */
    var count: Int {
        queue.sync { cache.count }
    }
}
