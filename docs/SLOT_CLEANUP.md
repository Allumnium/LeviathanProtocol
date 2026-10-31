> Superseded by the actual physical hangar migration. See [HANGAR.md](HANGAR.md). This document records the earlier stage.

# Slot migration cleanup

October 31, 2026. The owner authorized removing obsolete systems after choosing image-based chassis, typed slots, exact size matching and no materials.

## Removed

- Hex painting/assembly UI, recipe matcher/previews, material palette/TileSet resource, chassis prototype scene, and standalone hex Designer.
- Hex battle adapter/runtime design, renderer, hit geometry, physical fleet/health prototype and the corresponding battle/adjacency/stats branches in the shared engine.
- The duplicate standalone square Designer scene/script. The embedded square campaign builder is still in use.
- Prototype-only hex tests and theme styles. Archive compatibility now has a focused read-only regression suite.
- Mining Laser, Extraction Drill, Ore Processor and Seismic Cutter from new slot choices. Material/mining equipment plans are retired, not optional content waiting to be activated.

Original owner artwork, existing user saves/libraries, historical screenshots and the currently playable campaign were not deleted.

## Active slot code no longer depends on recipes or component sprites

`data/slot_equipment.json` explicitly defines the implemented equipment IDs/ranks, types, sizes and stats. Its initial tuning was extracted without changes; it does not contain material layouts or derive sizes/mass from tile counts. `SlotCatalog` validates it and constructs fresh `ShipPartStats`/weapon values. The slot Designer reads those stats directly instead of building `ShipPartPattern` recipes, legacy textures and procedural square component art. Existing numeric tuning/type assignments remain draft content; this cleanup does not rebalance them or activate unimplemented equipment.

Retired entries remain readable metadata for earlier version-three slot libraries. They are excluded from new choices and cannot be installed, even with their old research grant. An already fitted retired item is visible/disabled with a Retired explanation and can be cleared. Loading such a design does not make it deployable. This avoids invalidating an entire saved library because one design once used a mining item.

## Compatibility boundary

Six small compatibility classes live under `scripts/legacy/`, with frozen versioned data in `data/legacy/`. Their `LegacyHex*` names distinguish them from the current model. The old hex library reader has no save API. Its helpers retain only the coordinate/recipe/chassis validation needed to read existing blueprints; rendering, picking, ray collision, editing and physical fleet simulation are gone. No old file is converted or rewritten on read.

The read-only hex classes also no longer consult `GameDefinitions`, `MaterialRecipe`, `ShipPartPattern` or the active research registry. Frozen archive footprints supply historical identities/ranks. Completeness, duplicate identity, bounds and connectivity checks remain; retired recipe matching/ambiguity policy is removed. Future campaign registry cleanup therefore cannot alter how those old hex footprints are interpreted.

`tests/fixtures/legacy_hex_blueprint_v2.json` records an actual pre-cleanup blueprint. `tests/test_legacy_archives.gd` checks square/hex readability, corrupted revision/identity/coordinates, failed-load atomicity, explicit schema boundaries, unchanged library bytes and verified backup recovery.

## Still live, remove after replacement

The campaign still uses `Ship`, `FleetShip`, `ShipPartPattern`, `MaterialRecipe`, its embedded builder/Archive, material balances, mining/rewards, family/reserve/capacity logic and old checkpoints. They are not dead code. Deleting them before the slot physical fleet/economy/save path exists would break current runs. TODO S2-S4 replace these callers and then remove their old implementations/fixtures, including obsolete research/reward/map-preview paths. No material or reserve features belong in the replacement.

The common battle/weapon/support systems remain in use. Hex-specific scaffolding was removed without claiming that slot ships now enter combat. Mandatory flagship, command budgets, whole-chassis HP and damage splitting remain required slot migration work; deleting a retired prototype does not cancel those owner decisions.

## Plan and instructions

`TODO.md` now lists confirmed decisions, the required migration order, remaining core content and a separate optional backlog. Material/ore/refinery/spectroscopy requirements are retired. Detailed previous milestones are preserved in `docs/history/TODO_PRE_SLOT_CLEANUP_2026_10_31.md`. `AGENTS.md` contains only current rules and the explicit legacy boundary, without contradictory active hex/material instructions.

## Verification

All 48 baseline suites pass in `.local/cleanup/baseline.log`, with isolated saves/logs in `.local/checks/ab5f9075c5f647718a0cf8f291a85fc0/`. This includes 600 basic encounters, campaign traversal/first-act/boss checks and economy/replay/persistence regressions. The runner replaces four retired prototype suites with focused archive coverage; its lower suite count is intentional.

Final isolated reader cleanup additionally passes `final-archives.log` (34 checks) and `final-slots.log` (1,270 checks). Native slot checks pass at all three supported resolutions in `native-slots.log`, covering equipment fitting, saved/retired items, research refresh, no overlap/scrolling and sub-500-ms interaction settling. The 187 static resource references checked by `.local/cleanup/check_refs.js` resolve; no GDScript/parse/formatting errors in final logs, and whitespace checks pass. Existing certificate-store and legacy shutdown-resource diagnostics remain separate from assertion results. User data was isolated throughout.
