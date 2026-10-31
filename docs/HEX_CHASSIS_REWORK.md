> Superseded October 31, 2026: the owner replaced grids, materials and recipes with chassis images and typed equipment slots. This document is historical. Active work is described in SLOT_DESIGNER.md and TODO.md.

# Hex chassis and flagship rework

Owner decisions recorded October 30, 2026. This is the next required work before TODO step 56. Implementation is in progress; the existing campaign still uses the legacy square model until the replacement works end to end. These decisions supersede the freeform square-grid ship-design assumptions in earlier plans.

## Confirmed rules

- Ship designs use hexagonal tiles. Material recipes remain the equipment-building mechanic.
- Each ship uses an existing chassis, defined by a predefined connected set of hexagons and a fixed outline. Players cannot expand or reshape that outline; they choose another chassis to change shape.
- Materials can be placed only in designated construction regions. There are no additional open building hexes between those regions. Chassis space outside the regions is unavailable for player construction.
- Construction regions do not touch: at least one intervening hex separates them. Each equipment recipe must fit entirely inside one region.
- No design-slot limit. Remove the old act-based deployment-capacity budget. Flagship chassis supply command points; non-flagship chassis each consume a chassis-specific command cost. There are no reserves: every owned ship is deployed and consumes its command cost. Remove reserve UI and state during migration.
- The chassis has a single integrity pool. It breaks all at once below zero; zero integrity remains alive. Unshielded equipment hits divide damage equally between chassis and component. A bare-chassis hit damages the chassis directly.
- All chassis include a command center. Many include built-in armor and thrusters. Built-in equipment has fixed placement and can be destroyed and repaired.
- Construction regions can grant multiple equipment bonuses. The owner gave armor efficiency +20% and weapon range +30% as examples; players choose which equipment to build in those regions. These are examples rather than finalized chassis statistics.
- The initial catalog contains five chassis, including flagship chassis. Flagships are larger and offer more construction space.
- The fleet contains exactly one physical flagship, and it must deploy in every battle. It cannot be parked in reserve to avoid risk.
- Losing the flagship ends the run. Existing command-center destruction rules still apply: losing its command center destroys the flagship and ends the run.
- Replacing a flagship chassis must keep the fleet valid through one atomic replacement action at a shipyard; a temporary zero-flagship state must not trigger defeat. No second physical flagship may be retained.
- Existing UI preferences continue: shared Starhull/theme, minimal inline or click-open details, no hover tooltips except the Designer lock, no keyboard focus cycling, and no Port/Story navigation or automatic explanatory panels.

The mandatory flagship is an explicit owner-authorized singleton. It does not introduce dedicated science/civic ships or other equipment segregation.

## Details to settle during design

These are not approved mechanics yet:

- The five actual chassis shapes, the number of flagship choices, built-in loadouts, construction regions, bonuses and costs.
- Hex orientation, recipe footprints and mirroring. Existing square recipes need deliberate hex-native definitions; do not blindly reinterpret saved coordinates.
- The exact meaning of each efficiency bonus and its stacking/cap rules. Prefer precise metrics when selecting final values.
- The source and persistence of chassis availability. Choosing/finding another chassis is part of the owner direction; a new loot, shop or unlock subsystem has not been specified.
- Retirement value and loaded-passenger/cargo handling during flagship replacement. Existing loss and safe-offload protections must remain effective.
- The legacy-save policy. Preserve old saves and blueprints while designing an explicit versioned transition; do not silently reshape them or overwrite them.

## Required implementation sequence

1. Specify versioned hex coordinates, chassis identity, fixed geometry, construction masks, built-in equipment identities and region modifiers. Validate connected outlines, legal cells and unique command centers. Define legacy handling before changing runtime storage.
2. Complete one representative chassis through the actual builder and battle. Implement hex picking, placement, recipe transforms, adjacency, previews, physical geometry and rendering together; verify that construction stays inside allowed regions.
3. Integrate chassis-based construction, pricing, repairs and refits with existing material-stock/credit-shortage rules. Preserve bounded equipment effects, research authorization and explicit recipe identity.
4. Add flagship identity and lifecycle checks across new runs, construction orders, salvage actions, deployment, withdrawal, replacement, defeat, saves and replay. Remove design-slot limits, old act capacity and reserve state/UI; enforce chassis-specific command supply/cost instead. Exactly one flagship must survive every valid nonterminal state and deploy every battle.
5. Add the remaining four chassis after the prototype works, including distinct flagship choices as agreed during catalog design. Keep layouts usable for mixed equipment without adding role restrictions.
6. Revalidate economics, region bonuses and caps, component destruction/reconstruction, passenger/cargo losses, visibility, targeting, collision, formation, persistence and replay. Review the real designer/construction/research/formation UI at 640x360 with native pointer input, pause/2x and performance checks. Update the required MVP gates to the new ship model before resuming step 56.

This sequence plans the rework; it does not authorize unrelated features or activate Optional / Extra backlog items.

## Implemented foundation

The new model is currently isolated from the campaign. It does not convert, replace or write existing run/archive files. The legacy `Ship` loader explicitly rejects versioned/topology-bearing payloads rather than reading axial coordinates as squares.

- `HexGrid`: point-up axial `(q,r)` cells; +q points forward/right. Six rotations and a reflection, exact shared-edge cancellation, inner-hole boundaries, picking and polygon ray intersections.
- `data/hex_recipes.json` / `HexRecipe`: 58 explicit equipment/rank layouts with stable equipment IDs, recipe revisions, six rotations and reflection. Rows are axial parallelograms; this deliberately retains existing material counts while giving new recipes hex geometry. This is new recipe authoring, not a square-blueprint conversion. Duplicate/ambiguous layouts are rejected except the existing mutually exclusive branch pairs. Deferred recipes remain data only; this does not unlock optional equipment.
- `data/chassis.json` / `ChassisDefinition` / `ChassisCatalog`: five draft connected masks, immutable canonical definitions, fixed built-ins and disjoint construction regions. Validation rejects duplicate cells, overlaps, disconnected outlines/groups, touching regions, invalid bonuses and missing/duplicate command centers.
- `HexShipDesign`: blueprint version 2 with topology `hex_axial_v1`, chassis ID/revision, player materials and fitted recipe identities/transforms. Built-ins, structure, bonuses and HP come from catalogs rather than saved user-supplied masks. Fitting requires matching materials wholly within one region; no overlaps. Failed loads leave the current design untouched.
- `HexShipState`: a physical blueprint copy, one chassis pool and independent component HP. Equipment damage splits 50/50; bare structure receives full damage. The chassis footprint persists until integrity is strictly negative or the command center dies. Ordinary repair cannot resurrect a dead chassis. Physical health reloads atomically with stable unit identities.
- `HexFleet`: all-owned deployment, one flagship, chassis command supply/cost, construction/salvage guards, atomic flagship replacement and terminal flagship loss. There is no reserve field or fixed slot roster. Transactional campaign purchases, loaded cargo/passenger guards and shipyard checks still belong to the later integration; this class is not connected to those entry points yet.
- `HexBuildArea`: native hexagonal TileMapLayers for rendering/picking, protected structural/built-in cells, continuous paint/erase strokes, pointer-anchored zoom, panning and whole-chassis framing. Used by both the prototype and the real main-menu Designer. The Designer integration below is complete; battle/campaign integration remains R2 work.

Draft catalog tuning, not a balance commitment:

| Chassis | Type | Hull integrity | Build hexes | Command |
|---|---|---:|---:|---:|
| Wren | Standard | 35 | 6 | costs 2 |
| Bulwark | Standard | 70 | 16 | costs 4 |
| Wayfarer | Standard | 50 | 18 | costs 3 |
| Vanguard | Flagship | 140 | 50 | supplies 12 |
| Ark | Flagship | 180 | 55 | supplies 16 |

Region defaults use the precise metrics **armor component integrity** and **weapon range**, expressed as additive fractions on that component's base value. These names avoid giving an undefined generic efficiency multiplier. The foundation applies armor integrity to fitted armor components; weapon-stat integration and interaction with other effects remain R3. Built-ins currently have compact single-hex prototype footprints, not finalized artwork/geometry.

### Legacy transition policy

Keep square campaigns and square archived blueprints intact and explicitly identified as legacy. Never mix square and hex ships within a new-model fleet and never guess a chassis or move saved component coordinates. The campaign switch must wait until new-run creation, the actual Designer, battle geometry/rendering, command/flagship rules, economy and checkpoint persistence all work together. New hex storage must carry its own version/topology and must not overwrite the old file before a successful validated write. Legacy Continue remains available until an explicit transition exists. No automatic reset, blueprint replacement or destructive migration is authorized.

### Verification

`tests/test_hex_chassis.gd` covers geometry, all 58 recipe identities, chassis masks/gaps, all twelve orientations, failed-load atomicity, JSON health persistence, 50/50 damage, the zero-integrity boundary, command budgets, fleets larger than three ships, atomic replacement and flagship defeat. `tests/test_hex_builder.gd` uses viewport pointer input to check painting/erasing, protected structure/built-ins, zoom anchoring, minimum-size framing and placement latency. Both suites are included in `tests/run_baseline.ps1`. Native 640x360 capture: `docs/ui-review/hex-chassis-prototype.png`. This is Godot coverage, not Playwright.

October 30 foundation verification: all 48 isolated baseline suites pass, including both new suites, 600 basic encounters, 1,000 topology seeds, 1,000 content seeds and the existing campaign/economy/persistence checks. Log: `.local/hex-chassis/baseline.log`; isolated run: `.local/checks/f1203f2756a84fe3b03b6c4ee262181b/`. The new model reports 3,747 checks and the builder 411 checks, all passing; the native builder run also passes. No GDScript/parse errors found. Existing certificate-store and shutdown resource diagnostics remain separate from gameplay assertions. Whitespace checks pass.

### Next integration work

R2 now connects hex blueprints/physical fleets to the existing battle engine (see the combat section below). The campaign's embedded Designer/refit view remains legacy until transactional refits and versioned checkpoints support hex ships. R3/R4 must replace the existing `GameState` purchase/refit/reserve/deployment paths and `RunCheckpoint` family/HP schema as one versioned integration. Do not simply delete capacity checks while the old three-family roster still controls deployment.

## Main-menu Designer integration

`scenes/ship_designer.tscn` now opens `hex_ship_designer.gd` from the existing main-menu button. The shared Starhull three-panel Build/Archive workspace includes five chassis, placeholder material selectors, contextual region bonuses/equipment identity, material totals, chassis integrity and command supply/cost. No per-control fonts, hover tooltips or focus navigation were introduced. The old standalone scene is preserved as `scenes/legacy_ship_designer.tscn`; the embedded campaign builder is unchanged.

### TileMap and art

`HexMaterialPalette` now creates a native TileSet with `TILE_SHAPE_HEXAGON`, vertical offset and `TILE_LAYOUT_STAIRS_DOWN`, matching the flat-topped artwork at 64x55. Saved axial `(q,r)` maps directly to Godot cells, including negative coordinates. Rendering and picking use `TileMapLayer.map_to_local` / `local_to_map`; no odd/even-row save conversion is involved. Grid/material layers share the TileSet, disable physics/navigation, and use batched updates. The palette transforms the mathematical HexGrid reference by 30 degrees and accounts for pixel rounding. Native cell centers and group outlines share this transform. Battle rendering, mounted weapons and hit polygons now use the same presentation convention through HexBattleShip.

The owner's material images are assigned in `themes/hex_material_palette.tres`: `solid_red_tiles.png` (Offense), `solid_blue_tiles.png` (Defense), `Green_tech_tiles.png` (Tech), `solid_purple_tiles.png` (Civic). These are individual 64x55 tiles, not sheets. Builder, selectors, totals and Archive share this resource; null fields retain fallbacks. Source images are not modified or rotated. Palette icons expand within their buttons, avoiding the new texture dimensions enlarging the sidebar.

Hex equipment no longer draws legacy square equipment sprites. `HexEquipmentDrawing` draws the actual group boundary, retaining concavities/holes, and an upright centered equipment name. Built-ins and Archive share this presentation. Font/size/colors inherit from the `HexEquipmentLabel` theme variation. Names keep screen-readable text through pan/zoom, wrap at spaces, and have a dark text outline over the material artwork. Placeholder single-cell built-ins can have names wider than their footprint at far zoom; definitive chassis geometry/label spacing remains part of R5's art/layout pass.

### Assembly and history

`HexRecipeMatcher` prepares implemented recipe variants once and searches only candidates anchored on the changed material cell. Matches stay in one region. Larger recipes consume smaller assembled components only in their entirety; partial overlaps are rejected. Four blue plates become Armor and six Civic cells become a cabin. Same-size installed identities remain protected. Shared recipes such as Focusing Lens / Ion Emitter require an inline choice and Assemble click. Equivalent placements of one type use deterministic candidate order instead of duplicate choices.

A complete paint/erase stroke is one undo entry, including assembly. Fast drags interpolate intervening hexes. Undo/redo and per-chassis drafts preserve recipe identity; Ctrl+Z, Ctrl+Shift+Z/Ctrl+Y and material keys 1-4 avoid text fields/modals. Right mouse erases, middle mouse pans, wheel zooms about the pointer, and Fit View reframes the chassis. Structure/built-ins cannot be edited. Archive shows a canonical preview of each recipe with no Rotate/Flip controls. Assembly recognizes all six rotations and their reflections automatically; equipment has no functional facing.

### Persistence and verification

`HexDesignLibrary` stores named version-2 blueprints in separate `user://hex_designs.json` through the existing atomic/checksummed store. It validates all designs, preserves generations on failed writes, detects stale concurrent writes, and recovers verified `.next`/`.bak` files. An unrecoverable library cannot be silently replaced as empty. Save uses an inline name; Load uses a small window with the shared X. No fixed design slots. Legacy `ship_designs.json`, run checkpoints, research and the square editor ship remain untouched. Creative assembly never grants current-run research or authorizes legacy physical construction.

`tests/test_hex_designer.gd` enters through the main menu and uses native viewport pointer input to check painting, Armor/cabins, region details, undo/redo, fast strokes, shared-recipe choice, save/load and the shared X. It checks axial picking, minimum-size layout, three resolutions, legacy-state separation, exact material asset assignments, native flat-hex outline geometry and the named thruster group without equipment sprites. The expanded model suite covers all twelve ranked-recipe orientations plus archive concurrency/corruption recovery. Native screenshots: `docs/ui-review/hex-designer-build.png`, `hex-designer-archive.png`, `hex-designer-1280.png`, `hex-designer-1920.png`. This is Godot coverage, not Playwright.

Final October 30 Designer verification: all 49 baseline suites pass in `.local/hex-designer/baseline.log` (isolated saves: `.local/checks/399ef4a16d8f4208bf08733d7039d3f3/`). The final UI review fixed collapsed wrapped context labels using inherited font height plus theme line spacing, and hides the unbuildable command-center recipe from Archive. Affected model, canvas, Designer, research-enforcement and battle suites pass again in `final-test_*.log`; final layout checks pass in `headless-layout-final.log` and `native-layout-final.log`. Model: 3,783 checks; canvas: 411; Designer: 322, including the visible-line count for both bonuses, native popup X, read-only built-ins and resized native picking. Native worst tested placement including frame settling: about 50 ms (headless about 21 ms). All final logs have no GDScript/parse errors. Existing certificate-store and shutdown-resource diagnostics remain separate; whitespace checks pass.

### Material-art and equipment-outline follow-up

The supplied material PNGs and flat-topped presentation are integrated. No active recipe, chassis mask, equipment identity or balance value was changed. Recipe redesign and stable named-part assembly are discussion-only in [HEX_RECIPE_PROPOSAL.md](HEX_RECIPE_PROPOSAL.md).

Five affected suites pass in `.local/hex-materials/`: hex model (3,783 checks), canvas (411), Designer (619), research enforcement and legacy battle (600 encounters). Native Designer checks also pass at 640x360, 1280x720 and 1920x1080, with the correct asset assignment, flat-hex picking/outline alignment, named equipment and no legacy equipment badge rendering. Screenshots under docs/ui-review/hex-designer-* show the latest presentation. No GDScript/parse errors in final logs; whitespace checks pass. Existing certificate-store and shutdown-resource diagnostics remain separate. The earlier 49-suite result predates this presentation update; this follow-up reran the affected suites rather than the full runner.

## Hex combat integration (October 30, 2026)

`HexFleet.battle_ships()` binds the fleet's physical `HexShipState` instances to `HexBattleShip`, an adapter accepted by the existing `BattleSimulation.setup_owned` interface. Component HP and chassis HP remain shared with the persistent fleet; no damage is copied back heuristically after battle. The `HexBattleDesign` runtime view exposes equipment to existing support/doctrine code while serializing only the explicit hex blueprint schema. The legacy square loader rejects it. This does not switch `GameState` or the campaign checkpoint format.

Equipment has no functional orientation. All twelve recipe transforms retain identical DPS, thrust and range behavior. Weapons already aim automatically; thrust remains a scalar for ship movement. Ship headings/movement still exist. `ShipPart.hex_cells` selects six-neighbor adjacency for Crew, repair, science and doctrine interactions. Mixed square/hex adjacency and deployments are rejected. Archive no longer has Rotate/Flip controls. Recipe motifs/assembly redesign remain discussion-only.

Weapon mounts use the same flat-hex cell centers as the native Designer. Incoming hits trace actual hex polygons and scatter among exposed nearby hexes using axial distance. Empty structure and destroyed equipment cells remain solid chassis. Fixed structural mass, bounds and collision radius survive component destruction; chassis destruction still removes the entire ship at once. Default fleet formation spacing accommodates the larger hull radius. Material-cell mass is removed when equipment is destroyed; structural mass remains. Current structure mass is one unit per chassis cell, a prototype tuning value pending R5.

Regional armor bonuses affect component maximum HP; regional range bonuses affect equipped weapon range once. Shields absorb incoming damage before the 50/50 chassis/component split. Bare structure receives full damage. Chassis at exactly zero remains alive; negative HP or destroyed command center kills it. Flagship death takes precedence over victory/withdrawal even with living escorts. Hex deployment requires exactly one living flagship, unique physical IDs, no reserve state and a valid command budget. Finite component repair still uses the existing repair pool; it does not invent chassis regeneration. Chassis repair/refit pricing remains R3.

Destroyed hardware latches `load_lost` in hex health saves. Hardware reconstruction/reloading cannot revive former passengers/cargo. Built-ins do not create fabricated material salvage from their compact prototype footprints. Player material salvage uses the established combat path. Full travel/economy/passenger/cargo settlement integration remains R3/R4.

`BattleVisuals` bypasses the square hull/equipment caches for hex ships. It draws the supplied material hexes over fixed structure, actual equipment outlines and upright names using the shared theme's default font. Names appear when zoom provides room; outlines remain visible at battle overview scale. No square equipment sprites are used. Native rendering evidence: `docs/ui-review/hex-battle.png`; refreshed Designer/Archive screenshots retain the canonical recipes without rotation controls.

`tests/test_hex_battle.gd` exercises real engine combat: all twelve laser placements, six-neighbor adjacency, range/armor bonuses, mounts, exposed hit polygons, persistent split damage, reconstruction contents, support repairs, lab recognition, shields, command/reserve/mixed-topology guards, zero HP, core/flagship defeat, larger formation spacing and deterministic weapon exchanges. The suite is part of the baseline runner. Campaign migration is still deliberately pending R3/R4; R2's combat foundation is complete.
