# fruit-dock

**Free and open source.** [GPLv3](./LICENSE).

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
./Scripts/run.sh
```

Look for the dock icon in your menu bar. Quit from that menu.

Nothing else is required — no Apple account, no certificate. The build signs
ad-hoc when it finds no certificate, which works fine; the only consequence is
that Accessibility permission has to be re-granted after each rebuild, and
[Code signing](#code-signing) explains how to stop that.

Two things do not travel with the repository, because macOS ties both to a
particular machine:

- **Accessibility permission** must be granted again on each Mac.
- **Signing certificates** are per-machine. Create one wherever you develop.

> **Use the bundle, not `swift run`.** `swift run FruitDockApp` is fine for a
> quick look, but it cannot hold the Accessibility permission — see
> [Permissions](#permissions-and-privacy).

## Development loop

`Scripts/run.sh` quits the running copy, rebuilds, signs, and relaunches.
Quitting first matters: fruit-dock has no window, so a stale copy left running
is invisible apart from a second menu-bar icon, and every click you test goes to
the old binary — which looks exactly like a fix that didn't work.

```sh
./Scripts/run.sh                 # the usual loop
./Scripts/run.sh --test          # run the suite first, stop if it fails
./Scripts/run.sh --reset         # wipe saved settings — restores first-launch behaviour
./Scripts/run.sh --release       # release configuration
./Scripts/run.sh --no-launch     # build and sign only
./Scripts/run.sh --help
```

`--reset` is the only way to exercise the first-launch path, where pinned apps
are seeded from your system Dock. After the first save, seeding never runs
again.

Tests alone need none of this — `swift test` is enough.

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

### ⚠️ If you sign ad-hoc, the permission won't survive a rebuild

macOS ties Accessibility grants to an app's *code signing identity*. With
**ad-hoc** signing that identity is derived from the binary, so any edit that
alters generated code produces a different app as far as macOS is concerned —
**the grant silently stops applying while System Settings still shows it
switched on.**

Measured on this project:

| Signing | Identity across a real code change | Grant survives? |
|---|---|---|
| Ad-hoc | changes | ❌ |
| **Apple Development certificate** | **unchanged** | ✅ |

The fix is free: create an Apple Development certificate and the build script
uses it automatically — see [Code signing](#code-signing). If you are signing
ad-hoc and placement stops working after an edit, remove fruit-dock from the
Accessibility list and add it again.

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

### A stable identity — still free, and worth it

Ad-hoc signatures change on every meaningful build, which is what breaks the
Accessibility grant. An **Apple Development** certificate fixes that and does
not require the paid Developer Program — any Apple ID will do.

Create one in Xcode: **Settings → Accounts → Manage Certificates → +
→ Apple Development**. The build script finds it automatically:

```sh
security find-identity -v -p codesigning   # confirm it is there
./Scripts/make-app-bundle.sh               # picks it up on its own
```

Set `FRUIT_DOCK_SIGN_IDENTITY` to choose between several certificates.

Why this works: TCC matches an app against its *designated requirement*. Ad-hoc
signing pins a `cdhash`, which changes whenever the binary does. A certificate
pins identity instead — bundle identifier plus the signing authority — and
nothing in that expression depends on the binary's contents, so the grant keeps
applying across rebuilds.

#### If your certificate exists but isn't found

`security find-identity -v` lists only identities whose **full chain**
validates, so a perfectly good certificate shows up as "0 valid identities"
when an intermediate is missing or expired. Check which generation issued it:

```sh
security find-certificate -c "Apple Development: you@example.com" -p \
  | openssl x509 -noout -issuer -dates
```

Look at the `OU=` in the issuer (`G3`, `G4`, …), download that generation from
<https://www.apple.com/certificateauthority/>, and add it:

```sh
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
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
| `Scripts/make-app-bundle.sh` | Assembles and signs the `.app`. Builds only. |
| `Scripts/run.sh` | The development loop: quit, rebuild, relaunch. |

The guiding rule: **decisions live in pure functions in `FruitDockCore`**, and
the AppKit layer executes them without deciding anything. That is what lets a
test simulate unplugging a monitor by passing a shorter array. See
[CLAUDE.md](./CLAUDE.md) for the full conventions.

## Licence

GPLv3 — see [LICENSE](./LICENSE). Free to use, study, change, and share; any
distributed build must come with its source under the same terms.

Code borrowed from other projects is recorded in
[THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md), which also sets out what may
and may not be brought in.

### Related projects

Both are GPLv3 and both are excellent. If they cover what you need, use them:

- **[DockDoor](https://github.com/ejbills/DockDoor)** — window previews on Dock
  hover, and a better Alt-Tab. Can lock the Dock to one monitor so it stops
  moving.
- **[Docky](https://github.com/josejuanqm/docky)** — a full Dock replacement,
  with widgets, folders, themes, and a built-in Launchpad.

fruit-dock does something neither does: **a dock on every display at once**, each
launching apps onto the display it sits on, staying out of the way of Apple's
Dock as that moves between screens.

## Status

Under active early development. See [ROADMAP.md](./ROADMAP.md) for the phased
plan, [BACKLOG.md](./BACKLOG.md) for open concerns — including an explicit list
of what has and has not been verified on real hardware — and the
[issues](https://github.com/izaakwhite/fruit-dock/issues) for planned work.
