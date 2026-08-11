# fruit-dock — Project Guidelines

A macOS menu-bar utility that puts a dock on displays Apple's Dock isn't on.
Swift 6, SwiftPM, AppKit. See [ROADMAP.md](./ROADMAP.md) for phases and
[BACKLOG.md](./BACKLOG.md) for open concerns.

---

## Commands

```
swift build                      # build
swift test                       # run tests
swift run FruitDockApp           # launch (menu-bar agent; ⌘Q or menu to quit)
swift test --enable-code-coverage
```

Coverage report:
```
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/FruitDockPackageTests.xctest/Contents/MacOS/FruitDockPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='.build|Tests'
```

---

## Architecture

Two targets, and the boundary between them is the point.

| Target | Contains | Rule |
|---|---|---|
| `FruitDockCore` | Domain: models, pure decision functions, `DockCoordinator`, protocols | **Imports no UI framework.** A stray `import AppKit` here is a review-blocker. |
| `FruitDockApp` | AppKit shell: panels, views, `NSWorkspace`/`NSScreen`/`UserDefaults` wrappers, `main.swift` | Decides nothing. Executes plans and reports events. |

**Decisions live in pure functions.** `DisplayReconciler` decides which displays get a dock; `DockContentBuilder` decides what goes in it. Both take values and return values. This is why a test can simulate unplugging a monitor by passing a shorter array.

**System APIs go behind protocols** (`SystemInterfaces.swift`). `NSScreen`, `NSWorkspace`, and `UserDefaults` are process-global and unfakeable; each has exactly one real implementation and a fake in `Tests/.../Fakes.swift`. When you need a new system capability, add a protocol method — don't reach for the global.

**One composition root.** `AppDelegate` constructs everything and injects it. Nothing else reaches for shared state.

---

## Hard-won lessons

These cost real debugging time. Read before touching the relevant area.

### Never claim runtime behavior you haven't observed

The most important rule here. Twice I described implemented code as though I'd watched it work — once for a transition that never fired at all. Build success and passing tests prove neither that a feature runs nor that it looks right.

State plainly what was verified and what wasn't: "builds and tests pass; runtime unverified" is the honest form. This is a GUI app on the user's machine — only they can confirm visual and interactive behavior.

### Testing a pure function proves nothing about wiring

The dock-follows-Dock feature shipped completely non-functional with every test green. `DisplayReconciler` was correct and fully covered. **Nothing called it.**

When adding a feature driven by a callback, write a test that the callback is subscribed and that firing it produces the effect. `DockCoordinatorTests` exists for this; extend it rather than only testing the new pure function.

### Report coverage honestly

`FruitDockCore` sits above 95%. `FruitDockApp` has no tests and doesn't appear in the coverage report at all — it's ~70% of the code. Quoting the domain figure alone is misleading. Target is 70%, 55% acceptable; always say which number you mean.

Every bug found by hand so far has lived in the unmeasured half.

### macOS gotchas discovered here

- **No notification exists for the system Dock's location.** `didChangeScreenParametersNotification` does *not* fire when the user moves Apple's Dock between displays — no screen parameter changes, only `visibleFrame`. It is polled every 500ms, and only while >1 display is connected. (Backlog T10.)
- **Non-activating panels need `acceptsFirstMouse`.** An accessory app is never frontmost, so *every* click is a first-mouse click and AppKit swallows them. Views must also claim `mouseDown` or the matching `mouseUp` never arrives.
- **Accessibility and Cocoa coordinates disagree.** Cocoa measures from the bottom-left of the primary display, `AXUIElement` from the top-left. Getting it backwards looks correct on a single display whose origin is zero — which is what makes it ship.
- **`Dock.app` cannot be replaced.** It also owns Mission Control, Spaces, and Launchpad, and launchd restarts it. Coexisting is the only supportable design.
- **Swift 6 rejects some C globals.** `kAXTrustedCheckOptionPrompt` is a mutable global; its string value is spelled out instead.

---

## Conventions

**Comments explain why, never what.** The code says what. A comment earns its place by recording a constraint, a rejected alternative, or a non-obvious consequence. Delete anything that restates the line below it.

**Respect the user's system settings.** Accessibility settings are not optional — Reduce Transparency, Reduce Motion, Increase Contrast, Differentiate Without Color. Read them live via `SystemAppearance` and observe changes; a dock that only checks at launch ignores the setting. Use semantic `NSColor`s throughout. (Backlog T8.)

**Persisted config decodes field by field with defaults.** Synthesized `Codable` treats a missing key as an error, which would discard everything a user configured when a field is added. See `DockConfiguration.init(from:)` and `ConfigurationMigrationTests`.

**Identify displays by `DisplayID`, never by index.** `NSScreen.screens` ordering is not stable across reconfiguration. Positional identity produces bugs that only reproduce after unplug/replug.

**Prefer notifications to polling.** Polling on a timer is how an idle menu-bar agent blows the <1% CPU budget (NFR-1). The Dock-location poll is the one deliberate exception, and it is scoped as narrowly as possible.

---

## Testing

- Framework is **swift-testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- Test names are sentences describing behavior, not method names. Reference the requirement ID where one applies (`— FR-1.3`).
- Fakes live in `Tests/FruitDockCoreTests/Fakes.swift`; `Fixture` holds shared sample displays and apps.
- Cover the failure mode, not just the happy path: display disconnect, total display loss, settings that persist but don't refresh.

---

## Workflow

- **Backlog is live.** New concerns go in `BACKLOG.md` with a severity and a reason; resolved ones move to the Resolved table with a date rather than being deleted, so the reasoning survives.
- **Commit messages explain the reasoning**, in prose paragraphs — what was wrong, why this fix, what was rejected. Not bulleted change lists. End with the `Co-Authored-By` trailer.
- **Verify before asserting.** Read the file, run the command, check the output. The Xcode install this session failed because a 403 HTML error page was cached as a `.xip`; the misleading crash it caused was resolved by checking the file's actual size and type.
