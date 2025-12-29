import SwiftUI

// MARK: - Fallback Model Picker Popover
struct FallbackModelPickerPopover: View {
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var modelRouter = ModelRouter.shared
    
    /// Filtered models based on search text
    private var filteredModelsByProvider: [String: [ModelConfig]] {
        guard !searchText.isEmpty else {
            return modelRouter.modelsByProvider
        }
        
        let searchLower = searchText.lowercased()
        var filtered: [String: [ModelConfig]] = [:]
        
        for (provider, models) in modelRouter.modelsByProvider {
            let matchingModels = models.filter { model in
                model.name.lowercased().contains(searchLower) ||
                model.id.lowercased().contains(searchLower) ||
                provider.lowercased().contains(searchLower)
            }
            
            if !matchingModels.isEmpty {
                filtered[provider] = matchingModels
            }
        }
        
        return filtered
    }
    
    private var filteredProviders: [String] {
        let order = ["antigravity", "google", "qwen", "iflow", "codex", "claude", "copilot", "kiro"]
        return order.filter { filteredModelsByProvider[$0] != nil }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Model list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // None option
                    Button(action: {
                        modelRouter.fallbackModelId = ""
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            if modelRouter.fallbackModelId.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                            Text("None")
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Provider sections
                    ForEach(filteredProviders, id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(modelRouter.providerDisplayName(provider))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 4)
                            
                            ForEach(filteredModelsByProvider[provider] ?? []) { model in
                                Button(action: {
                                    modelRouter.fallbackModelId = ModelRouter.uniqueKey(for: model)
                                    dismiss()
                                }) {
                                    HStack(spacing: 8) {
                                        if ModelRouter.uniqueKey(for: model) == modelRouter.fallbackModelId {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                                .font(.caption)
                                        }
                                        Text(model.name)
                                            .font(.system(size: 13))
                                        if model.supportsThinking {
                                            Text("⚡")
                                                .font(.caption)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 350)
    }
}
