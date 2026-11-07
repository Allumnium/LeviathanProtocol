# Development thoughts

Open questions, concerns and ideas recorded during development. These are observations and proposals, not an implementation backlog or approval to change gameplay. Resolved entries move to [THOUGHTS_ARCHIVE.md](THOUGHTS_ARCHIVE.md). Agreed work belongs in [TODO.md](TODO.md); verified deliveries belong in [COMPLETED.md](COMPLETED.md).

## 2026-11-07 - Starting P2

- **Concern / remaining legacy diagnostics:** The five pre-existing square-checkpoint fixture failures remain with `test_legacy_archives`, pending its reference audit and retirement in P2e. The active-suite stale-fixture corrections are recorded in [the archive](THOUGHTS_ARCHIVE.md).
- **UX proposal / explain an unavailable option:** The future inspector and Playtest overlay could show which prerequisite, equipment capability or rule prevents an option, with a jump to its definition. This would make valid-but-inactive content much easier to debug without hover tooltips.
- **Imaginative proposal / paired playtests:** A designer could compare the same seed and commands with and without a patch, highlighting changed encounters, prices and quest outcomes. This builds naturally on content hashes and stable streams; defer the surface until Playtest exists.
- **UX concern / remaining ability metadata:** Some ability definitions still describe retired or unavailable behavior. Do not expose those as usable options just because a generic Library form can display them. Research offer/access metadata is now explicit and its resolved portion is archived; remaining ability authorities belong to P2d.

## 2026-11-07 - P2 starter and economy implementation

- **Refactor opportunity / remaining caches:** Audit remaining UI/static caches as their authorities move in later P2 checkpoints. GameDefinitions, SlotCatalog and ShipLoadouts are already fixed; their resolution is archived.
- **UX observation / footer density:** Native captures at 640x360 show fuel, missile supply and the ammunition purchase packed tightly together. Current quotes fit and pointer purchases work. Consider slightly clearer separation when the HUD next changes; do not expand this content migration into a layout redesign.
- **UX concern / contradictory trip estimates:** `_render_map_details` still formats selected-trip estimates at 1x and 10x, while the actual Map has fixed 8x controls and the underway estimate uses 8x. A focused future UX change should use the current travel speed consistently.
- **Tooling concern / pack-root diagnostics:** PackLoader discovers packs inside root directories. Passing a pack directory itself can produce a warning about its `defs` child instead of loading that pack. The CLI comment calls roots "pack folders," which is easy to misread. Consider accepting both forms or reporting the expected container layout explicitly.
- **Refactor opportunity / relational validation:** Schemas validate new start/package fields, and new-run preflight rejects duplicate member IDs, unavailable fits, multiple flagships and oversized fleets. Moving reusable cross-definition checks into the loader's type-check registry would let the future Problems panel diagnose these before Playtest.
- **Imaginative proposal / starter constellation preview:** A fleet-package inspector could show the actual fitted formation and let a designer compare a convoy's fuel, cargo, lab output and early eligible research before launching. Reuse the Fleet renderer and definitions; avoid building a second fitting system.

## 2026-11-07 - P2 research follow-ups

- **Refactor opportunity / retired research views:** Active cards now read shared `research_tuning` for costs and counts. The unused focused-research/tree readers and nominal `cost_rp` metadata still exist for the legacy audit. Remove them in P2e so Library forms do not imply that an ignored per-project price controls the shared bar.
- **Refactor concern / qualified identities:** Qualified family and gate references now work, with a single commitment identity for qualified/local family aliases and explicit gate-to-run-flag bindings. Other legacy registry views still require globally unique local research/equipment IDs. Finish their move to scoped Content lookups before claiming complete namespace support for independent packs.
- **Editor opportunity / modifier pickers:** Research modifier parameter validation now has one engine implementation shared by CLI and runtime checks. Expose those primitive schemas through the inspector registry in the remaining P2 work, so authors can pick supported operations rather than discovering their names through errors.
