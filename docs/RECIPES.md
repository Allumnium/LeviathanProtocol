# Recipe identity, orientation and assembly

Step 20 adds a shared `MaterialRecipe` parser and canonical signature for labeled material cells. Normalization removes translation, then evaluates all four rotations and both reflections. A signature includes material labels and actual occupied cells; periods are outside the footprint, and may contain unrelated material or assembled equipment.

The registry contains 56 base recipes and two additional Research Lab rank recipes. Their 58 entries produce 46 unique signatures: exactly the 12 intended opposite-branch duplicate pairs. The three pairs in each family are explicitly listed in `MaterialRecipe.EXCLUSIVE_PAIRS`. Definition validation rejects unexpected collisions, missing intended pairs, duplicate rank declarations and mismatched rank-I/base recipes. This audit does not activate future equipment or research.

## Assembled identity and transforms

Blueprint part records now include `definition_id`, `rank`, `quarter_turns` and `horizontally_flipped` alongside the existing enum ID, origin, ordered cell offsets and hidden exhaust offsets. Loaders cross-check these fields against the actual implemented equipment, labeled footprint and legal transform. A mismatched ID, unavailable rank, invalid rotation or non-boolean reflection is rejected. The current live catalog admits rank I; physical lab ranks remain step 24.

Unversioned blueprints still load. Missing orientation is inferred from their existing ordered offsets; the next save adds explicit metadata without changing their material cells, original IDs or exhaust offsets. Persistent physical ship/component IDs and HP ordering are unchanged. Regular-family membership remains based on the existing family rules; adding metadata does not manufacture a new family.

Non-engine recipes can rotate and reflect. Their material labels transform with their cells. Engine rotations retain the existing restriction, and exhaust material remains in the footprint and cost. `ShipPart.get_transform()` supplies explicit orientation to builder, design preview, fleet preview and battle rendering. `ShipPart.facing()` gives the corresponding transformed forward direction, including for symmetric footprints whose orientation cannot be recovered from shape alone. Existing target-tracking weapon behavior is unchanged; this step records orientation rather than introducing new firing-arc restrictions.

## Editor workflow

The Ship Designer's **ASSEMBLY** menu provides:

- Auto-assembly of loose material, enabled by default.
- Explicit assembly of loose matches, largest first.
- Explicit disassembly of the blueprint's parts while retaining all material; this also disables auto-assembly so the player can plan a larger layout.
- A list of loose-tile matches, with larger footprints first. Hovering a match outlines its actual cells; selecting one assembles that match. Up to 32 candidates appear in the menu, with bulk assembly available for larger layouts.

Evaluation preserves intact assembled parts. Adding adjacent material or learning another recipe cannot consume an already assembled component. Editing its own material invalidates that component; its remaining cells become loose material eligible for matching. Explicit disassembly changes the blueprint only; it neither dismantles owned physical ships nor creates inventory or refunds. Preview is read-only and excludes assembled cells and cells locked by an in-flight discovery animation. Holes outside a recipe may contain unrelated equipment.

Whole-ship movement translates existing part instances, keeping their orientation. Undo/redo stores the complete blueprint, including assembled identity, rather than reinterpreting a tile-only snapshot. Discovery animation completion commits the selected part explicitly, including in manual assembly mode.

## Verification

`tests/test_recipes.gd` covers all 58 recipes under all eight transforms, the 46-signature count, allowed/accidental collisions, duplicate lab ranks, live-pattern/definition agreement, every legal live orientation through JSON, symmetric facing, exhaust offsets, forged metadata rejection, holes, assembly locks, read-only previews, preservation of assembled turrets beside larger layouts, explicit larger assembly, movement and undo/redo. Legacy fixture checks compare all original fields after removing only the four additive metadata fields.

Native 640×360 designer and menu captures were inspected (`.local/recipe-builder.png`, `.local/recipe-menu.png`); the final native log has no script errors. Full regression results are recorded in TODO.md. Existing certificate-store and shutdown resource diagnostics remain separate from assertions.

Changed files: `scripts/material_recipe.gd`, `game_definitions.gd`, `ship_part.gd`, `ship_part_pattern.gd`, `ship.gd`, `build_tilemap_area.gd`, `battle_visuals.gd`, `fleet_ship_preview.gd`, `ship_design_preview.gd`, `tests/test_recipes.gd`, `test_definitions.gd`, `test_battle.gd`, `run_baseline.ps1`, and the checklist/documentation.
