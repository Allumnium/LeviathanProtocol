# Useful shared research and Gate C review

Step 27 enables six purchases plus known Foundation. The catalog has 16 live patterns across 14 equipment types. Future branches, abilities and economic equipment remain gated.

| Research | RP | Working benefit |
|---|---:|---|
| Applied Energy | 20 | Laser and Double Laser |
| Field Engineering | 20 | Large Thruster and Repair Station |
| Guided Munitions | 20 | Point-Defense Turret and Missile Rack |
| Energy Manipulation | 40 | +10% beam firing/shield recharge rate; requires Applied Energy |
| Laboratory II | 40 | Physical rank-II lab |
| Laboratory III | 80 | Physical rank-III lab; requires Laboratory II and first-boss victory |

The grouped review's explicit purchase action calls `GameState.purchase_research`. It checks current-run prerequisites, story gates, exclusions, branch commitments, readiness and RP, and blocks deployment/end-of-run purchases. A research ledger event commits RP debit and grants together before live state changes. Repeats cannot charge twice; failed saves grant nothing and spend nothing. Grants refresh construction choices and stats without changing assembled parts or owned hulls. New hardware requires paid physical construction at a shipyard. Buying the concept immediately changes shared builder/battle stats for applicable owned equipment.

Energy Manipulation adds to Crew's efficiency: together they give +22%, rather than multiplying. The same stat path caps ordinary bonuses at +30%. Damage per shot, projectile weapons, maximum shields, shield interruption, engine speed and RP are unaffected. Departure records the concept and support context for replay; damage refreshes retain it.

## Repair and interception

Repair Station uses `CD/.D`, including its empty corner. It shares 2 HP/s between up to two orthogonally adjacent damaged surviving components, chosen in stable component order. Crew improves throughput. It never restores destroyed parts or a dead command center. Each source has at most 20 HP of reserve; the battle HUD shows usable reserve. Destroyed sources stop immediately.

The node also retains its maximum concurrent station allowance and cumulative HP expenditure. Replacing/recycling a source cannot refill that allowance. Deploying additional stations together can raise it; a replacement changes coverage without erasing expenditure. Reserves and the node budget persist through withdrawal, reload, reconstruction and retries. A new node has a fresh allowance. Midbattle pickup commits include the current reserve state and repaired HP, while repair expenditure remains separate from ore pickup identity. Invalid finite reserve/pool values fail checkpoint validation.

Point-Defense Turret uses `OD/DT`. It prioritizes incoming hostile missiles within 160 units, then hostile strike craft, with weak 0.6-damage hull fire every 0.5 seconds. Each interception consumes its firing cycle and releases the intercepted missile's pending damage. It cannot erase bullets or friendly fire, or operate after destruction. Missile Rack uses `OOT/OTT`: three interceptable 3-damage missiles every five seconds, range 340, speed 200. New Chrysalis spore missiles are also explicitly interceptable. Existing six-field frozen weapon records load with their original behavior; an optional seventh boolean stores missile identity for new records.

The three new component textures are procedural placeholders. The existing entity rules handle strike-craft targeting; carrier spawning and reserves remain later milestones.

## Gate C findings

The functional support/research loop is reviewed: starting resources can construct a lab, real first victories earn RP, the reviewed action buys multi-grant research, and a later shipyard constructs working beam hardware. Stable families, dedicated roles, capacity, physical lab ranks, ordinary adjacency, research authorization and persistence have automated coverage. Native 640×360 ready/review/owned states and the reserve HUD were inspected in `.local/shared-*.png`.

Gate C's complete starter rollout remains open under step 18. Step 32 activates functional Foundation Cargo Holds and arrival trade; the specified four free ships and 300-credit start still need their layouts and actual opening research/economy playtest. The current three-Drone start remains active; Gate C is provisional until that review passes.

`tests/test_shared_research.gd` covers real grouped purchases, insufficient RP, prerequisites/readiness/story gates, duplicate and failed-save handling, physical construction, lab ranks, shared stats/caps, finite repairs, source destruction/replacement, pickup/retry persistence, missile/craft defense, old frozen records, deterministic shared-content replay and the real earn/purchase/construct route. The complete isolated regression and final focused results are recorded in TODO.md. Existing certificate-store and shutdown-resource diagnostics remain separate from assertions.

Changed implementation files: `data/definitions.json`; `scripts/shared_support.gd`, `game_state.gd`, `transaction_ledger.gd`, `run_checkpoint.gd`, `battle_simulation.gd`, `auto_battle.gd`, `alien_ship.gd`, `ship_weapon_stats.gd`, `ship_part_pattern.gd`, `ship_stats.gd`, `ship.gd`, `fleet_ship.gd`, `formation_board.gd`, `game_map.gd`, `upgrades_panel.gd`, `research_panel.gd` and `research_view_model.gd`; `tests/test_shared_research.gd`, `test_definitions.gd`, `test_research.gd`, `test_research_ui.gd` and `run_baseline.ps1`; the checklist and related docs. Godot import also refreshed generated caches and new script UIDs.
