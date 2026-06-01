# Releasing Erudite

Erudite ships as an ad-hoc-signed universal macOS DMG, distributed via:

1. **GitHub Releases** — primary download (`Erudite-x.y.z.dmg`)
2. **Homebrew Cask** — `brew install --cask lightblues/tap/erudite`

## TL;DR

```bash
# Cut a release
git tag erudite-v1.1.0 && git push origin erudite-v1.1.0
```

GitHub Actions does the rest: builds the DMG, creates the Release, bumps
the Homebrew tap.

## Install (for users)

```bash
brew tap lightblues/tap            # one-time
brew install --cask erudite        # or: brew upgrade --cask erudite
```

Open `Erudite.app` from Launchpad. No "right-click → Open" dance — Brew
strips the quarantine flag during install.

If they download the DMG directly from Releases instead of via Brew,
they need to right-click → Open the first time (ad-hoc signing).

## Local build

```bash
./scripts/build-dmg.sh                  # uses MARKETING_VERSION from pbxproj
VERSION=1.2.0-beta ./scripts/build-dmg.sh   # override
```

Output: `dist/Erudite-<version>.dmg` — universal (arm64 + x86_64), ad-hoc
signed with hardened runtime + the project's entitlements. Same flow as CI.

## CI workflows

### `.github/workflows/build.yml`

| Trigger | Effect |
|---|---|
| `push` tag `erudite-v*` | DMG → upload artifact → create GitHub Release → bump Homebrew tap |
| `workflow_dispatch` | DMG only (artifact); skip release + tap |

The `release` job runs only on tag pushes (`if: startsWith(github.ref,
'refs/tags/erudite-v')`).

### `.github/workflows/update-tap.yml`

Manual fallback. Use when:
- The inline tap-update in `build.yml` failed
- You edited a release and need to re-bump

```bash
gh workflow run update-tap.yml -f tag=erudite-v1.1.0
```

It downloads the DMG from the existing release, recomputes sha256, and
updates the cask file.

## One-time setup

### 1. Homebrew tap repo

`lightblues/homebrew-tap` must contain `Casks/erudite.rb`:

```ruby
cask "erudite" do
  version "1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Lightblues/erudite/releases/download/erudite-v#{version}/Erudite-#{version}.dmg"
  name "Erudite"
  desc "AI-native macOS app for GRE vocabulary learning"
  homepage "https://github.com/Lightblues/erudite"

  depends_on macos: ">= :sonoma"   # macOS 14+ — required by SwiftUI @Observable

  app "Erudite.app"

  zap trash: [
    "~/Library/Preferences/site.easonsi.Erudite.plist",
    "~/Library/Application Support/Erudite",
    "~/Library/Caches/site.easonsi.Erudite",
  ]
end
```

The all-zero sha256 is a placeholder — the first CI run replaces it. The
file must exist before the first release pushes; both workflows read +
overwrite the version + sha256 lines.

### 2. Repository secrets

| Secret | Where to set | What it does |
|---|---|---|
| `TAP_PUSH_TOKEN` | This repo's settings → Secrets → Actions | Personal Access Token with `repo` scope on `lightblues/homebrew-tap`. CI uses it to push cask bumps to that repo. |

GitHub's built-in `GITHUB_TOKEN` only works inside the current repo, so
cross-repo writes need a PAT. Create one under your GitHub settings →
Developer settings → Personal access tokens (classic), with `repo` scope.

## Release checklist

Before tagging:

- [ ] All commits merged to `main`
- [ ] `MARKETING_VERSION` in Xcode bumped (or skip — CI tag-injects)
- [ ] Smoke tested locally: `./scripts/build-dmg.sh`, install the DMG, open the app

Tag and push:

```bash
git tag erudite-v1.x.y
git push origin erudite-v1.x.y
```

Watch the workflow:

```bash
gh run watch
```

After it finishes:

- [ ] Release page has the DMG attached
- [ ] `lightblues/homebrew-tap` has a fresh commit "erudite: bump to 1.x.y"
- [ ] `brew update && brew upgrade --cask erudite` works on a test machine

## Why ad-hoc signing (not Developer ID)?

Erudite is friend-distribution. Apple Developer ID + notarization buys:
- No "right-click → Open" prompt for direct DMG installs
- Trust badge in System Settings → Privacy & Security

Costs:
- $99/yr Apple Developer Program
- Notarization step in CI (extra ~30s + Apple's API tokens)

For Brew Cask users it doesn't matter (Brew strips quarantine). For DMG
direct downloads, "right-click → Open" once is fine. **Skip until there
are actual end users complaining.**

## Why universal (not arm64-only)?

Universal binaries (~13 MB DMG) cover both Apple Silicon and Intel Macs.
Apple Silicon users see no runtime difference vs an arm64-only build —
macOS only loads the matching slice. Intel users (Sonoma 14+ on 2018+
Macs) can install instead of being locked out. The +6 MB DMG cost is
negligible compared to "this app won't install" friction.
