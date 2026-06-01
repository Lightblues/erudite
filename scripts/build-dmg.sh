#!/usr/bin/env bash
# Build a universal Erudite DMG (arm64 + x86_64), ad-hoc signed.
#
# Used by both:
#   - Local dev: `./scripts/build-dmg.sh` → dist/Erudite-<version>.dmg
#   - CI:        .github/workflows/build.yml calls this script
#
# Version source priority:
#   1. $VERSION env var (CI passes the tag-stripped version)
#   2. MARKETING_VERSION grepped from project.pbxproj (the value Xcode shows
#      under target → General → Identity → Version)
#
# Output: dist/Erudite-<version>.dmg + the unsigned .app for inspection.
#
# Signing: ad-hoc (`-s -`) with hardened runtime + the project's entitlements.
# This is fine for tap-distributed apps — Brew Cask passes through quarantine
# stripping during install, so the user doesn't see a Gatekeeper prompt.
# (Full Developer ID + notarization would let it run from Finder without
# right-click-Open; not worth it for friend-distribution scope.)

set -euo pipefail

# ---- Paths ----
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${ROOT}/Erudite/Erudite.xcodeproj"
SCHEME="Erudite"
ENTITLEMENTS="${ROOT}/Erudite/Erudite/Erudite.entitlements"
DIST="${ROOT}/dist"
BUILD="${ROOT}/build"

# ---- Version ----
if [[ -z "${VERSION:-}" ]]; then
  VERSION=$(awk -F'= ' '/MARKETING_VERSION =/ {gsub(";","",$2); print $2; exit}' \
    "${PROJECT}/project.pbxproj" | tr -d '[:space:]')
fi
if [[ -z "${VERSION}" ]]; then
  echo "ERROR: could not resolve VERSION (no env var, no MARKETING_VERSION in pbxproj)" >&2
  exit 1
fi
echo "▶ Building Erudite v${VERSION}"

# ---- Clean ----
rm -rf "${BUILD}" "${DIST}"
mkdir -p "${BUILD}" "${DIST}"

# ---- Compile (universal) ----
# ARCHS forces both slices in one binary; ONLY_ACTIVE_ARCH=NO so xcodebuild
# doesn't shortcut to the host arch in non-archive builds.
# CODE_SIGNING_ALLOWED=NO defers signing — we ad-hoc sign ourselves below
# so the same flow works without Apple Developer signing identities (CI's
# macos-14 runner has none of ours).
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${BUILD}/DerivedData" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="${VERSION}" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="${BUILD}/DerivedData/Build/Products/Release/Erudite.app"
[[ -d "${APP}" ]] || { echo "ERROR: built app not found at ${APP}" >&2; exit 1; }

# ---- Verify universal ----
MAIN_BIN="${APP}/Contents/MacOS/Erudite"
echo "▶ lipo info:"
lipo -info "${MAIN_BIN}"
if ! lipo -info "${MAIN_BIN}" | grep -q "arm64" \
   || ! lipo -info "${MAIN_BIN}" | grep -q "x86_64"; then
  echo "ERROR: binary is not universal" >&2
  exit 1
fi

# ---- Ad-hoc sign ----
# --deep walks frameworks (GRDB).
# --options runtime enables hardened runtime — required for the entitlements
# on this app (sandbox + network.client + files.user-selected.read-only).
codesign --force --deep --sign - \
  --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
echo "✓ App signed (ad-hoc)"

# ---- Stage + DMG ----
STAGE="${BUILD}/dmg-staging"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

DMG="${DIST}/Erudite-${VERSION}.dmg"
hdiutil create \
  -volname "Erudite ${VERSION}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  "${DMG}"

# Sign the DMG itself so its signature is consistent with the app's.
codesign --force --sign - "${DMG}"

# Also publish the unsigned .app for inspection / debugging.
ditto -c -k --keepParent "${APP}" "${DIST}/Erudite-${VERSION}.app.zip"

# ---- Report ----
echo
echo "─────────────────────────────────────"
echo "✓ Build complete"
echo "  DMG: ${DMG}"
echo "  Size: $(du -h "${DMG}" | cut -f1)"
echo "  sha256: $(shasum -a 256 "${DMG}" | awk '{print $1}')"
echo "─────────────────────────────────────"
