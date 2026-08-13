# fruit-dock — Project Guidelines

A macOS menu-bar utility that puts a dock on the displays Apple's Dock isn't on.
Swift 6, SwiftPM, AppKit, macOS 26 host.

**Read alongside this:** [BACKLOG.md](./BACKLOG.md) for open concerns and their
severities, [ROADMAP.md](./ROADMAP.md) for phases, [EVALUATION.md](./EVALUATION.md)
for the prior-art assessment. Feature requests live as
[GitHub issues](https://github.com/izaakwhite/fruit-dock/issues).

---

## Commands

```
swift build
swift test                        # 134 tests, all must pass
swift run FruitDockApp            # quick run — see the warning below
./Scripts/make-app-bundle.sh      # real .app; REQUIRED for Accessibility work
open build/fruit-dock.app
```

> **`swift run` cannot hold Accessibility permission.** It produces a bare,
> ad-hoc-signed binary whose identity is derived from the binary itself, so
> every rebuild is a different application to macOS and any granted permission
> silently stops applying. Anything touching window placement must be tested via
> `Scripts/make-app-bundle.sh`, which signs with an Apple Development
> certificate when one is installed — that makes the identity stable across
> rebuilds and the grant persistent. See **T13** (resolved); it is the reason
> window placement appeared broken for a long time while the code was fine.

Coverage:
```
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/FruitDockPackageTests.xctest/Contents/MacOS/FruitDockPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='.build|Tests'
```

---

## Architecture

Two targets. The boundary between them is the single most important thing in
this codebase.

| Target | Contains | Rule |
|---|---|---|
| `FruitDockCore` | Models, pure decision functions, `DockCoordinator`, all protocols | **Imports no UI framework.** A stray `import AppKit` here is a review-blocker. |
| `FruitDockApp` | AppKit shell: panels, views, and the wrappers around `NSScreen`, `NSWorkspace`, `UserDefaults`, `AXUIElement` | Decides nothing. Executes plans, reports events. |

### Decisions live in pure functions

Every non-trivial rule is a pure function over plain values, in `FruitDockCore`:

| Function | Decides |
|---|---|
| `DisplayReconciler.plan` | which displays get a dock |
| `DockContentBuilder.elements` | what goes in it, in what order |
| `SystemDockPreferences` | how to read Apple's Dock plist |
| `ApplicationCatalog` | how installed apps are grouped |
| `WindowGeometry` | Cocoa ↔ Accessibility coordinate conversion |
| `WindowPlacementRules` | which window to move |
| `AccessibilityPromptPolicy` | when it is acceptable to prompt |

This is why a test can simulate unplugging a monitor by passing a shorter
array. **Keep new logic here.** If a rule ends up in a view or a provider, it
becomes untestable and, historically, wrong.

### System APIs go behind protocols

All in `SystemInterfaces.swift`, each with one real implementation in
`FruitDockApp` and a fake in `Tests/FruitDockCoreTests/Fakes.swift`:

`DisplayProviding` · `ApplicationProviding` · `ConfigurationStoring` ·
`DockPresenting` · `DockActionHandling` · `SystemDockReading` ·
`InstalledApplicationProviding`

Protocols return **raw values, not interpretations** — `SystemDockReading`
hands back untyped plist tiles precisely so the parsing stays in the domain
where it can be tested from literal fixtures.

`AppDelegate` is the only composition root. Nothing else reaches for globals.

---

## Hard-won lessons

Each of these cost real debugging time. They are the reason this file exists.

### Never claim runtime behaviour you have not observed

The most important rule here, and the one most often broken. Build success and
green tests prove neither that a feature runs nor that it looks right.

Say plainly what was verified and what was not: *"builds and tests pass;
runtime unverified"* is the honest form. An agent cannot launch this GUI app,
click an icon, or grant a permission — so it cannot know the feature works.
This was claimed twice for code that turned out to be completely dead.

### Testing a pure function proves nothing about wiring

Dock-follows-Dock shipped entirely non-functional with every test green. The
reconciler was correct and fully covered. **Nothing called it** — the trigger
relied on a notification that never fires for that event.

When adding anything callback-driven, add a `DockCoordinatorTests` case that
the subscription exists and that firing it produces the effect. Coverage of the
domain is not coverage of the product.

### Report coverage honestly

`FruitDockCore` sits around 97% line coverage. `FruitDockApp` — about 1,500
lines, and where **every** hand-found bug has lived — has no tests and does not
appear in the report at all. Quoting the domain figure alone is misleading.
Target 70%, 55% acceptable, and always say which number is meant.
Fixing this properly is [issue #5](https://github.com/izaakwhite/fruit-dock/issues/5).

### macOS specifics discovered here

- **TCC and code signing.** Covered above and in T13. Ad-hoc signatures change
  on any edit that alters codegen; a stable bundle identifier alone is not
  enough.
- **No notification exists for the system Dock's location.**
  `didChangeScreenParametersNotification` does *not* fire when the user moves
  Apple's Dock between displays — only `visibleFrame` changes. It is polled
  every 500ms, and only while more than one display is connected. (T10)
- **Non-activating panels need `acceptsFirstMouse`.** An accessory app is never
  frontmost, so *every* click is a first-mouse click and AppKit swallows them.
  Views must also claim `mouseDown` or the matching `mouseUp` never arrives.
  This made the dock appear to ignore clicks entirely.
- **Accessibility and Cocoa disagree on the origin.** Cocoa measures from the
  bottom-left of the primary display, `AXUIElement` from the top-left. Getting
  it backwards *looks correct* on side-by-side displays of equal height and only
  breaks on a display **above or below** the primary — so test vertical
  arrangements specifically.
- **`Dock.app` cannot be replaced.** It also owns Mission Control, Spaces, and
  Launchpad, and launchd restarts it. Coexisting is the only supportable design.
- **Swift 6 rejects some C globals.** `kAXTrustedCheckOptionPrompt` is a mutable
  global; its string value is spelled out instead. `AXFullScreen` has no
  constant at all (T12).

---

## Conventions

**Comments explain why, never what.** A comment earns its place by recording a
constraint, a rejected alternative, or a non-obvious consequence. Delete
anything restating the line below it.

**Respect the user's system settings.** Accessibility settings are not optional
— Reduce Transparency, Reduce Motion, Increase Contrast, Differentiate Without
Color. Read them live through `SystemAppearance` and observe changes; a dock
that only checks at launch ignores the setting. Use semantic `NSColor`s.

**Never write to `com.apple.dock`.** Read-only, always. It is another app's
defaults domain and the Dock rewrites it constantly.

**Persisted config decodes field by field with defaults.** Synthesized `Codable`
treats a missing key as an error, which would discard everything a user
configured when a field is added. Add new keys to `DockConfiguration.init(from:)`
*and* to `ConfigurationMigrationTests`.

**Identify displays by `DisplayID`, never by index.** `NSScreen.screens`
ordering is not stable across reconfiguration.

**Prefer notifications to polling.** Polling is how an idle menu-bar agent blows
the <1% CPU budget (NFR-1). The Dock-location poll is the one deliberate
exception and is scoped as narrowly as possible.

---

## Testing

- **swift-testing** (`import Testing`, `@Test`, `#expect`) — not XCTest.
- Test names are sentences describing behaviour; cite the requirement where one
  applies (`— FR-1.3`).
- Fakes and the shared `Fixture` namespace live in `Fakes.swift`. `Fixture.tile`
  reproduces the real `com.apple.dock` tile shape, verified against a live plist.
- Cover the failure mode, not the happy path: display disconnect, total display
  loss, malformed plist entries, deleted apps, settings that persist but don't
  refresh.

---

## Working in this repo

- **The backlog is live.** New concerns go in `BACKLOG.md` with a severity and a
  reason. Resolved ones move to the Resolved table with a date rather than being
  deleted, so the reasoning survives. Check the highest unused T-number before
  claiming one — two agents once picked T11 simultaneously.
- **Commit messages explain reasoning in prose paragraphs** — what was wrong,
  why this approach, what was rejected. Not bulleted change lists. End with the
  `Co-Authored-By` trailer.
- **Verify before asserting.** Read the file, run the command, check the output.
  The Xcode install here failed because a 403 HTML error page had been cached as
  a `.xip`; the misleading crash was diagnosed by checking the file's actual size
  and type.
- **Agents: work on a branch, commit, do not push.** Overlapping edits to
  `AppDelegate.swift`, `SystemInterfaces.swift`, and `BACKLOG.md` are the usual
  conflict points. If two agents run at once, one should use worktree isolation.

## Current state

Working: multi-display docks that follow Apple's Dock, pinning, running
indicators, recents, system-Dock import, an applications browser, hover labels,
fade transitions, and accessibility-setting support — all confirmed at runtime
by the user except where noted below.

**Not verified:** no window has ever been observed moving to the clicked display
(T11). That path is gated on Accessibility permission, which is in turn gated on
T13. Start there before assuming `WindowPlacer` is broken.
