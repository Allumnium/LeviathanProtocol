# Chassis mounts

The owner's explicit artwork-based specification below supersedes the earlier
general-purpose side-mount draft. Equipment and mounts require an exact S/M/L/XL
size match; smaller parts never fill larger mounts.

| Chassis | Mounts |
| --- | --- |
| Flagship | Three front S Offense/Defense; central M any; four rear S Civic/Tech/Defense. |
| Corsair | Front L Offense/Defense; two side M Offense/Defense; rear S any. |
| Fighter | Front S any; two side S Offense only. |
| Transport | Central XL Civic/Tech; two side L Civic/Tech/Defense; front and rear S any. |
| Frigate | Four adjacent front S any; two side S Offense/Defense; central M any; rear S Civic/Tech/Defense. |
| Drone | Three S any; central M any. |

Catalog mount roles: `general` accepts every category; `offense` accepts Offense;
`combat` accepts Offense/Defense; `civil` accepts Civic/Tech; `utility` accepts
Civic/Tech/Defense. Shield Generator and Shield Relay are Defense equipment.
Symmetrical sides always use identical rules. Source artwork is unchanged.

`SlotCatalog.compatible` shares these rules across fitting, save validation,
eligible loot and drag previews. Research, unique ownership, damaged equipment,
loaded-item restrictions, free transfers and command costs remain unchanged.
Side callouts are still display-only; fit and select directly on the artwork.
See [HANGAR_DRAG_DROP.md](HANGAR_DRAG_DROP.md).

## Draft chassis tuning

| Chassis | Base hull | Built-in thrust | Command cost |
| --- | ---: | ---: | ---: |
| Flagship | 320 | 22 | Supplies 12 |
| Corsair | 180 | 50 | 4 |
| Fighter | 100 | 38 | 2 |
| Transport | 220 | 18 | 3 |
| Frigate | 180 | 40 | 4 |
| Drone | 55 | 24 | 1 |

Fighter weapons deal +30% damage, reflected in mounted DPS. Each incoming weapon
hit, including beams/projectiles, has a seeded 20% dodge chance before shields.
Direct, environmental and ability damage do not dodge. Warden Lance is a weapon.
Zero-dodge chassis do not consume extra dodge RNG. Dodges are combat-log events.

All chassis retain the 30 HP command center and 25 HP built-in engine. The
flagship additionally owns a fixed level I Shield Generator: 25 HP, 40 shields,
1.6 shield recharge/s after four seconds without damage. Its health participates
in the ordinary damage, repair quote, atomic repair and save paths. It is not a
stock instance and cannot be removed, sold or copied.

The starter retains its two compatible turrets (front sides) and central Lab I.
The incompatible old starter Armor Block is removed, with no replacement.
At the owner's direction, incompatible previous physical layouts are not
converted; strict checkpoint validation rejects them without rewriting saves.

## Inspection and validation

Click equipment/chassis shop rows or loose stock rows to inspect them in the
right panel; blank/outside clicks restore stock. Only the green plus buys.
Equipment details include size/category, HP, mass, effects and weapon rates.
Chassis details show base hull, thrust, mass, derived movement, shields, command,
price, bonuses/penalties, built-ins and every mount's size/category restriction.
Inspection preserves stock filters and does not change ownership or loadouts.
Beginning an installed-equipment drag restores the full-panel unequip target.

`test_hangar_mounts.gd` covers shared compatibility and physical fitting.
`test_chassis_review.gd` verifies the exact mount specification, draft stats,
built-in shield health/save/repair rollback, seeded weapon-only dodge and real
inspection/deselection inputs. Run the current isolated baseline with
`tests/run_baseline.ps1 -Native`.
