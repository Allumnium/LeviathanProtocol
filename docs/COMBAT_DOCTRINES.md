# Energy and Survival intermediates (step 55)

Implemented October 30, 2026. Definitions revision 2026-10-30.2 enables only the first two Energy and Survival tiers and their eight components. Endpoints and Optional / Extra features remain disabled. Existing branch prices remain provisional until step 61's campaign pacing review.

## Behavior and initial tuning

| Path | Component | Effect and tradeoff |
|---|---|---|
| Optics I | Focusing Lens | First two touching beam components: +20% shot damage and range, +25% firing interval and +0.25 s charge. Same-type lenses do not stack. Source loss removes the bonus. |
| Optics II | Beam Lance | 12 damage / 4 s, range 360, 1.2 s locked-aim charge. Normal shields apply; at most two exposed physical components receive the remaining hull damage. Targets can move away from the warned point; source destruction, loss of sight or Ion interruption cancels the pending shot. |
| Disruption I | Ion Emitter | Basic fire: 2 damage / 2 s, range 300; twice shield damage and half hull damage. Shield overflow converts at the hull rate. Ion Pulse: visible enemy within 300, shared 24 s cooldown, interrupts a charge and suppresses shield regeneration for 4 s. Warden accepts one interruption per charge. |
| Disruption II | Gravitic Snare | Gravity Well: visible area within 350, radius 100, shared 30 s cooldown, 35% movement/turn reduction for 5 s. No stacking or immobilization. Search/radar movement is slowed too. |
| Bastion I | Reactive Bulkhead | First two touching components receive 30% less projectile hull damage. Shields and beams receive no extra protection; a source cannot protect itself. Duplicate sources do not multiply the reduction. |
| Bastion II | Shield Relay | One transfer stream per hull, at most 2 shield points/s to an ally within 180. The host pays exactly what the ally receives. Transfers move fractions toward equality without overfilling either hull; duplicate relays do not multiply the rate. |
| Renewal I | Repair Drone Bay | Each initial operational bay contributes 20 HP to the encounter allowance. Launch a 4 HP payload every 2 s toward a damaged living component within 220. Drone: 2 HP, speed 100, lifetime 6 s, targetable craft/summon under the shared live-64 cap. Interception, source loss or failed delivery spends the payload; no refund, resurrection or salvage payout. |
| Renewal II | Nanoforge | One destroyed non-command component per surviving host, at 25% HP. Multiple forges on one hull do not add reconstructions. Empty hardware returns; passengers and goods do not. A destroyed command center cannot be restored. |

Optics favors adjacency and deliberate long-range aim. Disruption trades hull damage for shield pressure, interruption and space control. Bastion needs protected placement and shield-bearing allies. Renewal needs surviving sources and vulnerable, finite deliveries. Baseline ships remain usable without these branches.

## Shared rules and persistence

Crew improves repair-drone launch cadence while preserving the 20 HP allowance. Instant Nanoforge reconstruction consumes no Crew recipient slot. Energy Manipulation also applies to the new energy weapons under the existing +30% ordinary efficiency cap.

Existing research exclusion and component identity rules authorize both branch tiers and their exact shared recipes. New assembly in a run sees one legal opposite-branch recipe. Saved assembled identity remains explicit; no catalog, material enum or component ID was renumbered. Both paths can mix with other general equipment in the three ordinary families, within normal deployment capacity and prices.

The existing ability bar exposes Ion Pulse and Gravity Well alongside Scan. Both use the standard source selector, Auto preference, optional pause-to-aim, commit validation and durable shared cooldowns. Auto uses visible opponents; a hidden/out-of-range target consumes nothing. Control effects do not contribute visibility sources. Only Scan reveals an area.

CombatDoctrines owns pending charged shots, repair flights and support expenditure. Only the encounter allowance and its expenditure persist across withdrawal/reload/refit; actor motion and unfinished casts use the existing replay/checkpoint model. A retried encounter does not replenish used drone payloads or reconstruction capacity, including a newly fitted replacement hull. A new destination initializes a new allowance. Doctrine state is shape/range validated in deployment and field checkpoints; older saves default to no prior allowance.

Physical destruction latches loss of contents until a successful accounting checkpoint. This covers destruction followed by same-tick Nanoforge reconstruction: casualty fees and lost cargo are settled before the empty rebuilt hardware is saved. Failed writes keep the latch; successful accounting clears it, allowing normal boarding/refill on a later genuine arrival. No passenger/cargo inventory is restored from the blueprint.

Changed runtime files: combat_doctrines.gd, ship_part_pattern.gd, ship_weapon_stats.gd, ship_stats.gd, adjacency_rules.gd, battle_simulation.gd, battle_abilities.gd, battle_visibility.gd, battle_visuals.gd, fleet_ship.gd, passenger_rules.gd, cargo_rules.gd, game_state.gd, run_checkpoint.gd, auto_battle.gd, battle_ability_bar.gd, research_view_model.gd and data/definitions.json. Existing procedural component art and shared Starhull/theme styles are reused. No new tooltip, focus cycling or modal was introduced.

## Validation

The new test_combat_doctrines.gd covers real branch purchases and paid construction, exact-recipe authorization, duplicate adjacency sources, charge timing/cancellation/dodging and two-component penetration, complete Double Laser volleys, combat activity, actual Warden interruption, Ion shield/hull behavior, bounded control and shield transfers, interceptable finite repairs, reconstruction limits, malformed deployment data, fixed-tick replay, failed saves and occupied reconstruction losses.

The actual two-hull support checkpoint preserves a 40 HP drone allowance with 8 HP spent and two used reconstruction identities across JSON reload. The occupied cabin pays its 80-credit loss once; the rebuilt hold contains no goods. Native controller tests exercise pointer targeting for both controls at 640x360, durable cooldown commits, pause, 2x speed, victory and reload.

All 46 baseline suites pass in .local/doctrines/baseline-final.log (isolated run .local/checks/8ac33a9b093f4a6eb7d2421266ee6877/), including six complete first acts and 600 basic battles. Final Crew/Energy integration and reconstructed-battle settlement additionally pass integration-{combat_doctrines,adjacency,shared_research,ship_stats,battle_replay,research_ui}.log. Native final checks pass in native-final-combat_doctrines.log: actual pointer casts, pause/2x, durable cooldowns, visible charge pixels, hidden-geometry pixel equality, new research details and focus controls. A native unified-tree pass also succeeds in native-final-research_ui.log. Captures under .local/doctrines/ include controller-640.png, charge-640.png, and optics_i/optics_ii/renewal_ii-details-640.png; these were visually inspected. The minimum-zoom charge warning uses a two-unit antialiased line. UI placement/add/remove measured 46/274/213 ms; builder evaluation averaged 39.37 ms. Whitespace checks pass. Known Windows certificate-store and engine shutdown diagnostics remain tracked separately from gameplay assertions. Remaining campaign tuning and core component readability still belong to steps 61 and 66.
