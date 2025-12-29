import Foundation
import Network

/// Protocol for handling connection lifecycle
protocol ConnectionHandling {
    func handleConnection(_ connection: NWConnection)
}

/// Protocol for processing HTTP requests
protocol RequestProcessing {
    func processRequest(data: Data, connection: NWConnection)
}

/// Protocol for handling HTTP responses
protocol ResponseHandling {
    func sendError(to connection: NWConnection, statusCode: Int, message: String)
}

/// Protocol for thinking parameter transformation
protocol ThinkingProcessing {
    func processThinkingParameter(jsonString: String) -> (String, Bool)?
}
