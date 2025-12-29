import Foundation

// MARK: - Ring Buffer

/// Ring buffer for storing fixed-capacity log entries
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head = 0
    private var tail = 0
    private(set) var count = 0
    
    let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }
    
    mutating func append(_ element: Element) {
        storage[tail] = element
        tail = (tail + 1) % capacity
        
        if count < capacity {
            count += 1
        } else {
            head = (head + 1) % capacity
        }
    }
    
    func toArray() -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)
        
        for index in 0..<count {
            let storageIndex = (head + index) % capacity
            if let value = storage[storageIndex] {
                result.append(value)
            }
        }
        
        return result
    }
}
