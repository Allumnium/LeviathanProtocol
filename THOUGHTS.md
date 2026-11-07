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
- **Refactor opportunity / run-scoped tuning:** `SharedSupport.parameters` now serves the shared behavior schemas, including enemy roles and research weapon effects. Move this lookup into the run's frozen content view during P3 and keep finite repair operations separate. Enemy roster/geometry/allocation snapshots already resist later tuning edits; full support/ability/art freezing belongs with P3 run content, not a second save system here.

## 2026-11-07 - P2e follow-ups

- **Refactor opportunity / paired equipment metadata:** Physical equipment still expects a part-metadata definition with the same scoped base ID. The namespace fixture deliberately authors both. A future schema could reference that metadata explicitly, or consolidate the remaining shared DTO fields, so a Library author receives a clear relationship instead of relying on an ID convention. Preserve engine behavior bindings while assessing this refactor.
