# Basic blueprints and armor assembly

Owner request, 2026-10-29: add basic ships and fix four blue blocks failing to assemble armor.

The shared design library now includes these optional templates alongside Drone:

| Design | Equipment | Cells | Deployment capacity |
| --- | --- | ---: | ---: |
| Scout | Command Center, Thruster, Armor Block, 2 Mini Turrets, plates | 15 | 4 |
| Escort | Command Center, Thruster, Shield, 2 Armor Blocks, 4 Mini Turrets, plates | 30 | 5 |
| Surveyor | Command Center, Thruster, Lab I, Crew Quarters, 2 Mini Turrets, plates | 19 | 5 |
| Hauler | Command Center, Thruster, Cargo Hold, Crew Quarters, Mini Turret, plates | 19 | 4 |

All use Foundation equipment, fit the starting build area and have connected, nonoverlapping component footprints. Load them through Ship Designer's library or select them for a general Fleet slot, then construct normally. Existing starting ships and credits are unchanged. Templates cannot be overwritten or deleted; edited copies need another name. Previously saved player designs with these new names retain priority and remain editable.

The paged library removes outgoing rows from its layout before queuing their deletion. This prevents old and new pages being counted together and permanently expanding the popup off-screen at 640×360.

The armor bug came from automatic single-plate assembly: each blue tile immediately became an assembled plate, which the general identity-preservation rule then excluded from the larger recipe. Both automatic and manual assembly now accept single plates specifically as inputs to the 2×2 Armor Block recipe. The four materials remain; consumed plate sprites are removed. Other assembled equipment and existing armor identities retain their protection. Manual mode offers the combination without automatically consuming it.

Validation: `tests/test_basic_ships.gd` checks Foundation authorization, connected footprints, no overlaps, starting-area fit, unique designs, real construction, checkpoint reload, library search and existing same-name player designs. It also checks paginated library mouse input at 640×360. `tests/test_recipes.gd` covers sequential blue placement, plate-sprite replacement, undo/redo and explicit assembly from plates, alongside the existing recipe/orientation/identity tests. The baseline runner includes the new basic-ship suite.

Evidence is under `.local/basic-ships/`: `recipes.log`, `final-native/run.log`, construction-order, fleet-slot and research-enforcement logs. All six targeted suites passed. The final isolated UI review is `ui-final/run.log`; its placement/add/remove timings were 75/514/477 ms, all within existing test budgets. An earlier concurrent timing run exceeded the fleet-add budget; the isolated runs passed. Native preview and library captures are `designs.png` and `library.png`.

This adds basic choices, not a completed opening-loop balance review. Step 18 remains open for that review and any starting-credit decision.
