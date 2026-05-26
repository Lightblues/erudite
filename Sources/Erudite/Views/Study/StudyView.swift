import SwiftUI

// MARK: - Study View (FSRS Card Session)

struct StudyView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Placeholder card
            VStack(spacing: 16) {
                Text("📚")
                    .font(.system(size: 48))

                Text("Study Session")
                    .font(.title)
                    .fontWeight(.bold)

                Text("FSRS-powered learning will be implemented here.")
                    .foregroundStyle(.secondary)

                Text("Cards will show word → tap to reveal → rate recall")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 400)
            .padding(32)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            // Rating buttons preview
            HStack(spacing: 12) {
                ForEach(Rating.allCases, id: \.self) { rating in
                    Button {
                        // TODO: implement rating action
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: rating.icon)
                            Text(rating.label)
                                .font(.caption)
                        }
                        .frame(width: 70, height: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Learn")
    }
}
