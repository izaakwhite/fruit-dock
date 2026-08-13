# fruit-dock

A macOS menu-bar utility that puts a dock on the displays Apple's Dock isn't on.

macOS keeps its Dock on exactly one screen at a time. fruit-dock fills in the
others, and moves out of the way automatically when you push the real Dock to a
different display — so every screen has exactly one dock and none has two.

Built with Swift 6, SwiftPM, and AppKit, with no external dependencies.

---

## Requirements

- macOS 15 or later (developed and tested on macOS 26 Tahoe)
- [Xcode](https://developer.apple.com/xcode/) with the Swift 6 toolchain —
  `swift --version` should report 6.0 or later
- An Apple ID for code signing (free; the paid Developer Program is **not**
  needed for local use — see [Code signing](#code-signing))

## Quick start

```sh
git clone https://github.com/izaakwhite/fruit-dock.git
cd fruit-dock
./Scripts/make-app-bundle.sh
open build/fruit-dock.app
```

Look for the dock icon in your menu bar. Quit from that menu.

> **Use the bundle, not `swift run`.** `swift run FruitDockApp` is fine for a
> quick look, but it cannot hold the Accessibility permission — see
> [Permissions](#permissions-and-privacy).

---

## Permissions and privacy

fruit-dock is a menu-bar-only ("accessory") app: no Dock icon of its own, no
app-switcher entry.

### What it asks for, and why

| Permission | Needed for | Without it |
|---|---|---|
| **Accessibility** | Opening an app on the display whose dock you clicked | Apps still launch and activate — macOS just chooses the display |

That's the only permission it requests, and it is **optional**. Everything else
— showing running apps, pinning, launching, the applications browser, importing
your Dock's contents — works with no permission at all.

### Granting Accessibility

1. Launch the bundle: `open build/fruit-dock.app`
2. Menu bar icon → **Enable Opening Apps on the Clicked Display…**
3. Approve the system prompt, or add fruit-dock manually under
   **System Settings → Privacy & Security → Accessibility**
4. The menu item flips to a checkmark once granted — no relaunch needed

The app also offers one-click routes to the relevant panes under
**System Settings** in its menu: Dock & Menu Bar, Displays, Accessibility
Display, and Privacy Accessibility.

### ⚠️ The permission does not survive a rebuild

macOS ties Accessibility grants to an app's *code signing identity*. Every time
you change code and rebuild, the ad-hoc signature changes, and macOS treats the
result as a different application — **the grant silently stops applying while
System Settings still shows it switched on.**

Measured on this project:

| Scenario | Code signature | Grant survives? |
|---|---|---|
| Rebuild, no source change | unchanged | ✅ |
| Comment-only edit | unchanged | ✅ |
| **Any change that alters codegen** | **changes** | ❌ |

If window placement stops working after you edit something, this is why. Remove
fruit-dock from the Accessibility list and re-add it, or sign with a stable
identity (below).

### What it reads

- **`com.apple.dock`** — read-only, for importing your Dock's pinned apps and
  recent items. fruit-dock never writes to Apple's preferences.
- **Installed applications** — `/Applications`, `/System/Applications`,
  their `Utilities` folders, and `~/Applications`, for the app browser.

No network access, no telemetry, no data leaves the machine.

---

## Code signing

### Local use — free

`Scripts/make-app-bundle.sh` ad-hoc signs the bundle (`codesign --sign -`) with
a fixed identifier. That is enough to run it, and needs no Apple account:

```sh
./Scripts/make-app-bundle.sh          # debug (default)
./Scripts/make-app-bundle.sh release  # release
```

The fixed `CFBundleIdentifier` (`com.izaakwhite.fruit-dock`, in
`Resources/Info.plist`) and fixed signing identifier are what give macOS a
stable identity to attach permissions to. **Don't change them casually** — a
changed bundle identifier is a new app as far as TCC is concerned.

### A stable identity — still free

Ad-hoc signatures change on every meaningful build, which is what breaks the
Accessibility grant. Signing with an **Apple Development** certificate gives a
stable identity and does not require the paid Developer Program — an Apple ID
is enough. Create one in Xcode under **Settings → Accounts → Manage
Certificates → +**, then:

```sh
security find-identity -v -p codesigning     # find your identity name
codesign --force --deep --sign "Apple Development: you@example.com (TEAMID)" \
  --identifier com.izaakwhite.fruit-dock build/fruit-dock.app
```

### Distribution — paid

Sharing the app with anyone else needs the **Apple Developer Program**
($99/year) for a Developer ID certificate plus notarization. Without those,
macOS quarantines a downloaded app and Gatekeeper refuses to open it. Apps a
user builds themselves are never quarantined, so distributing source needs
none of this.

---

## Testing

```sh
swift test
```

With coverage:

```sh
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/FruitDockPackageTests.xctest/Contents/MacOS/FruitDockPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='.build|Tests'
```

Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`), not XCTest.

The domain layer sits around 97% line coverage; the AppKit layer is much lower,
and the project-wide figure is the one worth quoting. Both targets appear in the
report.

---

## Project layout

| Path | Contains |
|---|---|
| `Sources/FruitDockCore` | Pure domain: models, decision functions (`DisplayReconciler`, `DockContentBuilder`, `DockLayout`, `DisplayGeometry`, `WindowGeometry`), `DockCoordinator`, and the protocols abstracting system APIs. **Imports no UI framework.** |
| `Sources/FruitDockUI` | AppKit shell: panels, views, and the wrappers around `NSScreen`, `NSWorkspace`, `UserDefaults`, and `AXUIElement`. |
| `Sources/FruitDockApp` | Entry point only — constructs the composition root and starts the run loop. |
| `Tests/FruitDockCoreTests` | Domain tests, plus fakes for every system protocol. |
| `Tests/FruitDockUITests` | Tests for the parts of the AppKit layer that are plain logic. |
| `Resources/Info.plist` | Bundle metadata. Holds the stable `CFBundleIdentifier`. |
| `Scripts/make-app-bundle.sh` | Assembles and signs the `.app`. |

The guiding rule: **decisions live in pure functions in `FruitDockCore`**, and
the AppKit layer executes them without deciding anything. That is what lets a
test simulate unplugging a monitor by passing a shorter array. See
[CLAUDE.md](./CLAUDE.md) for the full conventions.

## Status

Under active early development. See [ROADMAP.md](./ROADMAP.md) for the phased
plan, [BACKLOG.md](./BACKLOG.md) for open concerns — including an explicit list
of what has and has not been verified on real hardware — and the
[issues](https://github.com/izaakwhite/fruit-dock/issues) for planned work.
