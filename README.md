# Erudite

AI-native macOS app for GRE vocabulary learning.

- FSRS-powered spaced repetition (state-of-the-art scheduling algorithm)
- Multiple study modes: Flashcard, Typing
- Context-aware AI teacher
- Word root analysis and semantic clustering

Requires **macOS 14 (Sonoma) or later**.

## Install

```bash
brew install --cask lightblues/tap/erudite
```

That single command taps the repo (if needed), downloads the latest
universal DMG, and installs `Erudite.app` into `/Applications`. The
quarantine flag is stripped automatically — no "right-click → Open"
dance, just launch it from Launchpad.

### Update

```bash
brew update && brew upgrade --cask erudite
```

### Uninstall

```bash
brew uninstall --cask erudite              # remove the app
brew uninstall --cask --zap erudite        # also wipe Caches / Preferences / Application Support
```

## Manual install (without Homebrew)

Grab the latest DMG from
[Releases](https://github.com/Lightblues/erudite/releases). Drag
`Erudite.app` to `/Applications`. The app is ad-hoc signed, so the
first launch needs **right-click → Open** (only once); after that
double-click works normally. Or run once from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Erudite.app
```

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — high-level structure
- [`.ea/spec/`](.ea/spec/) — product, features, AI system, data model, dev workflow
- [`RELEASE.md`](RELEASE.md) — how releases are cut

## Development

Open `Erudite/Erudite.xcodeproj` in Xcode. See
[`.ea/spec/development.md`](.ea/spec/development.md) for the dev workflow.
