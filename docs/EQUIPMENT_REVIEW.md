# Equipment stacking and weapon review

2026-11-05. The user approved additive uplink/relay effects and the first-pass weapon values below. They are implemented and verified with focused support checks, controlled firing samples and native equipment-detail review. Further tuning remains a user decision.

## Support equipment

Before this pass, Command Uplink used the first operational copy on each ship, marks one target for five seconds every 20 seconds, and grants +20% allied damage (+30% with Command I). When multiple ships mark the same target, the damage resolver returned the first matching mark rather than combining them. Extra uplinks on the same host did nothing.

Implemented: retain the existing target selection, 500 range, five-second duration and 20-second interval. Each operational uplink contributes +20% damage to its host's marked target, or +30% with Command I. Add contributions from all living allied hosts marking that target. Two copies therefore give +40%/+60%, never 1.2 squared or 1.3 squared. No hidden cap; mounts and ship capacity constrain investment. Ten simultaneous ordinary uplinks would give +200%, so this is a meaningful fleet-support balance decision. Lost hosts cease contributing; a host's active matching copies determine its contribution.

Before this pass, Shield Relay transferred at most two shields per second per host regardless of copy count. It transfers existing shields to a nearby ally with a lower shield fraction; it does not generate shields. A donor without shield capacity cannot transfer, and recipients also need shield capacity.

Implemented: two shields per second per operational relay, so two copies transfer up to four per second. Retain range 180, the current recipient selection and fraction equalization, donor/recipient capacity limits and shield conservation. Do not add free shields, extra capacity, regeneration or a new targeting system.

Sources: [support doctrines](../scripts/combat_doctrines.gd), [equipment catalog](../data/slot_equipment.json).

## Weapons

These figures exclude chassis/research bonuses, travel time, interception, protection, shield overflow, target movement and first-shot timing. They expose the current tradeoffs; they are not measured battle outcomes. Charge time overlaps the weapon cooldown, so it is not added to the nominal fire interval.

| Weapon | Before tuning | Implemented first pass |
| --- | --- | --- |
| Double Laser, M | Two 14.4-damage hits every four seconds: 7.2 DPS, range 220, mass 6, price 85. | Retain as the comparison point. |
| Ion Emitter, M | Base hit 2 every two seconds. Its existing multipliers yield 2 shield DPS or 0.5 hull DPS; range 300, mass 4, price 85. Ion Pulse requires Disruption I. | Base hit 8: 8 shield DPS or 2 hull DPS. Retain range, interval, shield/hull multipliers and researched Ion Pulse. It should be useful against shields before research. |
| Missile Rack, M | Three missiles dealing 3 each every five seconds: 1.8 DPS, range 340, mass 6, price 85; each parent spends one fleet missile. | Damage 12 per missile: 7.2 DPS. Retain three-shot salvos, interval, range, mass, cost, interception and one ammo debit per parent. Range and burst distinguish it; ammo and interception are its costs. |
| Beam Lance, L | Hit 12 every four seconds: 3 nominal DPS, range 360, mass 6, price 160. A 1.2-second charge aims at the original position and can miss moving targets. Its old component-penetration loop adds no extra damage against the active single hull pool. | Hit 48: 12 nominal DPS. Retain charge/miss behavior, interval, range, mass, cost and rare research access. Define its role through a strong charged hit; do not claim component piercing or introduce a new penetration mechanic. |
| Railgun, L | Hit 24 every six seconds: 4 nominal DPS, range 500, mass 10, price 240; bypasses Sentinel cover when shields are down. | Unchanged in this pass. Its lower damage versus the tuned lance needs observation in the focused comparison; range, projectiles and cover penetration differ. |

Research remains unchanged. Applied Energy gives lasers +15% damage; Prismatic Lasers ramps qualifying Laser/Double Laser beams to twice damage, excluding Beam Lance. Guided Munitions adds 25% missile range. Siege I produces three half-damage fragments per parent and Siege II increases fragment damage by 20%. At the tuned missile damage, aggregate nominal output is 10.8 DPS with splitting, or 12.96 with Siege II, only if all fragments hit. Applied Energy gives the tuned lance 13.8 nominal DPS. Existing Command I strengthens each stacked uplink contribution to +30%.

Sources: [equipment catalog](../data/slot_equipment.json), [damage and firing](../scripts/battle_simulation.gd), [charge and support behavior](../scripts/combat_doctrines.gd), [research combat](../scripts/research_combat.gd), [research modifiers](../scripts/research_upgrades.gd).

## Focused verification results

The new focused suite passed 126 checks, including support copies and allied overlaps, research, source loss, expiry, shield conservation, transfer limits, actual firing, shield-breaking overflow, missile spending/interception/splitting and laser modifiers. Research redesign and combat regression checks passed 117 and 208 checks. Native equipment details passed 66 checks, with captures reviewed at 640x360, 1280x720 and 1920x1080; tuned fits survive Continue.

The suite recorded 36 controlled 12-second firing samples using the actual firing, charge, projectile, collision and damage paths. It held the shooter still, scripted target positions and omitted enemy firing and general combat AI. Moving targets oscillated laterally by 60 units at two radians/second; targets had enough hull/shields to avoid kills. These samples compare specific mechanics, not campaign outcomes or full encounter win rates.

| Weapon, without research | Stationary hull damage | Shield damage | Moving-target hull damage | Hull damage under Sentinel cover |
| --- | ---: | ---: | ---: | ---: |
| Ion Emitter | 24 | 96 | 24 | 19.2 |
| Missile Rack | 108 | 108 | 108 | 86.4 |
| Beam Lance | 144 | 144 | 0 | 115.2 |
| Double Laser, unchanged | 86.4 | 86.4 | 86.4 | 69.12 |
| Railgun, unchanged | 48 | 48 | 48 | 48 |

Each tuned weapon delivered four times its previous damage under the same sample conditions. Ion fired six times, missiles fired three salvos costing nine ammunition, and the lance fired three charges. All lance charges missed the scripted mover; its stationary impacts succeeded. Splitting with Siege II produced 194.4 damage for the same nine missiles; the lance with Applied Energy produced 165.6 damage. Guided Munitions range, research eligibility and finite reserves were unchanged.

The observed roles are shield specialization for ion, ammunition-funded guided damage for missiles and a stronger but avoidable charged hit for the lance. Railgun retains range 500 and Sentinel-cover penetration; its raw output is lower than the tuned lance at this close range. This remains a first pass. No further weapon/research changes, campaign sweep, broad acceptance or soak were performed. Local logs, JSON and captures are under .local/checks/equipment-balance/. Expected malformed-effect rejection, certificate-store and existing shutdown resource diagnostics remain.

Focused entry point: [test_equipment_balance.gd](../tests/test_equipment_balance.gd).

## 2026-11-05 - Relay shield capacity and computer clarity

The user subsequently requested shield capacity on the relay. Each copy now adds 10 shields while retaining its additive two-shield/second transfer, range 180 and fraction equalization. Normal shield recovery applies at 4% per second after four seconds without damage: 0.4/s per relay. An empty pool still transfers nothing until recharged; the relay works without a separate generator. Recipients still need their own capacity.

Tactical Computer behavior is unchanged; its equipment text now explains the weapon cooldown reset and wait for an unshielded target. One computer charges in 12 seconds, two in six; Command II improves a single computer to 9.6 seconds. Beam charges and ammunition rules remain. Focused support-only and native checks are recorded in COMPLETED.md.
