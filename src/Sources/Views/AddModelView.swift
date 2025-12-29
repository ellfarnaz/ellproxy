import SwiftUI

/// View for adding a new custom model
struct AddModelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var modelRouter = ModelRouter.shared
    
    @State private var modelId = ""
    @State private var displayName = ""
    @State private var selectedProvider = "antigravity"
    @State private var upstreamModel = ""
    @State private var supportsThinking = false
    @State private var errorMessage: String?
    @State private var isProcessing = false
    
    private let providers = [
        "antigravity": "AntiGravity",
        "google": "Google Gemini",
        "qwen": "Qwen",
        "iflow": "iFlow",
        "codex": "Codex (OpenAI)",
        "claude": "Claude",
        "copilot": "GitHub Copilot",
        "kiro": "Kiro"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Custom Model")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section {
                    TextField("Model ID (e.g., gpt-6-custom)", text: $modelId)
                        .textFieldStyle(.roundedBorder)
                        .help("Unique identifier for the model")
                    
                    TextField("Display Name (e.g., GPT-6 Custom)", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .help("Human-readable name shown in the UI")
                } header: {
                    Text("Basic Information")
                        .font(.headline)
                }
                
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(providers.keys.sorted(), id: \.self) { key in
                            HStack {
                                if let icon = IconCatalog.shared.image(named: modelRouter.providerIconName(key), resizedTo: NSSize(width: 16, height: 16), template: true) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .renderingMode(.template)
                                        .frame(width: 16, height: 16)
                                }
                                Text(providers[key] ?? key)
                            }
                            .tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("The provider that hosts this model")
                    
                    TextField("Upstream Model Name", text: $upstreamModel)
                        .textFieldStyle(.roundedBorder)
                        .help("The actual model name used by the provider API")
                } header: {
                    Text("Provider Configuration")
                        .font(.headline)
                }
                
                Section {
                    Toggle("Supports Extended Thinking", isOn: $supportsThinking)
                        .help("Enable if this model supports reasoning/thinking parameters")
                } header: {
                    Text("Model Capabilities")
                        .font(.headline)
                }
                
                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Add Model") {
                    addModel()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
    }
    
    private func addModel() {
        // Clear previous error
        errorMessage = nil
        
        // Validate inputs
        guard !modelId.isEmpty else {
            errorMessage = "Model ID is required"
            return
        }
        
        guard !displayName.isEmpty else {
            errorMessage = "Display Name is required"
            return
        }
        
        guard !upstreamModel.isEmpty else {
            errorMessage = "Upstream Model Name is required"
            return
        }
        
        // Validate model ID format (alphanumeric, hyphens, underscores)
        let validIdPattern = "^[a-zA-Z0-9_-]+$"
        if modelId.range(of: validIdPattern, options: .regularExpression) == nil {
            errorMessage = "Model ID can only contain letters, numbers, hyphens, and underscores"
            return
        }
        
        // Check for duplicate ID
        if modelRouter.models.contains(where: { $0.id == modelId }) {
            errorMessage = "A model with ID '\(modelId)' already exists"
            return
        }
        
        isProcessing = true
        
        // Create new model
        let newModel = ModelConfig(
            id: modelId,
            name: displayName,
            provider: selectedProvider,
            upstreamModel: upstreamModel,
            supportsThinking: supportsThinking
        )
        
        // Add and save
        do {
            try ModelRouter.shared.addModel(newModel)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }
}

#Preview {
    AddModelView()
}
