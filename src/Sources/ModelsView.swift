import SwiftUI

/// View for managing model routing configuration
struct ModelsView: View {
    @ObservedObject private var modelRouter = ModelRouter.shared
    @State private var expandedProviders: Set<String> = []
    @State private var copiedModel: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                // Routing Toggle Section
                Section {
                    Toggle("Enable Model Routing", isOn: $modelRouter.routingEnabled)
                        .help("When enabled, incoming requests can be routed to the selected default model")
                    
                    if modelRouter.routingEnabled, let activeModel = modelRouter.activeModel {
                        HStack {
                            Text("Default Model")
                            Spacer()
                            HStack(spacing: 4) {
                                if let icon = IconCatalog.shared.image(named: modelRouter.providerIconName(activeModel.provider), resizedTo: NSSize(width: 14, height: 14), template: true) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .renderingMode(.template)
                                        .frame(width: 14, height: 14)
                                }
                                Text(activeModel.name)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Model Routing")
                } footer: {
                    Text("When routing is enabled, requests without a specific model will use the default model. Click a model below to set it as default or copy its name.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Models List by Provider
                Section("Available Models") {
                    ForEach(modelRouter.providers, id: \.self) { provider in
                        ProviderSection(
                            provider: provider,
                            models: modelRouter.modelsByProvider[provider] ?? [],
                            isExpanded: expandedProviders.contains(provider),
                            activeModelId: modelRouter.activeModelId,
                            copiedModel: copiedModel,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedProviders.contains(provider) {
                                        expandedProviders.remove(provider)
                                    } else {
                                        expandedProviders.insert(provider)
                                    }
                                }
                            },
                            onSelectModel: { model in
                                modelRouter.activeModelId = model.id
                            },
                            onCopyModel: { model in
                                copyModelToClipboard(model)
                            }
                        )
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            // Expand provider of active model by default
            if let activeModel = modelRouter.activeModel {
                expandedProviders.insert(activeModel.provider)
            }
        }
    }
    
    private func copyModelToClipboard(_ model: ModelConfig) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.id, forType: .string)
        
        withAnimation {
            copiedModel = model.id
        }
        
        // Reset copied state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedModel == model.id {
                    copiedModel = nil
                }
            }
        }
    }
}

/// A collapsible section showing models for a provider
struct ProviderSection: View {
    let provider: String
    let models: [ModelConfig]
    let isExpanded: Bool
    let activeModelId: String
    let copiedModel: String?
    let onToggleExpand: () -> Void
    let onSelectModel: (ModelConfig) -> Void
    let onCopyModel: (ModelConfig) -> Void
    
    private var modelRouter: ModelRouter { ModelRouter.shared }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Provider Header
            HStack {
                if let icon = IconCatalog.shared.image(named: modelRouter.providerIconName(provider), resizedTo: NSSize(width: 18, height: 18), template: true) {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 18, height: 18)
                }
                Text(modelRouter.providerDisplayName(provider))
                    .fontWeight(.medium)
                Spacer()
                Text("\(models.count) models")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpand()
            }
            
            // Models List
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(models) { model in
                        ModelRow(
                            model: model,
                            isActive: model.id == activeModelId,
                            isCopied: copiedModel == model.id,
                            onSelect: { onSelectModel(model) },
                            onCopy: { onCopyModel(model) }
                        )
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A single model row with selection and copy buttons
struct ModelRow: View {
    let model: ModelConfig
    let isActive: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Selection indicator
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .accentColor : .secondary)
                .font(.system(size: 12))
            
            // Model name
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .primary : .secondary)
                
                if model.supportsThinking {
                    Text("Supports extended thinking")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 2) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(isCopied ? "Copied!" : "Copy")
                        .font(.system(size: 10))
                }
                .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

#Preview {
    ModelsView()
}
