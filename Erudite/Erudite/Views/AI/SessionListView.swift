import SwiftUI

// MARK: - Session List View

/// Popover showing past conversation sessions.
struct SessionListView: View {
    let sessions: [AISession]
    let currentSessionId: String?
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onNewSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onNewSession) {
                    Label("New", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if sessions.isEmpty {
                Text("No conversations yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 260)
    }

    private func sessionRow(_ session: AISession) -> some View {
        let isCurrent = session.id == currentSessionId

        return Button {
            if !isCurrent {
                onSelect(session.id)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isCurrent ? Color.purple : Color.clear)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.caption)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(relativeDate(session.lastMessageAt))
                        Text("·")
                        Text("\(session.messageCount) msgs")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if !isCurrent {
                    Button {
                        onDelete(session.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isCurrent ? Color.purple.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Make AISession conform to Identifiable for ForEach
extension AISession: Hashable {
    static func == (lhs: AISession, rhs: AISession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
