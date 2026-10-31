> Superseded by the actual physical hangar migration. See [HANGAR.md](HANGAR.md). This document records the earlier stage.

# Chassis and equipment slots

Owner direction, October 31, 2026. Replaces both square and hex construction, material placement, recipes and construction regions. The active main-menu Designer uses the five supplied chassis images. Campaign migration remains in progress; the existing run is not silently converted.

## Rules

- Choose a chassis and equipment from dropdowns over its authored slots.
- Slot types are Offense, Defense, Tech and Civic, initially using the old equipment categories.
- Sizes are S, M, L and XL. Equipment must match both type and size exactly. Smaller equipment does not fill larger slots.
- Starter equipment comes from Foundation's existing grants. Research unlocks more equipment/ranks; editing does not grant tech or spend credits.
- No grid, material palette, recipes, facing or equipment rotation controls. Source chassis images are unchanged.
- Keep Starhull/theme inheritance, minimal prose, no hover tooltips, no keyboard focus navigation and no reserve system. Mandatory flagship/command rules remain requirements of the physical fleet migration.

## Current Designer

`scenes/ship_designer.tscn` opens `slot_ship_designer.gd` from the existing main-menu button. Select a chassis at the top; each mounting point has a compact dropdown. Its popup shows full equipment names, filtered by exact size/type. Unresearched options are disabled and marked Research. Empty removes the fitted item. Short names on the ship avoid overlapping controls; clicking a slot shows its full name/type/size and applicable stats on the right. The five images frame automatically without scrolling.

`data/slot_chassis.json` stores source art paths and pixel rectangles in each original 512x512 image. These are initial hand-authored interpretations of visible circles/recessed bays, not automatic detection or final balancing. Rectangles, sizes and categories can be adjusted independently of artwork or UI code.

| Chassis | Initial slots | Draft interpretation |
|---|---:|---|
| Corsair | 5 | Large fore weapon, medium wing weapons, central Tech bay, small aft Defense |
| Fighter | 3 | Medium nose weapon and two small wing weapons |
| Transport | 5 | XL Civic hold, medium Defense/Tech side mounts, small fore weapon and aft Tech |
| Frigate | 5 | Long fore Tech bay, two small weapons, central Civic bay, aft Defense |
| Drone | 6 | Small weapon/Tech fore mounts, wing weapon/Defense mounts, central Civic bay, aft Tech |

Slot sizes/types are provisional content choices for review, not inferred from old material recipes. `data/slot_equipment.json` explicitly assigns sizes to implemented equipment; Lab I/II/III use M/L/XL. Existing stable equipment IDs, stats and research grants are reused. This metadata does not create new research or activate optional content. Chassis flagship roles, command values, prices and final starting roster still need tuning for the physical migration.

Canvas background and category colors live in `themes/ui_theme.tres`; controls inherit the shared font/styles. The owner's PNGs are never recolored, cropped or painted over on disk. The canvas overlays are runtime controls only.

## Persistence and compatibility

`SlotShipDesign` uses version 3, format `chassis_slots_v1`: chassis ID plus stable slot-ID assignments of equipment ID/rank. It stores no coordinates, materials, recipe transforms or trusted stats. Loading validates chassis/slots/types/sizes/ranks atomically. A locked imported assignment remains inspectable, but authorization is checked separately against current research; direct equipment selection also checks permissions.

`SlotDesignLibrary` stores named designs in `user://slot_designs.json` through the checksummed atomic store, with generation-based conflict detection and the existing verified recovery behavior. Old square and hex libraries remain separate. Neither legacy loader can reinterpret a slot design. The retired hex editors and combat prototype are removed. Read-only compatibility classes are isolated under `scripts/legacy/`; their frozen data is under `data/legacy/`.

The campaign's embedded builder, `GameState` physical fleet, material economy and run checkpoints still use the legacy model. They must move together to slot loadouts, credit costs, physical component/chassis health and versioned run saves. Do not claim that selecting equipment in the main-menu Designer has migrated a current run. No further hex/recipe work is planned.

## Verification

`tests/test_slot_designer.gd` checks all five assets, exact size/type compatibility, starter and research permissions, atomic invalid-load rejection, separate save formats, named library round-trips and concurrent-write conflicts. It opens the actual main-menu Designer and checks every slot at 640x360, 1280x720 and 1920x1080, including native pointer opening, inline details, fit/no-overlap, research refresh and campaign-state isolation. The baseline runner includes this suite. Equipment metadata/stat parity, independent stat copies, retired-item read/removal and malformed catalog validation are also covered. Native screenshots: `docs/ui-review/slots-corsair.png`, `slots-fighter.png`, `slots-transport.png`, `slots-frigate.png`, `slots-drone.png`, and `slots-equipped-drone.png`.

Prototype hex editor/battle tests have been removed. `tests/test_legacy_archives.gd` covers the read-only compatibility boundary. Research-enforcement and general battle tests validate the new main-menu Designer instead of expecting material/Archive controls. See SLOT_CLEANUP.md for the removal inventory.

October 31 verification: all 51 baseline suites pass in `.local/slots/baseline.log`, with isolated saves/logs in `.local/checks/1ad2655f1ef241d2aee2ae6c951acdcd/`. This includes 600 basic encounters and existing campaign/economy/persistence coverage. The final expanded slot suite passes 1,297 checks headless and natively in `headless-final.log` / `native-final.log`, including the actual OptionButton menu-selection connection and a sub-500-ms equipment-change/frame-settling guard. Native captures cover all five chassis and the equipped Drone. No GDScript/parse/formatting errors in final logs; whitespace checks pass. Existing engine certificate-store and legacy shutdown-resource diagnostics remain separate from gameplay assertions. No optional extras were activated.

Subsequent cleanup: retired grid editors/combat prototype are removed, archive readers are isolated/read-only, and slot metadata/stats now come directly from data/slot_equipment.json. Mining/ore items are excluded from new choices while previous assignments stay readable/removable. All 48 remaining baseline suites pass; final focused slot checks pass 1,270 assertions headless and natively. See [SLOT_CLEANUP.md](SLOT_CLEANUP.md) for changes, compatibility boundaries and current validation logs. The earlier 51-suite result above predates removal of the prototype suites.
