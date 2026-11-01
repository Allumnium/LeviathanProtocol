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
eligible loot and drag previews. Research, unique ownership,
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

Engines are implicit and command is covered by overall ship integrity; neither
has separate damage or descriptive UI. The flagship additionally owns a fixed
level I Shield Generator: 40 shields, 1.6 shield recharge/s after four seconds
without damage. It is not a stock instance and cannot be removed, sold or copied.

Hull is the only persistent health pool. Shields absorb hits first; all
unabsorbed damage applies to hull, without component splitting or targeting.
A ship and all of its equipment remain active at zero hull; destruction occurs
strictly below zero. Equipment, engines and shields cannot be independently
disabled or damaged. Repairs restore the whole surviving hull for one credit
per missing hull point (rounded up). Destroyed ships cannot be repaired.
Trade loads are lost only with the host ship; casualty fees apply once.
Repair drones heal surviving hull using their existing finite allowance.
Nanoforge/Renewal II are deferred rather than inventing a replacement for
component reconstruction.

The starter retains its two compatible turrets (front sides) and central Lab I.
The incompatible old starter Armor Block is removed, with no replacement.
At the owner's direction, incompatible previous physical layouts are not
converted; physical checkpoint version 2 rejects previous versions without
rewriting them. Version 2 stores equipment identity/load and ship hull only;
equipment `hp` and ship `builtins` fields are rejected.

## Inspection and validation

Click equipment/chassis shop rows or loose stock rows to inspect them in the
right panel; blank/outside clicks restore stock. Only the green plus buys.
Equipment details include size/category, mass, effects and weapon rates.
Chassis details show base hull, thrust, mass, derived movement, shields, command,
price, bonuses/penalties, built-ins and every mount's size/category restriction.
Inspection preserves stock filters and does not change ownership or loadouts.
Beginning an installed-equipment drag restores the full-panel unequip target.

Hull, maneuverability, mass and shields use the supplied
`Progress_Cp` / `Progress_Cp_Bg` textures in shop, Fleet and Ships details.
For each stat, reference bounds are the minimum and maximum of all six base
chassis, including the flagship and its built-in shield mass. Exact numeric
values remain visible; bar fill is
`10 + 90 * clamp((value - minimum) / (maximum - minimum), 0, 1)` percent.
Outfitted/damaged ships use their real current values against those same bounds.
Equal reference bounds are a balancing error, not a silent divide-by-zero
fallback; current chassis vary across every displayed stat.

Maneuverability consolidates movement without changing physics. Let each
movement factor's weight be its mean across all six base chassis divided by
the sum of those means. Weight each actual/mean ratio and scale the result by
50; equivalently, `50 * (speed + acceleration + turn_rate) /
(mean_speed + mean_acceleration + mean_turn_rate)`. The average base chassis
scores 50. Thrust/mass already feed these derived mechanics and are not counted
again. Outfitted movement uses the same base reference. Displayed hull, mass,
shield, maneuverability and DPS values are rounded integers; calculations and
backend state retain full precision.

`test_hangar_mounts.gd` covers shared compatibility and physical fitting.
`test_chassis_review.gd` verifies the exact mount specification, draft stats,
seeded weapon-only dodge and real inspection/deselection inputs.
`test_whole_ship.gd` verifies hull-only damage/repair/rollback, operation,
shield-first hits, core-free sight and version 2 persistence.
Run the current isolated baseline with
`tests/run_baseline.ps1 -Native`.

Before the whole-ship simplification, all 17 baseline suites passed with isolated saves, including
57 dedicated chassis checks, 1,983 native general-UI checks and 197 native polish
checks. All nine natural campaign policies win; science builds operate Lab III
and reach 8 RP/day. Native drag coverage passes 548 checks. Existing Godot
renderer/resource shutdown diagnostics remain; no script/parse errors occur.

Whole-ship follow-up: all 18 isolated baseline suites pass, including native
144 chassis/stat-bar checks, 2,444 general-UI checks and 197 polish checks.
Native drag coverage passes 589 checks; the dedicated hull-only suite passes
37 checks. All nine natural campaign policies still win without forced outcomes.
