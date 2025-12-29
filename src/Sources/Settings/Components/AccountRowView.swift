import SwiftUI

// MARK: - Account Row View

/// A single account row with remove button
struct AccountRowView: View {
    let account: AuthAccount
    let removeColor: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(account.isExpired ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(account.displayName)
                .font(.caption)
                .foregroundColor(account.isExpired ? .orange : .secondary)
            if account.isExpired {
                Text("(expired)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Button(action: onRemove) {
                HStack(spacing: 2) {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                    Text("Remove")
                        .font(.caption)
                }
                .foregroundColor(removeColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.leading, 28)
    }
}
