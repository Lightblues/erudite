---
description: Cut a release (bumps version, tags + pushes; CI handles the rest)
allowed-tools: Bash
argument-hint: patch|minor|major [--watch]
---

# /release

Bump the project version, tag it, push the tag — that's it. GitHub Actions
takes over from there: builds the universal DMG, creates the Release,
bumps the Homebrew Cask. You don't wait for it.

## Context (auto-injected)

- Current branch: !`git branch --show-current`
- Working tree status: !`git status --porcelain | head -20 || echo "(clean)"`
- Local vs origin/main: !`git fetch origin main --quiet 2>&1 && git rev-list --left-right --count main...origin/main | awk '{print "ahead="$1" behind="$2}'`
- Latest erudite tag: !`git tag --list 'erudite-v*' | sort -V | tail -1 || echo "(none)"`
- gh auth: !`gh auth status 2>&1 | grep -E "Logged in|Active account" | head -2 || echo "NOT logged in"`
- Argument: $ARGUMENTS

## Your task

The user wants to cut a release. Argument is `patch`, `minor`, or `major`,
optionally with `--watch`. Execute these steps in order. Stop at the
first failure with a one-line reason.

### 1. Pre-flight (all must pass)

Validate each, abort with a clear message if any fails:

- **Branch must be `main`.** If not: `❌ Not on main (currently on <branch>). Merge your PR first.` and stop.
- **Working tree must be clean.** If `git status --porcelain` produced anything: `❌ Working tree dirty. Commit or stash first.` and stop.
- **Local main must match origin/main exactly.** If `ahead != 0` or `behind != 0`: `❌ Local main not synced (ahead=N, behind=M). Run: git pull --ff-only` and stop.
- **gh CLI must be authenticated.** If "NOT logged in": `❌ gh CLI not logged in. Run: gh auth login` and stop.
- **Argument must be valid.** If not in `{patch, minor, major}`: `❌ First argument must be patch | minor | major.` and stop.

### 2. Compute next version

Parse the latest tag (format `erudite-vX.Y.Z`). If no tags exist, start
from `0.0.0`.

Bump rules:
- `patch`: `X.Y.Z` → `X.Y.(Z+1)`
- `minor`: `X.Y.Z` → `X.(Y+1).0`
- `major`: `X.Y.Z` → `(X+1).0.0`

Show the user: `Latest: erudite-v<old> → bumping to erudite-v<new>`.

### 3. Tag and push

```bash
git tag erudite-v<new>
git push origin erudite-v<new>
```

If push fails (e.g. tag already exists on remote even though it wasn't
local), report the error and stop. Don't try to recover.

### 4. Report

Output, in this order:

```
✓ Tagged + pushed: erudite-v<new>

CI run:
  https://github.com/Lightblues/erudite/actions
  (~3 min — release + cask bump happen automatically)

When the release lands, install/upgrade with:
  brew upgrade --cask lightblues/tap/erudite
```

You can grab the actual run URL with `gh run list --workflow build.yml --limit 1 --json url --jq '.[0].url'` if it's been a few seconds since the push (the workflow needs a moment to register). If that returns nothing fresh, just use the actions tab URL above.

### 5. Optional: --watch

Only if the user passed `--watch` (it'll be in `$ARGUMENTS`):

```bash
gh run watch --exit-status $(gh run list --workflow build.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

Otherwise, do **not** run `gh run watch`. The whole point of fire-and-forget
is that the user gets back to work immediately.

## Notes

- This command is project-scoped to Erudite. Tag prefix is hardcoded to `erudite-v`. Cask name is hardcoded to `lightblues/tap/erudite`. If we ever generalize, lift these into a config file.
- If a release fails partway (rare — most failures here would be CI runner issues, not your fault), the manual fallback is `gh workflow run update-tap.yml -f tag=erudite-vX.Y.Z` to rerun just the tap-bump leg. See `RELEASE.md`.
- This command does NOT touch `MARKETING_VERSION` in pbxproj. CI injects the version from the tag at build time. If you want pbxproj to track the latest released version too, bump it in Xcode and commit before running `/release`.
