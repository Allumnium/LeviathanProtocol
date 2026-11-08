# Development thoughts

Open questions, concerns and ideas recorded during development. These are observations and proposals, not an implementation backlog or approval to change gameplay. Resolved entries move to [THOUGHTS_ARCHIVE.md](THOUGHTS_ARCHIVE.md). Agreed work belongs in [TODO.md](TODO.md); verified deliveries belong in [COMPLETED.md](COMPLETED.md).

## 2026-11-07 - Starting P2

- **UX proposal / explain an unavailable option:** The future inspector and Playtest overlay could show which prerequisite, equipment capability or rule prevents an option, with a jump to its definition. This would make valid-but-inactive content much easier to debug without hover tooltips.
- **Imaginative proposal / paired playtests:** A designer could compare the same seed and commands with and without a patch, highlighting changed encounters, prices and quest outcomes. This builds naturally on content hashes and stable streams; defer the surface until Playtest exists.

## 2026-11-07 - P2 starter and economy implementation

- **UX observation / footer density:** Native captures at 640x360 show fuel, missile supply and the ammunition purchase packed tightly together. Current quotes fit and pointer purchases work. Consider slightly clearer separation when the HUD next changes; do not expand this content migration into a layout redesign.
- **Imaginative proposal / starter constellation preview:** A fleet-package inspector could show the actual fitted formation and let a designer compare a convoy's fuel, cargo, lab output and early eligible research before launching. Reuse the Fleet renderer and definitions; avoid building a second fitting system.

## 2026-11-07 - P2d observations and ideas

- **UX concern / authored preset prose:** Generated equipment details now follow patched mechanics, but some loadout `role` descriptions still quote fixed damage or hull numbers. A content patch can make that prose stale. Consider generated summaries or linting numeric claims when the Library inspector arrives; do not rewrite strategy or balance during this migration.
- **UX observation / scroll discoverability:** Native support details are readable at all supported resolutions, but the right panel hides its scrollbar and its decorative lower frame can obscure a last line until scrolled farther. Long equipment descriptions also wrap `Range 260` across lines. A future focused UI pass could reserve interior frame padding and make scrolling more discoverable without hover tooltips or focus outlines.
- **Imaginative editor proposal / generation receipt:** An encounter inspector could show mandatory units, reserved reinforcements, hazard share, tier prices and remaining points as a budget receipt, explaining both failures and valid roster changes. Reuse generator records when the composer/Problems UI exists. The actionable failure diagnostic is delivered in [the archive](THOUGHTS_ARCHIVE.md).

## 2026-11-07 - P2e follow-ups

- **Refactor opportunity / paired equipment metadata:** Physical equipment still expects a part-metadata definition with the same scoped base ID. The namespace fixture deliberately authors both. A future schema could reference that metadata explicitly, or consolidate the remaining shared DTO fields, so a Library author receives a clear relationship instead of relying on an ID convention. Preserve engine behavior bindings while assessing this refactor.

## 2026-11-07 - Starting P3

- **Concern / clock semantics during extraction:** Current travel has simulation seconds and distance-derived travel days, with research affecting cruise speed. Preserve the existing income, lab and repair clocks while moving Travel into transactions; define pressure/day boundaries explicitly before replacing Swarm navigation, rather than accidentally making repairs or research speed up with a new clock.

- **Remaining refactor / explicit run contexts:** Fleet/shipyard operations and their shared catalog/fitting helpers now receive owning definitions directly; that resolved portion is in [the archive](THOUGHTS_ARCHIVE.md). Research, travel/delivery, battle settlement and semantic validation still use the temporary frozen Content binding. Finish their extraction and remove the hangar projection adapter; avoid treating mutable GameState fields and the committed document as two permanent authorities.
- **Potential UX concern / most-recent run selection:** Repository discovery currently sorts by file modification time, with a stable ID tie-break. File timestamps have second resolution, so closely spaced saves can tie. P3e should remember the last selected/continued run as a recoverable UI preference instead of relying on timestamp ordering alone. The browser must also explain missing/damaged content rather than silently rebinding to installed rules.

## 2026-11-07 - P3c Fleet/shipyard extraction

- **Observed UX concern / salvage consequences:** The production confirmation names the ship and offers SALVAGE, but does not show its refund, lost cargo/passengers or passenger loss fees. Current mechanics clear the physical loads and charge those fees even when salvaging a living escort. Preserve the mechanics; a focused follow-up should quote the refund and occupied-load consequences before confirmation, using the same transaction-owned calculation. This omission was observed in the existing screen code while extracting salvage, rather than inferred from a playtest.
- **Imaginative editor proposal / operation receipts:** Fleet and trade transactions now carry concise structured receipts. A future Playtest inspector could expand one receipt into changed ship/equipment IDs, credits and the triggering hook, with a jump to the owning frozen definition. Keep frequent placement edits in a separate command/debug timeline so they do not bury meaningful story entries.
