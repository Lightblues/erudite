import SwiftUI

// MARK: - Library View (Word Lists + Browser)

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Word Library")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button("Import", systemImage: "square.and.arrow.down") {
                    // TODO: import flow
                }
            }
            .padding()

            Divider()

            // Content
            if appState.isDBReady {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Word library will be displayed here")
                        .foregroundStyle(.secondary)

                    Text("Browse by list, root family, or search")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ProgressView("Loading database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: "Search words...")
    }
}
