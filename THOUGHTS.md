# Development thoughts

Open questions, concerns and ideas recorded during development. These are observations and proposals, not an implementation backlog or approval to change gameplay. Resolved entries move to [THOUGHTS_ARCHIVE.md](THOUGHTS_ARCHIVE.md). Agreed work belongs in [TODO.md](TODO.md); verified deliveries belong in [COMPLETED.md](COMPLETED.md).

## 2026-11-07 - Starting P2

- **Concern / remaining legacy diagnostics:** The five pre-existing square-checkpoint fixture failures remain with `test_legacy_archives`, pending its reference audit and retirement in P2e. The active-suite stale-fixture corrections are recorded in [the archive](THOUGHTS_ARCHIVE.md).
- **UX proposal / explain an unavailable option:** The future inspector and Playtest overlay could show which prerequisite, equipment capability or rule prevents an option, with a jump to its definition. This would make valid-but-inactive content much easier to debug without hover tooltips.
- **Imaginative proposal / paired playtests:** A designer could compare the same seed and commands with and without a patch, highlighting changed encounters, prices and quest outcomes. This builds naturally on content hashes and stable streams; defer the surface until Playtest exists.

## 2026-11-07 - P2 starter and economy implementation

- **Refactor opportunity / remaining caches:** Audit remaining UI/static caches as their authorities move in later P2 checkpoints. GameDefinitions, SlotCatalog, ShipLoadouts and shared support parameters now follow database replacement; their resolutions are archived.
- **UX observation / footer density:** Native captures at 640x360 show fuel, missile supply and the ammunition purchase packed tightly together. Current quotes fit and pointer purchases work. Consider slightly clearer separation when the HUD next changes; do not expand this content migration into a layout redesign.
- **UX concern / contradictory trip estimates:** `_render_map_details` still formats selected-trip estimates at 1x and 10x, while the actual Map has fixed 8x controls and the underway estimate uses 8x. A focused future UX change should use the current travel speed consistently.
- **Tooling concern / pack-root diagnostics:** PackLoader discovers packs inside root directories. Passing a pack directory itself can produce a warning about its `defs` child instead of loading that pack. The CLI comment calls roots "pack folders," which is easy to misread. Consider accepting both forms or reporting the expected container layout explicitly.
- **Refactor opportunity / relational validation:** Schemas validate new start/package fields, and new-run preflight rejects duplicate member IDs, unavailable fits, multiple flagships and oversized fleets. Moving reusable cross-definition checks into the loader's type-check registry would let the future Problems panel diagnose these before Playtest.
- **Imaginative proposal / starter constellation preview:** A fleet-package inspector could show the actual fitted formation and let a designer compare a convoy's fuel, cargo, lab output and early eligible research before launching. Reuse the Fleet renderer and definitions; avoid building a second fitting system.

## 2026-11-07 - P2 research follow-ups

- **Refactor opportunity / retired research views:** Active cards now read shared `research_tuning` for costs and counts. The unused focused-research/tree readers and nominal `cost_rp` metadata still exist for the legacy audit. Remove them in P2e so Library forms do not imply that an ignored per-project price controls the shared bar.
- **Refactor concern / qualified identities:** Qualified family and gate references now work, with a single commitment identity for qualified/local family aliases and explicit gate-to-run-flag bindings. Other legacy registry views still require globally unique local research/equipment IDs. Finish their move to scoped Content lookups before claiming complete namespace support for independent packs.

## 2026-11-07 - P2d observations and ideas

- **UX concern / authored preset prose:** Generated equipment details now follow patched mechanics, but some loadout `role` descriptions still quote fixed damage or hull numbers. A content patch can make that prose stale. Consider generated summaries or linting numeric claims when the Library inspector arrives; do not rewrite strategy or balance during this migration.
- **UX observation / scroll discoverability:** Native support details are readable at all supported resolutions, but the right panel hides its scrollbar and its decorative lower frame can obscure a last line until scrolled farther. Long equipment descriptions also wrap `Range 260` across lines. A future focused UI pass could reserve interior frame padding and make scrolling more discoverable without hover tooltips or focus outlines.
- **Observation and imaginative editor proposal / generation receipt:** The current allocator returns an empty encounter when required units cannot fit the budget. A structurally valid price edit can therefore need a feasibility diagnostic. An encounter inspector could show its budget as a receipt: mandatory units, reserved reinforcements, hazard share, tier prices and remaining points. This would explain an unaffordable composition or why a price change alters the roster. Reuse generation records rather than inventing a parallel allocator; add actionable failure details with the future composer/Problems work.
- **Refactor opportunity / run-scoped tuning:** `SharedSupport.parameters` now serves the shared behavior schemas, including enemy roles and research weapon effects. Move this lookup into the run's frozen content view during P3 and keep finite repair operations separate. Enemy roster/geometry/allocation snapshots already resist later tuning edits; full support/ability/art freezing belongs with P3 run content, not a second save system here.
