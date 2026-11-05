# Equipment stacking and weapon review

2026-11-05. Source audit and proposed first-pass tuning; implementation awaits user decisions. No equipment behavior or balance changed in this review.

## Support equipment

Command Uplink currently uses the first operational copy on each ship, marks one target for five seconds every 20 seconds, and grants +20% allied damage (+30% with Command I). When multiple ships mark the same target, the damage resolver returns the first matching mark rather than combining them. Extra uplinks on the same host do nothing.

Proposed: retain the existing target selection, 500 range, five-second duration and 20-second interval. Each operational uplink contributes +20% damage to its host's marked target, or +30% with Command I. Add contributions from all living allied hosts marking that target. Two copies therefore give +40%/+60%, never 1.2 squared or 1.3 squared. No hidden cap; mounts and ship capacity constrain investment. Ten simultaneous ordinary uplinks would give +200%, so this is a meaningful fleet-support balance decision. Lost hosts cease contributing; a host's active matching copies determine its contribution.

Alternative for the user: extra uplinks accelerate the mark cycle instead of increasing damage. That improves uptime but does not combine damage amplification from copies.

Shield Relay currently transfers at most two shields per second per host regardless of copy count. It transfers existing shields to a nearby ally with a lower shield fraction; it does not generate shields. A donor without shield capacity cannot transfer, and recipients also need shield capacity.

Proposed: two shields per second per operational relay, so two copies transfer up to four per second. Retain range 180, the current recipient selection and fraction equalization, donor/recipient capacity limits and shield conservation. Do not add free shields, extra capacity, regeneration or a new targeting system.

Sources: [support doctrines](../scripts/combat_doctrines.gd), [equipment catalog](../data/slot_equipment.json).

## Weapons

These figures exclude chassis/research bonuses, travel time, interception, protection, shield overflow, target movement and first-shot timing. They expose the current tradeoffs; they are not measured battle outcomes. Charge time overlaps the weapon cooldown, so it is not added to the nominal fire interval.

| Weapon | Current behavior | Proposed first pass |
| --- | --- | --- |
| Double Laser, M | Two 14.4-damage hits every four seconds: 7.2 DPS, range 220, mass 6, price 85. | Retain as the comparison point. |
| Ion Emitter, M | Base hit 2 every two seconds. Its existing multipliers yield 2 shield DPS or 0.5 hull DPS; range 300, mass 4, price 85. Ion Pulse requires Disruption I. | Base hit 8: 8 shield DPS or 2 hull DPS. Retain range, interval, shield/hull multipliers and researched Ion Pulse. It should be useful against shields before research. |
| Missile Rack, M | Three missiles dealing 3 each every five seconds: 1.8 DPS, range 340, mass 6, price 85; each parent spends one fleet missile. | Damage 12 per missile: 7.2 DPS. Retain three-shot salvos, interval, range, mass, cost, interception and one ammo debit per parent. Range and burst distinguish it; ammo and interception are its costs. |
| Beam Lance, L | Hit 12 every four seconds: 3 nominal DPS, range 360, mass 6, price 160. A 1.2-second charge aims at the original position and can miss moving targets. Its old component-penetration loop adds no extra damage against the active single hull pool. | Hit 48: 12 nominal DPS. Retain charge/miss behavior, interval, range, mass, cost and rare research access. Define its role through a strong charged hit; do not claim component piercing or introduce a new penetration mechanic. |
| Railgun, L | Hit 24 every six seconds: 4 nominal DPS, range 500, mass 10, price 240; bypasses Sentinel cover when shields are down. | No change in this proposal. Its lower damage versus the proposed lance needs observation in the focused comparison; range, projectiles and cover penetration differ. |

Research remains unchanged. Applied Energy gives lasers +15% damage; Prismatic Lasers ramps qualifying Laser/Double Laser beams to twice damage, excluding Beam Lance. Guided Munitions adds 25% missile range. Siege I produces three half-damage fragments per parent and Siege II increases fragment damage by 20%. At the proposed missile damage, aggregate nominal output is 10.8 DPS with splitting, or 12.96 with Siege II, only if all fragments hit. Applied Energy gives the proposed lance 13.8 nominal DPS. Existing Command I strengthens each proposed uplink contribution to +30%.

Sources: [equipment catalog](../data/slot_equipment.json), [damage and firing](../scripts/battle_simulation.gd), [charge and support behavior](../scripts/combat_doctrines.gd), [research combat](../scripts/research_combat.gd), [research modifiers](../scripts/research_upgrades.gd).

## Implementation and focused verification after approval

- Implement only approved stacking and tuning, with concise equipment details showing the actual effect. Keep current prices, mounts, ammunition, finite reserves, ownership, hull and UID rules.
- Check one/two uplinks on one host, allied overlapping marks, Command I, expiry and source loss; check one/two relays, equalization, empty donors, full recipients, missing shields and conservation.
- Compare the approved weapons through actual firing and damage against shielded/unshielded, stationary/moving and protected targets. Check missile expenditure/interception/splitting, lance charge/misses and research modifiers. Keep the workload bounded; no campaign sweep or soak.
- Bring observed role failures or further tuning decisions back to the user before changing additional equipment or research.
