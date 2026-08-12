#!/bin/bash
#
# Builds fruit-dock as a real .app bundle.
#
# WHY THIS EXISTS
#
# `swift run FruitDockApp` produces a bare Mach-O in .build/, ad-hoc signed
# with an identifier derived from the binary itself:
#
#     Identifier=FruitDockApp-5555494492c65f84580d3753b69778598c4c2a47
#     Signature=adhoc    TeamIdentifier=not set
#
# TCC — the subsystem behind Privacy & Security — keys Accessibility grants to
# that identity. Every rebuild relinks the binary, changes the identifier, and
# macOS sees a different application. The grant stops applying while System
# Settings still shows it switched on, which is worse than it plainly failing.
#
# Window placement needs Accessibility permission, so this made the feature
# effectively untestable by hand: it would look exactly like a bug in
# WindowPlacer rather than a permission that silently lapsed.
#
# A bundle with a fixed CFBundleIdentifier, at a fixed path, signed with a
# fixed identifier gives TCC something stable to attach a grant to.
#
# CAVEAT — read before trusting this
#
# The bundle identifier is now stable, but the signature is still ad-hoc. TCC
# may additionally key on the code directory hash, which changes whenever the
# binary changes. If Accessibility permission still lapses after a rebuild,
# that is the reason, and the fix is signing with a stable identity (a free
# Apple Development certificate, or a Developer ID once one exists).
#
# This has NOT been verified across a rebuild. Test it: grant permission, run
# this script again, and check whether placement still works.

set -euo pipefail

CONFIGURATION="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="fruit-dock"
BUNDLE_ID="com.izaakwhite.fruit-dock"

# A fixed location, outside .build/, so the path TCC remembers survives a
# `swift package clean`.
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building ($CONFIGURATION)"
cd "$ROOT"
swift build -c "$CONFIGURATION" --product FruitDockApp

BINARY="$(swift build -c "$CONFIGURATION" --product FruitDockApp --show-bin-path)/FruitDockApp"
[ -f "$BINARY" ] || { echo "error: binary not found at $BINARY" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/FruitDockApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --identifier is the point of the exercise. Without it, codesign derives one
# from the binary and it changes on every build.
echo "==> Signing"
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"

echo "==> Signature"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature|CDHash' || true

cat <<EOF

Built: $APP

Run it:      open "$APP"
Quit it:     menu bar icon -> Quit fruit-dock

Accessibility permission is required for windows to open on the clicked
display. Grant it to THIS bundle — a grant given to the bare .build/ binary
does not carry over:

  System Settings -> Privacy & Security -> Accessibility

If permission lapses after re-running this script, see the CAVEAT at the top
of this file.
EOF
