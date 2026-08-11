# Phase 0.1 — Fork Evaluation: henningziech/extradock

**Date:** 2026-08-11
**Evaluated commit:** `e9cdd80` (2026-03-16, 30 commits total)
**Toolchain:** Xcode 26.6 (17F113), macOS 26.5 SDK, Swift 6.3.3
**Host:** macOS 26.5.2, M1 MacBook Air

Resolves roadmap §0.1. Informs backlog **B2** (fork vs. greenfield) and **B3** (license provenance).

---

## Verdict

**It builds clean on Tahoe, and the hard part is done right.** The blocker is not technical.

| Criterion | Result |
|---|---|
| Builds on macOS 26.5 SDK / Xcode 26.6 | ✅ `** BUILD SUCCEEDED **` |
| Display identity handled correctly | ✅ keyed by `CGDirectDisplayID` |
| Connect/disconnect handling present | ✅ correct add/remove logic |
| Codebase size | ✅ 1,471 lines, 14 files — tractable |
| Architecture | ✅ Models / Views / Services / Windows |
| **Test coverage** | ❌ **zero — no test target, no test files** |
| **System APIs abstracted for testing** | ❌ `UserDefaults` / `NSScreen` used directly |
| **LICENSE file** | ❌ **absent — see B3** |

---

## Build result

```
xcodebuild -project ExtraDock.xcodeproj -scheme ExtraDock \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
→ ** BUILD SUCCEEDED **
```

Deployment target is `MACOSX_DEPLOYMENT_TARGET = 15.0`, and it compiles without modification against the 26.5 SDK. No deprecation walls, no Tahoe-specific breakage. One benign warning (`No AppIntents.framework dependency found`).

This retires the largest unknown in roadmap assumption **A3**: a macOS 15-targeted AppKit dock builds and links on Tahoe as-is.

---

## What it gets right

**Display identity — this is the one that matters.** Backlog T3 warned that `NSScreen.screens` ordering is unstable across reconfiguration and that indexing into it produces unreproducible bugs. ExtraDock never does this:

```swift
var panels: [CGDirectDisplayID: MirrorDockPanel] = [:]

static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}
```

Panels are keyed by stable hardware ID, and per-display enablement persists under that ID as its key. **T3 is solved here** — this file is worth reading regardless of the fork decision.

**Connect/disconnect logic is correct.** `refreshPanels()` observes `NSApplication.didChangeScreenParametersNotification`, closes panels for vanished IDs, creates panels for new ones, and defaults unknown displays to enabled. That's roadmap FR-1.3 and FR-1.4, working.

**Structure matches the roadmap's intended layering** — `Models/`, `Views/`, `Services/`, `Windows/` — arrived at independently.

---

## What it would need

None of these are disqualifying; they're the cost of adopting it.

1. **No tests at all.** No test target exists. Given the clean-code goal, this is the main retrofit.
2. **System APIs not injected.** `ScreenMonitor` calls `UserDefaults.standard` and `NSScreen.screens` directly, so its logic cannot be unit-tested — precisely the coupling roadmap Phase 2.1 exists to break. The fix is mechanical: extract `DisplayProviding` and `ConfigurationStoring`, inject via init. The logic itself is already small and correct; only its dependencies need inverting.
3. **`Services/` imports AppKit.** Roadmap Phase 2.2 wanted an AppKit-free domain layer. Here "Services" is AppKit-coupled, so the boundary would need redrawing.
4. **Minor:** the `NotificationCenter` observer is never removed (no `deinit`); `UserDefaults` dictionary parsing is duplicated across three accessors.

**Scope mismatch:** ExtraDock *mirrors the real Dock's* contents by reading Apple's Dock plist. The SRS specifies an *independently pinned* app list (FR-3.1). These are different products sharing a delivery mechanism. Adopting it means either accepting mirror-based behavior or replacing its data source — the panel/display layer is reusable, `DockConfigReader` largely is not.

---

## 🔴 Blocking issue: the license is not usable as-is

**There is no `LICENSE` file in the repository.** The only grant is line 72 of `README.md`:

```
## License

MIT
```

A bare word "MIT" with no copyright holder, no year, and no license text. GitHub's detector reports "MIT" from this, which is how it surfaced in earlier research — but that's a heuristic, not a grant.

For personal use this is a non-issue. **For a commercial product it is not sufficient** — there is no identified copyright holder to attribute, and no actual terms conveyed.

**This couples directly to backlog B1 (pricing):**

| If B1 lands on… | License risk |
|---|---|
| Personal tool / never distributed | Negligible — fork freely |
| Free & open source | Low — attribute the author, note the ambiguity |
| **Commercial product** | **Blocking — resolve before shipping** |

Resolution path: open an issue asking the author to add a proper `LICENSE` file with a copyright line. Low-cost, and it's a normal request. Until then, treat the code as **reference, not foundation**, for any commercial path.

---

## Recommendation

**Read it, don't fork it — yet.**

The middle path from roadmap §0.1 ("builds, but…") fits best, for two reasons that have nothing to do with code quality:

1. The license can't support a commercial fork today, and B1 is unresolved.
2. The product scope differs — Dock-mirroring vs. independent pinned list.

Concretely:
- **Do** lift the display-handling approach. `ScreenMonitor.swift` is 93 lines and solves T3; `MirrorDockPanel.swift` (325 lines) is the non-activating panel work that roadmap Phase 1 was scheduled to de-risk.
- **Don't** take it as a base until B1 and B3 are settled.
- **Phase 1 just got much cheaper.** Its purpose was proving a non-activating always-on-top panel works on Tahoe. A working build now exists on this machine — run it, confirm the behavior, and Phase 1 collapses to a confirmation step.

---

## Reproducing

```
git clone --depth 50 https://github.com/henningziech/extradock.git /tmp/extradock-eval
cd /tmp/extradock-eval
xcodebuild -project ExtraDock.xcodeproj -scheme ExtraDock \
  -configuration Debug -derivedDataPath /tmp/extradock-dd \
  CODE_SIGNING_ALLOWED=NO build
open /tmp/extradock-dd/Build/Products/Debug/ExtraDock.app
```

Built app is unsigned; Gatekeeper permits it since it was built locally rather than downloaded.
