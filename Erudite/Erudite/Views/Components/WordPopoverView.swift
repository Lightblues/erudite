import SwiftUI

// MARK: - Word Popover View (Compact Dictionary Card)

/// Where the popover was opened from. Affects which actions make sense:
/// - `.library`: user is already in Library and the right-hand pane already
///   shows full details, so the "Show details" sheet would be redundant.
/// - `.elsewhere`: anywhere else (Today, Plan, Flashcard, Typing, definition
///   click) — show "Show details" so the user can deep-dive without leaving.
nonisolated enum WordPopoverHost: Hashable {
    case elsewhere
    case library
}

/// A compact word card shown in a popover when a user clicks an interactive word.
/// Supports multi-layer lookup: English text inside the popover is also interactive.
///
/// While visible the popover bumps `AppState.popoverDepth` so the global
/// KeyCaptureView yields keyboard control — without this, pressing Esc to dismiss
/// the popover would also trigger flashcard/typing shortcuts.
struct WordPopoverView: View {
    let word: Word
    var host: WordPopoverHost = .elsewhere
    var onDismiss: (() -> Void)?

    @Environment(AppState.self) private var appState
    @State private var showAllDefinitions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: spelling + phonetic
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.spelling)
                    .font(.system(size: 20, weight: .bold, design: .serif))

                if let phonetic = word.phonetic {
                    Text(phonetic)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Definitions: show first 2, expand for rest
            let defsToShow = showAllDefinitions ? word.definitions : Array(word.definitions.prefix(2))
            ForEach(Array(defsToShow.enumerated()), id: \.offset) { _, def in
                HStack(alignment: .top, spacing: 8) {
                    if !def.partOfSpeech.isEmpty {
                        Text(def.partOfSpeech)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 3))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if !def.chinese.isEmpty {
                            Text(def.chinese)
                                .font(.body)
                        }
                        if !def.english.isEmpty {
                            InteractiveText(text: def.english, font: .callout, color: .secondary)
                        }
                    }
                }
            }

            // "Show more" if there are extra definitions
            if word.definitions.count > 2 && !showAllDefinitions {
                Button {
                    showAllDefinitions = true
                } label: {
                    Text("Show all \(word.definitions.count) definitions")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            // First example (interactive)
            if let example = word.examples.first {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    InteractiveText(text: example.sentence, font: .callout, color: .secondary, italic: true)
                }
            }

            // Mnemonic / Etymology (interactive)
            if let mnemonic = word.mnemonics.first {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption2)
                    InteractiveText(text: mnemonic, font: .caption, color: .primary.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Synonyms (each chip is tappable)
            if !word.synonymGroups.isEmpty {
                let synonyms = word.synonymGroups.flatMap { $0 }.prefix(5)
                SynonymChipsView(synonyms: Array(synonyms))
            }

            Divider()

            // Footer: external links + (optional) Show details
            HStack(spacing: 12) {
                if host == .elsewhere {
                    Button {
                        appState.showWordDetailSheet(word.id)
                        onDismiss?()
                    } label: {
                        Label("Show details", systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Open the full WordDetail in a sheet — ⌘O")
                }

                Spacer()

                Button {
                    openMWWeb(word.spelling)
                } label: {
                    Label("Merriam-Webster", systemImage: "globe")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Button {
                    WordLookupService.openInEudic(word.spelling)
                } label: {
                    Label("Eudic", systemImage: "book")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        // Esc dismiss via a zero-size hidden Button. Unlike .onKeyPress(.escape),
        // .keyboardShortcut works without the view needing focus, so it's
        // reliable inside a popover where focus is unpredictable. The Button is
        // not visible but is part of the view tree so the system installs the
        // shortcut while the popover is on screen.
        .background(
            Button("Dismiss") {
                onDismiss?()
            }
            .keyboardShortcut(.cancelAction)   // Esc + Cmd+. (cancelAction = .escape on macOS)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .onAppear { appState.popoverDidAppear() }
        .onDisappear { appState.popoverDidDisappear() }
    }

    private func openMWWeb(_ spelling: String) {
        let encoded = spelling.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spelling
        if let url = URL(string: "https://www.merriam-webster.com/dictionary/\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Not Found Popover

/// Shown when a word is not found in local DB or API.
struct NotFoundPopoverView: View {
    let spelling: String
    var onDismiss: (() -> Void)?

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(spelling)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                Spacer()
                Button { onDismiss?() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("Word not found in dictionary")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                WordLookupService.openInEudic(spelling)
            } label: {
                Label("Look up in Eudic", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 280)
        .background(
            Button("Dismiss") { onDismiss?() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .onAppear { appState.popoverDidAppear() }
        .onDisappear { appState.popoverDidDisappear() }
    }
}

// MARK: - Synonym Chips with Lookup

/// Individual synonym chips that are tappable for dictionary lookup.
struct SynonymChipsView: View {
    let synonyms: [String]
    var chipFont: Font = .caption
    var chipPaddingH: CGFloat = 6
    var chipPaddingV: CGFloat = 2

    @Environment(AppState.self) private var appState
    @State private var popoverWord: Word?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
                .font(.caption2)
                .foregroundStyle(.blue)
            ForEach(synonyms, id: \.self) { syn in
                Text(syn)
                    .font(chipFont)
                    .padding(.horizontal, chipPaddingH)
                    .padding(.vertical, chipPaddingV)
                    .background(.blue.opacity(0.1), in: Capsule())
                    .onTapGesture { handleTap(syn) }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
        }
        .popover(item: $popoverWord, arrowEdge: .bottom) { word in
            WordPopoverView(word: word) {
                popoverWord = nil
            }
        }
    }

    private func handleTap(_ spelling: String) {
        guard let service = appState.wordLookupService else { return }
        let cleaned = spelling.lowercased()
        if let word = service.lookup(cleaned) {
            popoverWord = word
            return
        }
        Task {
            let result = await service.lookupAsync(cleaned)
            if case .found(let word) = result {
                popoverWord = word
            }
        }
    }
}
