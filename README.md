# fruit-dock

A macOS menu-bar utility that puts a dock on displays Apple's Dock isn't on.

Built with Swift 6, SwiftPM, and AppKit. See [ROADMAP.md](./ROADMAP.md) for
the phased implementation plan and [BACKLOG.md](./BACKLOG.md) for open
concerns and known gaps.

## Requirements

- macOS (Apple Silicon or Intel)
- [Xcode](https://developer.apple.com/xcode/) with the Swift 6 toolchain
  (`swift --version` should report 6.0 or later)
- No other dependencies — the package has no external SwiftPM dependencies

## Building

```sh
swift build
```

## Running

For everyday development, run it straight from SwiftPM:

```sh
swift run FruitDockApp
```

This launches fruit-dock as a menu-bar-only ("accessory") app — it has no
Dock icon and no app-switcher entry. Look for its icon in the menu bar. Quit
either from that menu or with `⌘Q`.

### Running as a proper `.app` bundle

`swift run` produces a bare binary with an identity that changes on every
rebuild, which matters if you're testing the Accessibility-permission-gated
window-placement feature: macOS ties that permission grant to the app's
identity, so a rebuilt bare binary silently loses the grant. To get a stable
`.app` bundle instead:

```sh
Scripts/make-app-bundle.sh          # debug build (default)
Scripts/make-app-bundle.sh release  # release build
open build/fruit-dock.app
```

Grant Accessibility permission to this bundle (not the bare binary) under
**System Settings → Privacy & Security → Accessibility**. See the comments at
the top of `Scripts/make-app-bundle.sh` for the full story, including a known
caveat about ad-hoc code signing across rebuilds.

## Testing

```sh
swift test
```

With coverage instrumentation:

```sh
swift test --enable-code-coverage
```

Coverage report:

```sh
xcrun llvm-cov report \
  .build/arm64-apple-macosx/debug/FruitDockPackageTests.xctest/Contents/MacOS/FruitDockPackageTests \
  -instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  -ignore-filename-regex='.build|Tests'
```

Tests are written with **swift-testing** (`import Testing`, `@Test`,
`#expect`), not XCTest. As of this writing, only `FruitDockCore` (the
platform-agnostic domain layer) has a test target — see
[BACKLOG.md](./BACKLOG.md) and open issues for the plan to bring the AppKit
shell under test.

## Project layout

| Path | Contains |
|---|---|
| `Sources/FruitDockCore` | Pure domain logic: models, decision functions (`DisplayReconciler`, `DockContentBuilder`), `DockCoordinator`, and the protocols that abstract system APIs. Imports no UI framework. |
| `Sources/FruitDockApp` | The AppKit shell: panels, views, and the `NSWorkspace`/`NSScreen`/`UserDefaults` wrappers, plus `main.swift`. |
| `Tests/FruitDockCoreTests` | Tests for the domain layer, including fakes for the system-API protocols. |
| `Resources/Info.plist` | Bundle metadata used by `Scripts/make-app-bundle.sh`. |
| `Scripts/make-app-bundle.sh` | Assembles and ad-hoc signs a stable `.app` bundle for permission-testing. |

For the architectural rules behind this split (why decisions live in pure
functions, why system APIs sit behind protocols) see
[CLAUDE.md](./CLAUDE.md).

## Status

This project is under active early development — see
[ROADMAP.md](./ROADMAP.md) for the current phase and
[BACKLOG.md](./BACKLOG.md) for known gaps, including which behavior has and
hasn't been verified on real hardware.
