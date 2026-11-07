# Development thoughts

Open questions, concerns and ideas recorded during development. These are observations and proposals, not an implementation backlog or approval to change gameplay. Resolved entries move to [THOUGHTS_ARCHIVE.md](THOUGHTS_ARCHIVE.md). Agreed work belongs in [TODO.md](TODO.md); verified deliveries belong in [COMPLETED.md](COMPLETED.md).

## 2026-11-07 - Starting P2

- **Observation / content authority:** JSON is loaded through the new pack pipeline, but research grants are still filtered and rewritten in code. An inspector could show a valid edit that gameplay ignores. P2 should prove changes through real gameplay transactions, not only database lookups.
- **Concern / remaining legacy diagnostics:** The five pre-existing square-checkpoint fixture failures remain with `test_legacy_archives`, pending its reference audit and retirement in P2e. The active-suite stale-fixture corrections are recorded in [the archive](THOUGHTS_ARCHIVE.md).
- **UX proposal / explain an unavailable option:** The future inspector and Playtest overlay could show which prerequisite, equipment capability or rule prevents an option, with a jump to its definition. This would make valid-but-inactive content much easier to debug without hover tooltips.
- **Imaginative proposal / paired playtests:** A designer could compare the same seed and commands with and without a patch, highlighting changed encounters, prices and quest outcomes. This builds naturally on content hashes and stable streams; defer the surface until Playtest exists.
- **UX concern / misleading metadata:** Some authored ability and research definitions still describe retired or unavailable behavior. Do not expose those as usable options just because a generic Library form can display them. Make availability explicit while preserving current gameplay.

## 2026-11-07 - P2 starter and economy implementation

- **Refactor opportunity / remaining caches:** Audit remaining UI/static caches as their authorities move in later P2 checkpoints. GameDefinitions, SlotCatalog and ShipLoadouts are already fixed; their resolution is archived.
- **UX observation / footer density:** Native captures at 640x360 show fuel, missile supply and the ammunition purchase packed tightly together. Current quotes fit and pointer purchases work. Consider slightly clearer separation when the HUD next changes; do not expand this content migration into a layout redesign.
- **UX concern / contradictory trip estimates:** `_render_map_details` still formats selected-trip estimates at 1x and 10x, while the actual Map has fixed 8x controls and the underway estimate uses 8x. A focused future UX change should use the current travel speed consistently.
- **Tooling concern / pack-root diagnostics:** PackLoader discovers packs inside root directories. Passing a pack directory itself can produce a warning about its `defs` child instead of loading that pack. The CLI comment calls roots "pack folders," which is easy to misread. Consider accepting both forms or reporting the expected container layout explicitly.
- **Refactor opportunity / relational validation:** Schemas validate new start/package fields, and new-run preflight rejects duplicate member IDs, unavailable fits, multiple flagships and oversized fleets. Moving reusable cross-definition checks into the loader's type-check registry would let the future Problems panel diagnose these before Playtest.
- **Imaginative proposal / starter constellation preview:** A fleet-package inspector could show the actual fitted formation and let a designer compare a convoy's fuel, cargo, lab output and early eligible research before launching. Reuse the Fleet renderer and definitions; avoid building a second fitting system.
