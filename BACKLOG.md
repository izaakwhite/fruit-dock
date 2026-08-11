# fruit-dock — Backlog

**Status:** Open
**Last updated:** 2026-08-11
**Companion to:** [ROADMAP.md](./ROADMAP.md)

Concerns surfaced during SRS review and prior-art research. Nothing here is a task to execute yet — these are things that need a decision, a verification, or a deliberate acceptance of risk.

Severity: 🔴 blocks progress · 🟡 needs resolving before its phase · 🟢 track, don't act yet

---

## Blocking decisions

These have no technical answer. They are yours to make, and the roadmap branches on them.

### 🔴 B1 — Pricing is unresolved and the $1 target looks unviable
**Phase:** 0 (ideally) · **Blocks:** whether Phase 7 exists at all

SRS §1.2 targets a $1 price. Research since found [extradock.app](https://extradock.app/) selling the same concept at $14.99/yr or $37.99 lifetime. Meanwhile the Apple Developer Program is a $99/yr fixed cost.

At $1/unit that's ~100 sales annually just to break even on the account, before any value on your time. Three honest outcomes:

- **Personal tool** — build it, never sign it, run it locally. Cost: $0. Most of Phase 7 disappears.
- **Free / open source** — same as above, plus you owe users a Gatekeeper workaround story.
- **Real product** — price it against the competitor, not against $1.

Worth resolving early because it determines how much of Phase 7 you need, and whether polish work in Phase 6 is justified.

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

### 🟢 T6 — Config schema versioning
**Phase:** 4

Add a schema version field to persisted config on the very first write. One line now; avoids a migration crisis when the config shape changes post-release.

### 🟢 T7 — Localization externalization
**Phase:** 2 onward · **Source:** NFR-6

Use `String(localized:)` from the first UI commit even though only English ships. Retrofitting is disproportionately painful.

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
| T2 | Phase 1 window behavior unproven | Substantially de-risked. ExtraDock's non-activating `NSPanel` implementation builds and links against the 26.5 SDK. Not yet confirmed at runtime — launch the built app to close this out fully. | 2026-08-11 |
