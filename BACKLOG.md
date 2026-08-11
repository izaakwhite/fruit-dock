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
| T2 | Phase 1 window behavior unproven | Substantially de-risked. ExtraDock's non-activating `NSPanel` implementation builds and links against the 26.5 SDK. Not yet confirmed at runtime — launch the built app to close this out fully. | 2026-08-11 |
