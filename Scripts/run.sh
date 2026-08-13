#!/bin/bash
#
# The development loop: stop what's running, rebuild, relaunch.
#
# Separate from make-app-bundle.sh, which only ever builds. This one has side
# effects on the running system — it terminates a process and can delete your
# settings — and those belong behind a name that says so.
#
# Quitting first is not optional. fruit-dock is a menu-bar agent with no window,
# so a stale copy left running is invisible except as a second icon in the menu
# bar, and every click you then test goes to the old binary. That failure looks
# exactly like a fix that didn't work.
#
# Usage:
#   ./Scripts/run.sh                  build, sign, launch
#   ./Scripts/run.sh --release        release configuration
#   ./Scripts/run.sh --reset          wipe saved settings first
#   ./Scripts/run.sh --test           run the test suite, and stop if it fails
#   ./Scripts/run.sh --no-launch      build and sign only
#
# Flags combine: --test --reset --release is fine.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.izaakwhite.fruit-dock"
APP="$ROOT/build/fruit-dock.app"

CONFIGURATION="debug"
RESET=false
RUN_TESTS=false
LAUNCH=true

for arg in "$@"; do
    case "$arg" in
        --release)   CONFIGURATION="release" ;;
        --debug)     CONFIGURATION="debug" ;;
        --reset)     RESET=true ;;
        --test)      RUN_TESTS=true ;;
        --no-launch) LAUNCH=false ;;
        -h|--help)   sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *)
            echo "error: unknown option '$arg' (try --help)" >&2
            exit 1
            ;;
    esac
done

cd "$ROOT"

if [ "$RUN_TESTS" = true ]; then
    echo "==> Testing"
    # Before the build, and fatal: launching a build whose tests fail wastes the
    # slower half of the loop on something already known to be broken.
    swift test
    echo
fi

# Terminate before rebuilding, not after. Overwriting the bundle underneath a
# running process leaves it running the old code from a file that no longer
# exists, which is the most confusing state of the three.
if pgrep -f "fruit-dock.app/Contents/MacOS/FruitDockApp" > /dev/null 2>&1; then
    echo "==> Quitting the running instance"
    # Ask first: the app deserves the chance to close its panels and remove its
    # observers. SIGKILL only if it will not go.
    osascript -e 'quit app "fruit-dock"' > /dev/null 2>&1 || true

    for _ in $(seq 1 20); do
        pgrep -f "fruit-dock.app/Contents/MacOS/FruitDockApp" > /dev/null 2>&1 || break
        sleep 0.1
    done

    if pgrep -f "fruit-dock.app/Contents/MacOS/FruitDockApp" > /dev/null 2>&1; then
        echo "    (not responding — forcing)"
        pkill -f "fruit-dock.app/Contents/MacOS/FruitDockApp" || true
        sleep 0.5
    fi
fi

if [ "$RESET" = true ]; then
    # Restores the first-launch path, which is the only way to exercise seeding
    # from the system Dock — after the first save, seeding never runs again.
    echo "==> Deleting saved settings ($BUNDLE_ID)"
    defaults delete "$BUNDLE_ID" 2>/dev/null || echo "    (nothing saved)"
fi

"$ROOT/Scripts/make-app-bundle.sh" "$CONFIGURATION"

if [ "$LAUNCH" = false ]; then
    exit 0
fi

echo "==> Launching"
open "$APP"

# `open` returns as soon as it has handed off, so a crash on startup would
# otherwise look like a successful run. An accessory app has no window to check,
# which makes the process table the only evidence available.
sleep 2
if pgrep -f "fruit-dock.app/Contents/MacOS/FruitDockApp" > /dev/null 2>&1; then
    echo "    running — look for the dock icon in your menu bar"
else
    echo "    error: it exited immediately. Recent output:" >&2
    log show --last 30s --predicate 'process == "FruitDockApp"' \
        --style compact 2>/dev/null | tail -20 >&2
    exit 1
fi
