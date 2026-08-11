# fruit-dock — Implementation Roadmap

**Status:** Draft v0.1
**Derived from:** SRS v0.1 (External Display Dock, macOS)
**Last updated:** 2026-08-11

---

## 0. Working assumptions

These are **assumed, not decided**. Each one changes the plan below if reversed.

| # | Assumption | Rationale | Reverses what? |
|---|---|---|---|
| A1 | Self-distribution (Developer ID + notarization), not Mac App Store | App Sandbox blocks launching arbitrary apps by path and process-activation APIs. Independently confirmed by the OSS ExtraDock project, which states it cannot be sandboxed for exactly these reasons. | FR-3, FR-6, FR-7 |
| A2 | v1 ships launch/focus-only — no Accessibility permission | `NSWorkspace` alone covers launch, activate, and running indicators. Zero permission prompts on first run. | FR-6 → v2 |
| A3 | Target macOS 26 Tahoe and later | Dev machine is 26.5.2. Supporting 14+ triples the visual-QA matrix (pre/post Liquid Glass). | SRS §2.4 |
| A4 | Single active dock in v1 | SRS §6.1 already defers multi-dock. | — |

### Open, and genuinely blocking

- **Pricing.** The $1 target in SRS §7 predates knowing a competitor sells this at $37.99 lifetime. At $1, break-even on the $99/yr Apple account alone is ~100 sales/yr. Resolve before Phase 7, ideally before Phase 0 — it determines whether this is a product or a personal tool.
- **Build vs. fork.** See Phase 0.1.
- **Visual identity** (SRS §7 Q2). Less urgent under A1 — App Store rejection risk is moot when not shipping to the App Store. Still a design decision, deferred to Phase 3.

---

## Phase 0 — Decide and set up

> Nothing compiles until this phase is done. No Xcode is currently installed.

### 0.1 Evaluate the fork option *(do this first — it can delete most of this roadmap)*

Clone [henningziech/extradock](https://github.com/henningziech/extradock) (MIT) and assess:

- [ ] Does it build and run on macOS 26.5.2? (README claims macOS 15+, predates Tahoe)
- [ ] Is the GitHub repo related to the commercial extradock.app? Same author? Does the paid product derive from MIT code?
- [ ] Read the display connect/disconnect handling specifically — that's the hard part of this problem and the best signal of code quality
- [ ] Is the code something you'd want to own and extend?

**Decision gate:**

| Outcome | Action |
|---|---|
| Builds, clean, good bones | Fork it. Skip to Phase 4, retrofit tests as you go. |
| Builds, messy | Study its AppKit workarounds, then greenfield. The `NSScreen` edge cases it solves are worth hours of your time. |
| Doesn't build / abandoned | Greenfield, Phase 1. Still read it for reference. |

MIT means you can fork commercially. You must retain the copyright notice.

### 0.2 Environment

- [ ] Install Xcode from the App Store (~10GB) — `xcodebuild` is currently absent, only Command Line Tools are present
- [ ] `sudo xcode-select -s /Applications/Xcode.app` and verify `xcodebuild -version`
- [ ] `git init` in this directory — not yet a repo
- [ ] **Defer** the $99 Apple Developer account until Phase 7. Local dev signs fine with a free Apple ID.

**Exit criteria:** `xcodebuild -version` succeeds; fork-vs-build decided and written down.

---

## Phase 1 — Walking skeleton

Goal: a menu bar agent that puts an empty window on a display you pick. No features. Proves the riskiest assumptions early.

- [ ] Xcode project, SwiftUI + AppKit interop, `LSUIElement = true` (FR-5.1)
- [ ] `NSStatusItem` with a Quit menu item
- [ ] Borderless, non-activating window pinned to the bottom edge of the built-in display (FR-2.1)
- [ ] Hardcode everything — no config, no persistence

**Why this shape:** proves *"can I even get a non-activating always-on-top window to sit on a specific screen under Tahoe"* before any architecture is committed. If Liquid Glass or a Tahoe window-management change breaks this, you want to know in week one, not week six.

**Exit criteria:** empty dock window visible on one display, app quits cleanly.

---

## Phase 2 — Core domain, behind protocols

> This is where the clean-code investment concentrates. `NSScreen` and `NSWorkspace` are effectively untestable — you cannot fake a monitor being unplugged in a unit test. Wrapping them is what makes the rest of the codebase testable at all.

### 2.1 Service protocols

Each system dependency gets a protocol, a real implementation, and a fake:

```
DisplayProviding      → NSScreen + didChangeScreenParametersNotification
WorkspaceProviding    → NSWorkspace (running apps, launch, activate)
ConfigurationStoring  → UserDefaults
LaunchAtLoginManaging → SMAppService
```

### 2.2 Conventions

| Rule | Why |
|---|---|
| Domain types are `struct`, not `class` | Value semantics; free equatability for tests |
| No singletons except one composition root | `NSWorkspace.shared` is referenced in exactly one file |
| Domain layer imports **no AppKit** | Enforces the boundary; a stray `import AppKit` in domain code is a review-blocker |
| Each service does one thing | `DisplayProviding` never touches app launching |
| All user-facing strings via `String(localized:)` from day one | NFR-6. Retrofitting localization is miserable. |

### 2.3 Tests

Unit tests against fakes for: display selection when the assigned display vanishes (FR-1.3), reattachment on reconnect (FR-1.4), running-app diffing (FR-3.3), config round-trip with fallback defaults (FR-4.2).

**Exit criteria:** domain logic is unit-tested with zero AppKit in the test target. Fakes can simulate display disconnect — the scenario NFR-5 says must not crash.

---

## Phase 3 — Dock UI

- [ ] SwiftUI dock view in `NSHostingView` — icon row, configurable size (FR-2.4)
- [ ] Running indicator dots (FR-3.3)
- [ ] Click → launch if not running, activate if running (FR-3.2)
- [ ] Right-click context menu: Quit, Remove from Dock (FR-3.5)
- [ ] Light/Dark mode (NFR-4)
- [ ] **Decide visual identity here** (SRS §7 Q2)

**Humble-object rule:** the view owns layout and nothing else. Every decision — *is this app running, should this icon show, what happens on click* — lives in a tested view model. If you find yourself wanting to unit-test a SwiftUI view, logic has leaked into it.

**Exit criteria:** functional dock. Icons launch and switch apps. Indicators track reality.

---

## Phase 4 — Persistence and preferences

- [ ] Pinned apps: add/remove via drag-and-drop and file picker (FR-3.1)
- [ ] Persist pinned list, position, size, display assignment, behavior (FR-4.1)
- [ ] Preferences window: display picker, position, size, auto-hide (FR-5.2, §5.1)
- [ ] Launch at login via `SMAppService` (FR-5.3)
- [ ] Restore on launch with fallback when the saved display is gone (FR-4.2)

**Versioned config from the first write.** A schema version field costs one line now and saves a migration crisis later.

**Exit criteria:** quit and relaunch restores exact prior state, including the missing-display fallback path.

---

## Phase 5 — Display resilience *(the actually hard part)*

Everything above is standard app development. This is where multi-display utilities fail, and where NFR-5 lives.

- [ ] Handle disconnect: hide, or reassign to primary, per preference (FR-1.3)
- [ ] Handle reconnect: reattach automatically (FR-1.4)
- [ ] Display sleep/wake
- [ ] Resolution and scale changes while docked
- [ ] Display rearrangement in System Settings
- [ ] Meet the <1s response budget (NFR-2)

**Manual QA matrix — automate none of this, it isn't automatable:**

| Scenario | Expected |
|---|---|
| Unplug host display while dock focused | No crash, no hang (NFR-5) |
| Unplug, quit, replug, relaunch | Restores to correct display |
| Sleep/wake with display attached | Dock still correct |
| Change host resolution while docked | Dock repositions |
| Reorder displays in System Settings | Assignment survives |

Displays must be identified by a **stable ID**, not array index — `NSScreen.screens` ordering is not guaranteed stable across reconfiguration. DockAnchor's hardware-fingerprinting approach is worth reading here.

**Exit criteria:** the full matrix passes on real hardware.

---

## Phase 6 — Polish

- [ ] Auto-hide with hover reveal and configurable delay (FR-2.3)
- [ ] Hover magnification (FR-2.4)
- [ ] Optional running-but-unpinned section (FR-3.4)
- [ ] **Profile against NFR-1: <1% idle CPU, <50MB.** Measure, don't assume. Polling `runningApplications` on a timer is the classic way to blow this budget — prefer KVO/notifications.
- [ ] Verify localization externalization (NFR-6)

---

## Phase 7 — Distribution

Only now does money change hands.

- [ ] Resolve pricing (see §0)
- [ ] $99/yr Apple Developer Program
- [ ] Developer ID signing + hardened runtime
- [ ] Notarization + stapling (NFR-3)
- [ ] **Test the download path on a Mac that has never seen the app** — Gatekeeper behavior differs from a locally built copy
- [ ] Licensing if commercial (FR-7): local validation, minimal network calls
- [ ] `.dmg` packaging

---

## Sequencing

```
Phase 0  ──► fork? ──► maybe skip to Phase 4
   │
   ▼
Phase 1 walking skeleton      ← riskiest AppKit assumptions, week 1
   ▼
Phase 2 domain + tests        ← clean-code investment concentrates here
   ▼
Phase 3 UI ──► Phase 4 persistence
   ▼
Phase 5 display resilience    ← where this class of app actually fails
   ▼
Phase 6 polish ──► Phase 7 ship
```

**Critical path:** Phase 0 (fork decision) and Phase 5 (resilience). Everything else is routine.

---

## Clean-code principles, summarized

1. **Wrap every system API in a protocol.** The single decision that makes this codebase testable.
2. **Domain layer imports no AppKit.** Mechanically enforceable, therefore actually enforced.
3. **Humble objects at the boundary.** Views and window controllers stay dumb; logic sits in tested types.
4. **Value types by default.**
5. **One composition root.** Dependencies injected, not reached for.
6. **Externalize strings from commit one.**
7. **Version persisted data from the first write.**
8. **Write the failing test for display-disconnect before the handler.** It's the requirement most likely to regress silently.

---

## Verification notes

Claims here about macOS 26 / Tahoe API behavior, Liquid Glass, and current Gatekeeper specifics were **not** verified against live Apple documentation — they postdate the assistant's training data. Confirm against current developer docs before relying on any of them architecturally.

Prior art referenced:
- [henningziech/extradock](https://github.com/henningziech/extradock) — MIT, Swift, closest match to this SRS
- [bwya77/DockAnchor](https://github.com/bwya77/DockAnchor) — MIT, display detection and fingerprinting
- [extradock.app](https://extradock.app/) — commercial competitor, $14.99/yr or $37.99 lifetime
