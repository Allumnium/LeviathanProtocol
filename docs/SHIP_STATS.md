# Shared ship stats and physical geometry

Step 19 centralizes derived player-ship stats in `ShipStats.from_units()`. `Ship.get_stats(laser_level)` constructs full-health units for the blueprint, including parts in the assembly transition. `FleetShip.get_stats(laser_level)` supplies its actual persistent units and HP. Both paths use the same component-integrity formula, equipment values, material mass, weapon upgrades, mount geometry and movement properties.

Each material cell contributes one unit of mass; assembled equipment adds its configured equipment weight. Loose cells and engine exhaust material count. The decorative hull polygon can bridge empty space, but that infill contributes no mass or HP. Full component HP remains occupied-cell count plus configured integrity times the existing integrity multiplier, with a minimum of one. No persistent maximum-HP values or repair prices changed, so existing save health arrays remain compatible.

Partially damaged components retain their footprint and output until HP reaches zero. Dead components contribute neither mass nor output. Intact disconnected equipment remains operational, including after destruction of a connecting tile. Losing the command center still destroys the ship without deleting the remaining physical wreck. Destroyed cells are not reconstructed by recalculating stats.

## Movement and geometry

`ShipStats` owns top speed, acceleration and turn rate. Simulation reads those properties rather than maintaining a second formula. This step preserves the existing speed-per-thrust and acceleration/turn limits; correcting physical mass changes the mass-dependent values. Diminishing-return mass-sensitive top speed, weapon/shield tuning and repair economics remain step 26.

Player hull geometry now uses fixed eight-unit world cells. Six-cell-wide Drone hulls retain their original width of 48; larger designs remain larger. Shared footprint size comes from occupied-cell bounds, and the collision circle encloses the occupied cell corners relative to the original blueprint center. The collision circle is conservative for sparse or elongated hulls; cell damage still resolves through the existing physical hit-cell trace. Alien definitions retain their existing collision sizes.

Weapon mounts use the same cell scale in blueprint and physical calculations. Damage retains the original ship center, so losing a section never shifts surviving mounts or teleports the ship. Live mass, footprint, radius, shields, weapons and movement refresh after component damage. Weapon cooldowns follow physical component IDs and weapon names (with ordered entries for repeated names), so removing an earlier weapon does not reset another weapon's cooldown or misassign its timer.

Battle drawing uses the same fixed cell scale and culls large hulls using their radius. Thumbnail previews fit their actual design dimensions into available UI space. Blueprint designer panels display Mass and Speed, and the campaign designer includes the current run's laser modifier in displayed DPS. Blueprint panels show a full-health design; persistent damage remains represented by the owned ship and its health display.

## Verification

Changed files: `scripts/ship_stats.gd`, `ship.gd`, `fleet_ship.gd`, `battle_simulation.gd`, `battle_visuals.gd`, `fleet_ship_preview.gd`, `game_map.gd`, `standalone_ship_designer.gd`, `tests/test_ship_stats.gd`, `tests/run_baseline.ps1`, and the development documentation.

`test_ship_stats.gd` verifies builder/physical agreement across all nine implemented component patterns and laser upgrades, physical mass, partial damage, translation-invariant geometry, different hull sizes, disconnected equipment, stable mounts, battle movement/radius values, damage refresh and surviving weapon cooldowns. It uses isolated saves. Existing component destruction/disconnection and deterministic replay tests also pass.

The complete isolated baseline passed with zero failures in `.local/checks/f5ba2c245d1145a69641886e93098244/`, including 1,000 topology seeds, 1,000 content seeds, 1,080 encounter allocations, three complete campaign traversals and 600 battle cases. Native 640×360 captures of the final designer and differently sized battle hulls were inspected (`.local/shared-stats-builder.png`, `.local/shared-stats-battle.png`); the native log contains no script errors. Whitespace checks passed. Existing certificate-store and shutdown resource diagnostics remain separate from assertions.

Step 18 remains open for its four-ship starter activation and 300-credit start. Labs, Crew Quarters and Cargo Holds still require their scheduled research, adjacency and cargo effects before becoming available.
