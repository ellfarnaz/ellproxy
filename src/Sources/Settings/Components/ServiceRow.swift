import SwiftUI

// MARK: - Service Row

/// A row displaying a service with itsconnected accounts and add button
struct ServiceRow: View {
    let serviceType: ServiceType
    let iconName: String
    let accounts: [AuthAccount]
    let isAuthenticating: Bool
    let helpText: String?
    let onConnect: () -> Void
    let onDisconnect: (AuthAccount) -> Void
    var onExpandChange: ((Bool) -> Void)? = nil
    
    @State private var isExpanded = false
    @State private var accountToRemove: AuthAccount?
    @State private var showingRemoveConfirmation = false
    
    private var activeCount: Int { accounts.filter { !$0.isExpired }.count }
    private var expiredCount: Int { accounts.filter { $0.isExpired }.count }
    private let removeColor = Color(red: 0xeb/255, green: 0x0f/255, blue: 0x0f/255)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                if let nsImage = IconCatalog.shared.image(named: iconName, resizedTo: NSSize(width: 20, height: 20), template: true) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 20, height: 20)
                }
                Text(serviceType.displayName)
                    .fontWeight(.medium)
                Spacer()
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Add Account", action: onConnect)
                        .controlSize(.small)
                }
            }
            
            // Account display
            if !accounts.isEmpty {
                // Collapsible summary
                HStack(spacing: 4) {
                    Text("\(accounts.count) connected account\(accounts.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if accounts.count > 1 {
                        Text("• Round-robin w/ auto-failover")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 28)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                
                // Expanded accounts list
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(accounts) { account in
                            AccountRowView(account: account, removeColor: removeColor) {
                                accountToRemove = account
                                showingRemoveConfirmation = true
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("No connected accounts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .help(helpText ?? "")
        .onChange(of: isExpanded) { _, newValue in
            onExpandChange?(newValue)
        }
        .alert("Remove Account", isPresented: $showingRemoveConfirmation, presenting: accountToRemove) { account in
            Button("Cancel", role: .cancel) {
                accountToRemove = nil
            }
            Button("Remove", role: .destructive) {
                onDisconnect(account)
                accountToRemove = nil
            }
        } message: { account in
            Text("Are you sure you want to remove \(account.displayName) from \(serviceType.displayName)?")
        }
    }
}
