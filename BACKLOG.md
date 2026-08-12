# fruit-dock — Backlog

**Status:** Open
**Last updated:** 2026-08-11
**Companion to:** [ROADMAP.md](./ROADMAP.md)

Concerns surfaced during SRS review and prior-art research. Nothing here is a task to execute yet — these are things that need a decision, a verification, or a deliberate acceptance of risk.

Severity: 🔴 blocks progress · 🟡 needs resolving before its phase · 🟢 track, don't act yet

---

## Blocking decisions

These have no technical answer. They are yours to make, and the roadmap branches on them.

### ✅ B1 — Pricing — RESOLVED 2026-08-11

**Decision: $5 lifetime as an early-adopter price, raised for new users once the product gains traction. Existing buyers grandfathered.**

Break-even: at ~10% processor fees, $5 nets ~$4.50, so the $99/yr Apple Developer account is covered by **~22 sales/year** (vs. ~100 at the original $1). Viable.

Positioning: $5 against a $37.99 lifetime competitor is a deliberate ~7× undercut to buy early adoption.

**Consequences — this decision propagates:**
- **This is now a commercial product**, so **B3 (no LICENSE file on ExtraDock) is genuinely blocking**, not academic.
- Phase 7 stays in scope in full: Developer ID, notarization, licensing infrastructure.
- Three new concerns created — see *Commercial / licensing* below.

### 🔴 B2 — Fork vs. greenfield undecided
**Phase:** 0 · **Blocks:** Phases 1–3

[henningziech/extradock](https://github.com/henningziech/extradock) (MIT, Swift, 39 commits, last touched March 2026) implements most of the SRS functional requirements. If it builds cleanly on Tahoe, forking skips Phases 1–3 entirely.

Evaluation criteria are in ROADMAP.md §0.1. This is an hour of work that could delete weeks.

### 🔴 B3 — There is no LICENSE file (escalated 2026-08-11)
**Phase:** 0 · **Blocks:** B2 · **Evidence:** [EVALUATION.md](./EVALUATION.md)

Worse than originally assessed. The repo contains **no `LICENSE` file at all**. The only grant is line 72 of README.md — the bare word `MIT`, with no copyright holder, no year, and no license text. GitHub's "MIT" label is a detector heuristic reading that line, not an actual grant.

Fine for personal use. **Not sufficient for a commercial product** — no identified copyright holder to attribute, no terms conveyed.

Couples to B1: negligible risk if this becomes a personal tool, blocking if it becomes a product. Resolution is cheap — open an issue asking the author to add a proper LICENSE file.

Separately, whether the MIT repo and the commercial extradock.app are the same codebase remains unestablished.

### 🟡 B4 — The core premise may be partly solved by macOS already
**Phase:** 0 · **Blocks:** scope

macOS natively moves the Dock to whichever display you push the cursor to the bottom edge of. The genuine gaps are *simultaneous* docks on multiple displays and *pinning* one permanently.

Spend ten minutes confirming the native gesture doesn't already cover your actual daily workflow. If it does, this becomes a much smaller project — or none.

### 🟡 B5 — Minimum macOS version
**Phase:** 0 · **Source:** SRS §7 Q4

SRS says "macOS 14+"; dev machine is 26.5.2. Supporting 14+ spans the Liquid Glass design break and roughly triples visual QA. Roadmap assumes 26+ (assumption A3). Confirm or reverse.

**Still open after #4 (2026-08-12).** Liquid Glass adoption did not force this decision: `NSGlassEffectView` is guarded behind `@available(macOS 26, *)` with the pre-existing `NSVisualEffectView` material as the fallback on 15–25, so `Package.swift` stays at `.v15`. That sidesteps B5 rather than answering it — the two material code paths now both need visual QA on every future change, which is exactly the cost this item is about.

---

## Environment blockers

### ✅ E1 — Xcode not installed — RESOLVED 2026-08-11

Xcode 26.6 (17F113) installed at `/Applications/Xcode-26.6.0.app`, macOS 26.5 SDK, Swift 6.3.3. Verified by building a real project.

### 🟢 E2 — Apple Developer Program ($99/yr) not purchased
**Phase:** 7

Deliberately deferred. Local development signs fine with a free Apple ID. Only needed for Developer ID signing and notarization. Do not buy until B1 is settled.

### 🟡 E3 — Not a git repository
**Phase:** 0

`fruit-dock/` is not under version control. Run `git init` before any code lands.

---

## Technical risks

### 🔴 T1 — All macOS 26 / Tahoe claims are unverified
**Phase:** all

Every statement in the roadmap about Tahoe APIs, Liquid Glass, and current Gatekeeper behavior comes from an assistant whose training data predates macOS 26. None of it was checked against live Apple documentation.

Treat the roadmap's API-level assertions as hypotheses. Verify before building on them architecturally. This is the single largest source of unknown-unknowns in the plan.

### 🔴 T2 — The Phase 1 window behavior is unproven
**Phase:** 1

The whole product rests on being able to pin a borderless, non-activating, always-on-top window to a chosen display. Under Tahoe this is assumed, not demonstrated. That's precisely why Phase 1 is scoped as an empty walking skeleton — to fail fast if the assumption is wrong.

### 🟢 T3 — Display identity must be stable, not positional
**Phase:** 5 · **Reference solution found 2026-08-11**

ExtraDock solves this correctly — panels keyed by `CGDirectDisplayID` obtained from `screen.deviceDescription["NSScreenNumber"]`, never by array index. See [EVALUATION.md](./EVALUATION.md). Downgraded from 🟡: the approach is now known, just needs implementing.

Original concern retained below.

`NSScreen.screens` ordering is not guaranteed stable across display reconfiguration. Identifying the host display by array index will produce bugs that only reproduce after unplug/replug or reordering in System Settings — the worst kind to debug.

Use a stable hardware identifier. [DockAnchor](https://github.com/bwya77/DockAnchor) fingerprints displays and is worth reading.

### 🟡 T4 — NFR-1 performance budget is easy to blow
**Phase:** 6

<1% idle CPU and <50MB is achievable but not free. The classic failure is polling `NSWorkspace.runningApplications` on a timer. Prefer KVO or workspace notifications. Measure with Instruments rather than assuming.

### 🟡 T5 — Gatekeeper friction if shipping unsigned
**Phase:** 7 · **Depends on:** B1

Unsigned apps downloaded from the internet are quarantined, and Apple has been steadily removing the easy bypasses. If B1 lands on "free tool," the distribution story is *ship source, build locally* — locally built apps are never quarantined. Binary distribution without signing is a poor user experience.

### 🔴 T8 — Dock must respect the user's system settings
**Phase:** 3/6 · **Added 2026-08-11**

A dock that ignores the settings the user already configured for the system Dock reads as broken, not as customisable. Three tiers, in priority order.

**Tier 1 — accessibility. Non-negotiable, and currently violated.**

`DockPanel` hardcodes `NSVisualEffectView` with `.hudWindow`, which ignores **Reduce Transparency**. A user who turned that on gets exactly the effect they asked the system not to produce. Honour, via `NSWorkspace.shared`:

| Setting | Property | Effect on us |
|---|---|---|
| Reduce Transparency | `accessibilityDisplayShouldReduceTransparency` | Solid background instead of blur |
| Reduce Motion | `accessibilityDisplayShouldReduceMotion` | Skip magnification/hide animations |
| Increase Contrast | `accessibilityDisplayShouldIncreaseContrast` | Stronger borders, higher-contrast indicators |
| Differentiate Without Color | `accessibilityDisplayShouldDifferentiateWithoutColor` | Running indicator must not rely on colour alone |

These change at runtime — observe `NSWorkspace.didChangeAccessibilityDisplayOptionsNotification`, don't read once at launch.

**Tier 2 — inherit the system Dock's preferences as defaults.**

Read `com.apple.dock` and use it to seed our own settings, so a new install already matches the user's habits rather than starting at arbitrary values:

| Key | Meaning |
|---|---|
| `tilesize` | icon size — should seed `DockConfiguration.iconSize` |
| `magnification`, `largesize` | hover magnification, and its target size |
| `orientation` | `bottom`/`left`/`right` — should seed `DockConfiguration.edge` |
| `autohide`, `autohide-delay`, `autohide-time-modifier` | auto-hide behaviour and timing |
| `show-process-indicators` | whether running dots appear at all |
| `mineffect` | minimise animation |

Seed-then-diverge, not slave-to: once the user changes one of our settings, ours wins. Read-only — never write to `com.apple.dock`.

**Partly done 2026-08-11.** The reading half exists: `SystemDockDefaultsReader` opens the domain read-only, `SystemDockPreferences` parses the tile shape, `persistent-apps` can be imported on demand, `recent-apps` drives a dock section, and `show-recents` seeds `showsRecentApps` on first launch only. The settings in the table above — `tilesize`, `orientation`, `magnification`, `autohide`, `show-process-indicators` — are still unread, and each needs somewhere in `DockConfiguration` to land before it can be seeded.

**Tier 3 — general system appearance.** Light/dark (NFR-4), accent and highlight colour, and menu bar auto-hide interactions. Use semantic `NSColor`s throughout so most of this is automatic; the current code already does.

**Related:** the OSS ExtraDock reads the Dock plist directly and watches it with a file watcher, which is why it cannot be sandboxed. Reading via `UserDefaults(suiteName: "com.apple.dock")` is the lighter-touch route for Tier 2.

### 🔴 T9 — The AppKit shell has no tests, and that is where bugs are
**Phase:** 2 · **Added 2026-08-11**

The dock-follows-Dock feature shipped completely non-functional while every test passed. The reconciler was correct and well covered; **nothing ever called it**, because the trigger relied on a notification that does not fire for that event.

The tests proved the decision was right. They could not prove anything asked for a decision.

That gap is structural, not a one-off. `FruitDockCore` is well covered; `FruitDockApp` — `DockCoordinator`, `SystemDisplayProvider`, panel lifecycle — has zero coverage, and every bug found by hand so far has lived there.

`DockCoordinator` is testable today. It takes `DisplayProviding`, `ApplicationProviding`, and `ConfigurationStoring` as protocols precisely so fakes can be substituted; the fakes were simply never written. Worth covering:

- A display-change callback actually triggers reconciliation
- A running-apps change actually triggers a content refresh
- Panels are created and torn down as plans dictate
- Settings changes persist *and* refresh, rather than one or the other
- Toggling a display off, then on, restores its panel

**Lesson worth keeping:** a pure function tested in isolation says nothing about whether it is wired up. Coverage of the domain is not coverage of the product.

### 🟡 T10 — No notification exists for the system Dock's location
**Phase:** 5 · **Added 2026-08-11**

Recorded because it is unobvious and cost real time. `NSApplication.didChangeScreenParametersNotification` does **not** fire when the user moves Apple's Dock between displays: no screen parameter changes, only the space the Dock reserves, which surfaces as a different `visibleFrame`.

Current workaround is a 500ms poll, scheduled only while more than one display is connected. It is the deliberate exception to the no-polling rule in NFR-1 — a few rect comparisons, and with one display the Dock has nowhere to move.

Revisit if a real notification is ever found. Any future code that assumes screen-parameter notifications cover Dock movement will have this same bug.

### 🔴 T11 — No window has been observed moving
**Phase:** 3 · **Added 2026-08-11**

`WindowPlacer` has never been seen to reposition anything. It cannot be: the assistant that wrote it cannot launch a GUI app, click a dock icon, or grant Accessibility permission, and the whole feature is gated on a permission that only a human can give. The likeliest explanation for the original "it does nothing" report was simply that permission was never granted, which the code then swallowed in a silent `guard`. That guard now prompts and the menu reports the state, but **whether a window ever lands on the clicked display remains entirely unverified.**

The arithmetic and the which-window rule were extracted into `FruitDockCore` (`WindowGeometry`, `WindowPlacementRules`) and are covered by tests with literal coordinates. That covers being *wrong*; it says nothing about being *wired*, which is the T9 lesson.

Worth confirming by hand, in this order:

- Grant permission and check the menu item flips to "Opening Apps on the Clicked Display" with a checkmark.
- Click a single-window app's icon on the second display — does its window arrive?
- Click a multi-window app's icon. Only the frontmost window should move; the rest must stay put.
- Repeat on a display *above* or *below* the primary, not merely beside it. Everything vertical is where the coordinate flip bites, and a side-by-side arrangement of equal-height displays hides it.
- Click the same app on two displays in quick succession; the window should end on the second, not oscillate.

**Read T13 first — it may make all of the above impossible to test as things stand.**

### 🔴 T13 — Accessibility permission cannot survive a code change
**Phase:** 3 · **Added 2026-08-11 · Partly CONFIRMED 2026-08-12**

The agent's original diagnosis was right, and the signing half is now measured rather than suspected.

`swift run FruitDockApp` produces a bare, ad-hoc-signed Mach-O in `.build/` with an identifier derived from the binary itself:

```
Identifier=FruitDockApp-5555494492c65f84580d3753b69778598c4c2a47
Signature=adhoc    TeamIdentifier=not set
```

**Partial fix shipped.** `Scripts/make-app-bundle.sh` and `Resources/Info.plist` build a real `.app` at a fixed path with a fixed `CFBundleIdentifier` (`com.izaakwhite.fruit-dock`), signed with an explicit `--identifier`. That half is solved and verified.

**What is still broken, measured directly:**

| Scenario | CDHash |
|---|---|
| Rebuild, no source change | unchanged ✅ |
| Rebuild after a comment-only edit | unchanged ✅ |
| **Rebuild after a real code change** | **changes** ❌ |

Swift's build is deterministic, so an unchanged binary keeps its hash — but any edit that alters codegen produces a new one. If TCC keys Accessibility on the code directory hash (likely for ad-hoc signatures, since there is no stable certificate to key on instead), **the grant lapses on every meaningful build**, silently, with the entry still ticked in System Settings.

Not yet confirmed end to end: nobody has granted permission, seen placement work, changed code, rebuilt, and watched it stop. That experiment is the remaining unknown, and it is cheap.

**Likely real fix:** sign with a stable identity rather than ad-hoc. A free Apple Development certificate is enough and does not need the $99 account (see E2). Phase 7 wants proper signing regardless.

**Implication for T11:** every by-hand verification step listed there must be run against `build/fruit-dock.app`, never `swift run`, and permission re-granted after any rebuild until this is resolved.

### 🟡 T14 — Reading `com.apple.dock` returns nothing under App Sandbox
**Phase:** 7 · **Depends on:** T5 · **Added 2026-08-11**

*(Renumbered from T11 — both agents independently claimed that number.)*

Dock import, the recents section, and the `show-recents` seed all read another application's defaults domain. Unsandboxed that is an ordinary read and works. Inside the App Sandbox, `UserDefaults(suiteName: "com.apple.dock")` resolves against our own container instead and comes back empty, with no error to distinguish that from a Mac whose Dock is genuinely bare. Scanning `/Applications` has the same shape.

The failure is silent, which is what makes it worth recording: three features would quietly become no-ops rather than complain. Assumption A1 already rules out the Mac App Store for unrelated reasons, so this only bites if sandboxing is ever revisited — at which point it needs either a temporary-exception entitlement or code that detects the empty case and says so, instead of showing an empty menu.

### 🟡 T12 — Full-screen detection relies on an undocumented attribute
**Phase:** 3 · **Added 2026-08-11**

`WindowPlacer` reads `AXFullScreen` to avoid trying to move a window that owns its own Space. There is no `kAX…` constant for it — the name is convention among window managers, not published API, and Apple could drop it.

Failure is benign by construction: an absent attribute reads as "not full-screen", and the `AXUIElementIsAttributeSettable` check is expected to reject the move anyway. So this degrades to a redundant belt rather than a broken feature. Recorded because a future reader will wonder why one attribute in that file is a string literal.

### 🟢 T6 — Config schema versioning
**Phase:** 4

Add a schema version field to persisted config on the very first write. One line now; avoids a migration crisis when the config shape changes post-release.

### 🟢 T7 — Localization externalization
**Phase:** 2 onward · **Source:** NFR-6

Use `String(localized:)` from the first UI commit even though only English ships. Retrofitting is disproportionately painful.

---

## Feature requests

Tracked as GitHub issues; summarised here so this file stays the single place to look. Added 2026-08-12.

| # | Item | Severity | Note |
|---|---|---|---|
| [#1](https://github.com/izaakwhite/fruit-dock/issues/1) | Dock bar should behave like the macOS menu bar | 🟢 | Decided — see below. Coexist/replace now exposed as a user setting |
| [#2](https://github.com/izaakwhite/fruit-dock/issues/2) | Guarantee windows open on the clicked display | 🔴 | Partially built, never observed working |
| [#3](https://github.com/izaakwhite/fruit-dock/issues/3) | Hover behaviour should match Apple's Dock | 🟡 | Current values chosen by eye, not measured |
| [#4](https://github.com/izaakwhite/fruit-dock/issues/4) | Liquid Glass support (macOS 26) | 🟡 | **Research required** — post-dates training data |
| [#5](https://github.com/izaakwhite/fruit-dock/issues/5) | Coverage for `FruitDockApp` | 🔴 | ~70% of the code is unmeasured |

### 🟢 #1 decided: coexist by default, dynamically, and it's a user choice

"Behave like the menu bar" and "never render two docks on one screen" pulled in opposite directions. Resolved 2026-08-12: **coexist** is the default — never render on the display Apple's Dock currently occupies, and follow it live as it moves, so every display keeps exactly one dock. This is not new behaviour so much as newly-confirmed behaviour: `DockCoordinator`'s existing display-change wiring (`SystemDisplayProvider`'s 500ms Dock-location poll → `refreshDisplays()` → `DisplayReconciler.plan`) already does this correctly and is already covered by `DockCoordinatorTests` — "Our dock trades places when the system Dock moves". Nothing in the reconciliation logic needed to change.

What *was* missing: a way for the user to choose reading **(b)** instead — render everywhere, matching the menu bar literally, accepting two docks on one screen. `avoidsSystemDockDisplay` could already express either value, and `setAvoidsSystemDockDisplay(_:)` and the "Skip Display with macOS Dock" menu checkbox already wrote it, and this too is already covered — "Turning off Dock avoidance reclaims that display". Added in the #1 PR: `PreferencesWindowController`, a proper settings window presenting the same choice as an explicit Coexist/Replace decision (`SystemDockRelationship`), reachable via a new "fruit-dock Settings…" (⌘,) menu item, alongside the existing checkbox — both read and write the same `avoidsSystemDockDisplay`, so neither can drift from the other.

### 🔴 #2 cannot be a literal guarantee

Placement depends on Accessibility permission the user can decline, on apps that may refuse to move, and on windows that cannot be moved at all (full-screen, minimised). The achievable goal is **reliable best-effort with visible failure** rather than a silent no-op — never a guarantee. Failing to place must not mean failing to switch.

### 🟡 #4 must not regress T8 Tier 1

Whatever Liquid Glass turns out to be, Reduce Transparency still wins. A user who asked the system for less transparency must get a solid background.

**Addressed in code 2026-08-12, unverified on hardware.** `NSGlassEffectView` is real (confirmed against live Apple docs, not assumed — see the #4 PR description for sources) and is now adopted in `DockPanel` and `HoverLabelPanel`, gated behind `@available(macOS 26, *)` with the existing `NSVisualEffectView` path retained for 15–25. The Reduce Transparency check runs first in both files and short-circuits to the solid-fill path regardless of OS version, so it wins over both materials, not just the old one. `HoverLabelPanel` previously had no Reduce Transparency handling at all — that gap is closed here too, and `DockPanel.refreshAppearance()` now rebuilds the hover label as well as the dock itself so a live toggle reaches both windows. None of this has been seen running: this container has no Swift toolchain, so it is unverified in light mode, dark mode, and under Reduce Transparency/Increase Contrast, on real hardware.

---

## Commercial / licensing

Created by the B1 decision (2026-08-11).

### 🔴 C1 — "Lifetime" is an unbounded liability at $5
**Phase:** 7 · **Decide before first sale**

"Lifetime" is the riskiest word in the pricing decision. It commits you to perpetual updates for a one-time $4.50 net, on a platform that ships a breaking OS release every year. This app is unusually exposed to that — it depends on `NSScreen`, non-activating panel behavior, and Dock-adjacent APIs, all of which Apple can and does change. The competitor charges $37.99 for the same promise; at $5 you carry ~7× the obligation per dollar.

Note this repo already contains evidence of the risk: ExtraDock targets macOS 15 and needed no changes for 26 — but Liquid Glass landed in 26 and a visual overhaul is exactly the kind of unpaid work "lifetime" obliges.

Define the scope of "lifetime" **before** the first sale, since you cannot narrow it afterward. Common options:
- Lifetime updates within a major version; v2 is a paid upgrade *(recommended — industry-standard, keeps the door open)*
- Perpetual fallback: pay once, get 1 year of updates, keep using the last version you're entitled to forever (the Sketch model)
- Truly unlimited *(simplest to market, hardest to sustain)*

### 🟡 C2 — Merchant of record needed for VAT / sales tax
**Phase:** 7

Selling software internationally creates VAT and sales-tax obligations from the first sale. At this scale, use a platform that acts as **merchant of record** and absorbs that compliance — Paddle, Lemon Squeezy, or Gumroad. Raw Stripe does **not**; it leaves the liability with you.

The fee difference is irrelevant next to handling EU VAT registration yourself.

### 🟡 C3 — Grandfathering requires the license system to record a tier
**Phase:** 7 · **Depends on:** C1

The plan raises prices later while honoring early buyers. That's only possible if each license records **what it entitled the holder to at purchase time** — price tier, purchase date, and entitlement scope.

Cheap to build in now, effectively impossible to reconstruct later. Bake purchase tier into the license payload from the first key issued, even if v1 only ever reads one value.

### 🟢 C4 — Pricing is not the distribution problem
**Phase:** post-launch

"Once word spreads" carries most of the risk in this plan. The OSS ExtraDock has 1 star after 30 commits — building the thing is demonstrably not the same as being found. Discovery, not price, is the binding constraint on reaching even 22 sales/year.

Worth a deliberate launch plan (r/macapps, Hacker News, Product Hunt) rather than assuming word of mouth.

---

## Deferred scope

Recorded so they don't silently reappear as scope creep.

| ID | Item | Deferred to | Source |
|---|---|---|---|
| 🟢 D1 | Accessibility-gated window switching, "Show All Windows" | v2 | Assumption A2, SRS FR-6 |
| 🟢 D2 | Simultaneous docks on multiple displays | v2 | SRS §6.1 |
| 🟢 D3 | Visual identity — Dock-alike vs. distinct | Phase 3 | SRS §7 Q2 |
| 🟢 D4 | Per-Space configs, window thumbnails, iCloud sync | future | SRS §6.2–6.4 |
| 🟢 D5 | Running-but-unpinned app section | Phase 6 | SRS FR-3.4 |

---

## Resolved

| ID | Item | Resolution | Date |
|---|---|---|---|
| E1 | Xcode not installed | Xcode 26.6 (17F113) installed, macOS 26.5 SDK, Swift 6.3.3. Verified by building a real project. Note: `xcodes` cached a 403 HTML error page as a `.xip`, causing a misleading trace trap — root cause was an unaccepted Apple Developer agreement, not the download. | 2026-08-11 |
| E3 | Not a git repository | `git init`, committed, pushed to private repo `izaakwhite/fruit-dock`. Remote uses HTTPS (no SSH key on this machine). | 2026-08-11 |
| T2 | Phase 1 window behavior unproven | **Fully verified at runtime.** A borderless `.nonactivatingPanel` renders on the correct display, pins to any edge, and confirmed does **not** steal focus — typing continues uninterrupted in the frontmost app while the dock is clicked. This was the riskiest assumption in the plan. | 2026-08-11 |
| T8 Tier 1 | Accessibility settings ignored | Reduce Transparency now yields a solid background, Reduce Motion collapses transitions, Increase Contrast adds borders. Read live and observed via `accessibilityDisplayOptionsDidChangeNotification`. Tiers 2 and 3 remain open. | 2026-08-11 |
