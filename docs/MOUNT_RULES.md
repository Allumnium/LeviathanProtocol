# Size-led chassis mounts

Playtest direction: ordinary mounts accept equipment based primarily on the size shown in the artwork. Offense/Defense/Tech/Civic remain equipment categories. They do not restrict a general-purpose mount.

- S, M, L and XL still require an exact size match.
- General mounts accept any category of the matching size.
- Clear forward weapon mounts accept matching-size Offense equipment.
- Clear rear engine-housing mounts accept matching-size thrusters or defensive equipment. Shield generators/relays count as defense here even though their older equipment category is Tech. Unrelated Tech equipment does not qualify.
- Research gates, physical ownership, damage, trade loads, free transfers and the command budget still apply.

## Artwork review

| Chassis | General mounts | Position-specific exceptions |
| --- | --- | --- |
| Flagship | All nine mounts, including paired sides and utility bays | None: the marked platforms are not clearly dedicated engine nozzles or a fixed forward gun. |
| Corsair | Both wings and center | Forward L Offense; rear S Thruster/Defense. |
| Fighter | Both wings | Forward M Offense. |
| Transport | Both M sides and XL hold | Forward S Offense; rear S Thruster/Defense. |
| Frigate | Forward/center L bays and both S sides | Rear S Thruster/Defense. The long forward recess is a general bay, not clearly a dedicated gun. |
| Drone | Sensor-position S, both S sides and center M | Forward S Offense; rear S Thruster/Defense. |

This gives 25 general mounts and eight positional restrictions across the six supplied chassis. Source artwork, mount coordinates, sizes and IDs are unchanged. Symmetrical side mounts have identical fitting rules. In particular, either Transport side accepts M weapons, armor, shields, labs or other researched M equipment.

## Shared rules and UI

`SlotCatalog.compatible` is the common rule for actual fitting, checkpoint validation, eligible loot and both canvas dropdown paths. The catalog validates mount roles separately from equipment categories. General mounts use a neutral shared-theme color and show only their size in details; restrictions say Weapons or Thruster/Defense. No tooltip or new dialog is added.

The new maps broaden previously allowed equipment. Every old category-and-size pairing is tested against the new rule, including archived/retired item metadata. Existing physical saves and prototype loadouts need no conversion or rewriting. Old gameplay/editor screens remain retired.

## Validation

`test_hangar_mounts.gd` checks matching sizes/categories across all chassis, exact-size rejection, old-loadout compatibility, engine and forward restrictions, physical Transport purchases/transfers/reload, and both native side menus at 640x360, 1280x720 and 1920x1080. It also fits two purchased magazines in a Transport and two purchased computers in a Frigate to exercise real stacking loadouts. Native capture: `.local/mounts/transport.png`.

Recorded result: 1,332 mount checks pass natively. All twelve baseline suites pass, including nine full-route runs (126 natural battles), archive readers and 313 native general-UI checks. Shared resource references and whitespace checks pass. Existing Godot Windows certificate-store/renderer shutdown diagnostics remain unchanged.

The existing combat/trade/science playthrough policies retain their explicit build preferences in `tests/fixtures/playthrough_mount_preferences.json`. These are test-player choices, not gameplay restrictions. They keep the regression comparison useful while broader balancing remains deferred to the vertical-slice tuning pass.
