# Third-party notices

fruit-dock is licensed under the [GNU General Public License v3.0](./LICENSE).

This file records code and ideas taken from other projects. It exists so that
attribution is a step in the work rather than an audit afterwards — reconstructing
where a fragment came from six months later is unreliable, and getting it wrong
is a licence violation rather than an untidiness.

## Rules for adding to this project

**Every borrowed fragment gets a comment at the point of use**, naming the
project, its licence, and ideally the file it came from:

```swift
// Adapted from DockDoor (GPLv3) — Sources/…/WindowPreview.swift
// https://github.com/ejbills/DockDoor
```

…and a row in the table below. A borrowing recorded in only one of the two
places is the one that gets lost.

**Compatible licences.** GPLv3 code may be incorporated because this project is
GPLv3. So may MIT, BSD, and Apache-2.0 code, which are one-way compatible into
GPLv3 — but their notices must be preserved, and Apache-2.0 requires GPLv3
specifically, not v2.

**Incompatible licences.** Code that is proprietary, unlicensed, or under a
licence with terms GPLv3 cannot absorb must not be used. **Unlicensed is not
permissive**: with no licence there is no grant, so the default is that no
permission exists — see B3 in [BACKLOG.md](./BACKLOG.md), where exactly this
was noted about a project whose README said "MIT" while the repository carried
no licence file at all.

**Apple's own resources.** Loading artwork from `Dock.app` at runtime (as the
Trash tile does) reads files already on the user's machine and redistributes
nothing. Copying those files into this repository would be redistribution, and
is not permitted.

## Borrowed code

Nothing yet.

| Project | Licence | Used for | Where |
|---|---|---|---|
| — | — | — | — |

## Projects studied but not copied from

Recorded because "we looked at this" is worth knowing even when nothing was
taken, and because the record is what makes a later claim of independent
authorship credible.

| Project | Licence | Notes |
|---|---|---|
| [ejbills/DockDoor](https://github.com/ejbills/DockDoor) | GPLv3 | Dock previews and window switching. Its multi-display feature *locks* the Dock to one monitor — the opposite remedy to this project's. |
| [josejuanqm/docky](https://github.com/josejuanqm/docky) | GPLv3 | Full Dock replacement. Drives windows through private SkyLight SPI; this project deliberately stays on the public Accessibility API (backlog B8). |
| [henningziech/extradock](https://github.com/henningziech/extradock) | unclear — README says MIT, **no licence file** | Docks on secondary displays. The `CGDirectDisplayID` approach here was arrived at independently and is documented in Apple's own reference. Do not copy from it while its licensing is unresolved (B3). |
