import SwiftUI

// MARK: - Detected Tool

struct DetectedTool: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    var status: ToolStatus
    var statusMessage: String
    let configInstructions: String
}
