# Research line redesign - implemented first pass

2026-11-05. The user approved this 20-card first pass, including effects, stacking, dependencies and equipment access. It is implemented and verified with focused checks and a bounded opening playtest. Guided Munitions uses +25% missile range following the user's implementation-time decision. Later balance changes remain decisions to bring back to the user.

The design requirement is that every research choice changes gameplay. Equipment access should be an occasional exception, and an ineffective card calls for reviewing its entire line. Keep the approved three/four-card selection, 20 RP then +20 per selection, excess RP, saved offers and science flagship bonuses.

## Audit before the redesign

There are 20 offered upgrades, excluding starting Foundation:

| Status | Cards | Evidence |
| --- | --- | --- |
| Active gameplay effect: 9 | Fleet Logistics I/II/III; Field Engineering; Civil Hospitality; Prismatic Lasers; Disruption I; Bastion II; Siege I | Command capacity, travel modifiers, income, continuous lasers, Ion Pulse, shield pulses and missile splitting have runtime consumers. Ion Pulse requires a living fitted Ion Emitter. |
| No new combat/travel benefit: 7 | Applied Energy; Guided Munitions; Laboratory II; Renewal I; Siege II; Carrier I; Command I | Their ordinary equipment is already available. Repair drones, interceptors and uplink marking already operate from equipment. Railguns already bypass Sentinel cover without Siege II. The current hangar registry does not grant Command I's old active Focus Mark ability. |
| Equipment access only: 4 | Laboratory III; Optics II; Carrier II; Command II | Unlock Lab III, Beam Lance, Bomber Bay and Tactical Computer respectively; these cards do not independently improve existing equipment. |

Sources: [active catalog](../scripts/hangar_research.gd), [equipment availability](../scripts/ship_loadouts.gd), [research consumers](../scripts/hangar_state.gd), [combat effects](../scripts/research_combat.gd), [support doctrines](../scripts/combat_doctrines.gd), [carrier behavior](../scripts/hangar_carriers.gd), [baseline railgun penetration](../scripts/battle_simulation.gd).

This audit concerns the active physical-hangar/expedition loop. It does not turn archived equipment/grant metadata into new gameplay requirements.

## Implemented complete lines

The approved effects below retain existing working behavior and add meaningful benefits to every formerly ineffective or access-only card.

| Line | Progression and choice effects | Dependencies and access |
| --- | --- | --- |
| Fleet Logistics | I → II → III: retain total command bonuses of +8 / +24 / +108. Each choice expands usable fleet capacity. | Keep sequential prerequisites; shared across builds. No equipment grant. |
| Energy core | Applied Energy improves Laser/Double Laser damage. Prismatic Lasers follows it and retains sustained beams that ramp with uninterrupted contact. | Preserve Applied Energy → Prismatic Lasers. No equipment grant or removal of baseline lasers. |
| Energy specializations | Optics improves existing laser range; also unlocks Beam Lance as a rare exception. Disruption retains Ion Pulse's interruption and shield-recovery suppression. | Both follow Applied Energy and remain mutually exclusive with each other. Prismatic Lasers remains shared, as today. Ion Pulse keeps its fitted-emitter requirement. Rename visible Optics II to Optics I because there is no offered Optics I prerequisite. |
| Missile and siege | Guided Munitions improves guided-missile range. Siege I retains splitting missiles. Siege II improves fragment damage and railgun hull damage instead of claiming baseline cover penetration. | Guided Munitions → Siege I → Siege II. Preserve baseline interception, one ammunition debit per parent missile and baseline railgun penetration. No equipment grant. |
| Carrier | Carrier I launches available interceptors more quickly. Carrier II improves existing carrier-craft damage and unlocks Bomber Bay as the second rare exception. | Carrier I → Carrier II. Remove the unrelated Guided Munitions prerequisite. Keep the existing Siege/Carrier commitment; only actual opposite-path cards count as consequences. No new craft type, free bay or free sortie. |
| Shield survival | Keep the existing periodic shield recovery under fire. Rename visible Bastion II to Bastion I so the first offered shield upgrade is not presented as a missing second tier. | Starting shield specialization; remains exclusive with Renewal. Do not restore the retired Bastion I node or add a new tier just to fill a line. |
| Repair survival | Renewal I improves passive hull-repair speed and repair-drone travel speed. Both strengthen sustain rather than introducing repair equipment the player already has. | Remove the unrelated Field Engineering prerequisite. Keep the Shield/Renewal commitment. Never revive destroyed ships, recreate lost loads, refill reserves or reset equipment allowances. Do not restore deferred Renewal II. |
| Command | Command I strengthens the damage benefit of existing uplink marks. Command II speeds up existing Tactical Computer synchronization. | Command I → Command II. Tactical Computers become ordinary purchasable equipment under the approved two-exception policy. Remove the empty Command/Covert exclusivity and its misleading lock message; Covert is not an implemented alternative. |
| Science | Replace Laboratory II/III cards with Research Methods I/II. I increases output from existing labs; II adds a further output improvement. Both affect labs already fitted, including lower ranks. | Keep I → II and the current late-tier story gate initially. Lab (XL) is ordinary purchasable equipment under the approved two-exception policy; it still requires a compatible mount and its purchase cost. Research output stacks explicitly with the science flagship's existing host-lab bonus; the fourth-option bonus stays. |
| Travel engineering | Keep Field Engineering's faster cruise and lower distance-based fuel use. | Shared upgrade, no equipment grant. Stop using it as a compulsory entry toll for repair research. |
| Civil economy | Keep Civil Hospitality's travel income, without requiring a new cabin purchase to receive it. | Shared upgrade, no equipment grant. Preserve distance-based accrual and no retroactive payout. |

This retains 20 cards rather than expanding the catalog with filler or new systems. Renaming visible tiers does not require resurrecting omitted nodes. Equipment remains purchased and fitted normally; an unlock never supplies a free physical item.

## Implemented first-pass tuning

These are approved starting values for focused playtesting, not final balance claims. Existing working effects retain their current values.

| Card | Effect | Applicable deployed equipment |
| --- | --- | --- |
| Fleet Logistics I | Total research command bonus +8. | Fleet-wide. |
| Fleet Logistics II | Replace the research command bonus with +24 total. | Fleet-wide; requires I. |
| Fleet Logistics III | Replace the research command bonus with +108 total. | Fleet-wide; requires II. |
| Applied Energy | +15% laser damage. | Laser-family weapons, including qualifying future variants. |
| Prismatic Lasers | Keep continuous beams ramping to 2× damage over four seconds of uninterrupted contact. | Weapons explicitly supporting this beam conversion; requires Applied Energy. Charged Beam Lance firing is not converted. |
| Optics I (currently Optics II) | +20% laser range; unlock Beam Lance purchases. | Existing laser-family weapons; requires Applied Energy. |
| Disruption I | Keep Ion Pulse: interruption and four seconds of shield-regeneration suppression, 24-second shared cooldown. | Operational Ion Emitter capability; requires Applied Energy. |
| Guided Munitions | +25% guided-missile range. | Guided-missile weapons. No extra ammunition or removal of interception. |
| Siege I | Keep three fragments at half parent damage each, with one parent ammunition debit. | Missile weapons that support splitting; requires Guided Munitions. |
| Siege II | +20% split-fragment damage and +20% railgun damage reaching hull. | Splitting missiles or railguns; requires Siege I. Shield absorption, baseline cover penetration and boss protection remain. |
| Carrier I | +25% carrier launch rate: a single unmodified deck's four-second interval becomes 3.2 seconds. | Operational flight-deck capability. |
| Carrier II | +20% carrier-craft weapon damage; unlock Bomber Bay purchases. | Operational flight-deck capability; requires Carrier I. |
| Bastion I (currently Bastion II) | Keep recovery of 25% maximum shields every eight seconds, including under fire; suppression blocks recovery. | Operational shield capability. |
| Renewal I | +25% passive hull-repair rate and +25% repair-drone travel speed. | A deployed ship with passive hull repair or an operational repair-drone bay. Each effect applies only where supported. |
| Command I | Uplink marks amplify allied damage by 30% total, replacing their current 20% benefit. | Operational command-uplink capability. |
| Command II | +25% Tactical Computer synchronization rate: 12 seconds becomes 9.6 seconds with one computer before other modifiers. | Operational synchronization-computer capability; requires Command I. |
| Research Methods I (currently Laboratory II) | +20% output from existing operating labs. | Operational research-lab capability, any rank. |
| Research Methods II (currently Laboratory III) | Replace the research output bonus with +40% total. | Operational research-lab capability; requires I and the current story gate. |
| Field Engineering | Keep +25% cruise speed and −25% distance-based fuel use. | Fleet-wide. |
| Civil Hospitality | Keep four credits per traveled day, paid at existing quarter-day milestones. | Fleet-wide. |

Stacking: different research effects multiply their applicable base statistic once. A higher tier replaces its own earlier tier bonus, rather than multiplying the two. Research Methods therefore multiplies lab output by 1.2 or 1.4, alongside the science flagship's existing 1.25 multiplier on its own labs; its extra option is independent. Existing equipment-copy stacking remains unchanged.

Carrier research does not change active-craft limits, ammunition, sortie lifetime, finite replacement capacity, reserves already spent or equipment UID tracking. Repair research does not replenish payload reserves, accelerate repair-delivery ticks, revive destroyed ships or recreate lost loads. No new equipment, craft types, boss phases, ECM/Phase mechanics or campaign content are part of this first pass.

The user approved these values and line/dependency changes for implementation and focused playtesting. Subsequent balance adjustments require a new decision.

## Offer relevance

Approved 2026-11-05: equipment-specific cards require matching equipment in the deployed fleet. A carrier upgrade needs an operating flight deck, and an Ion Pulse card needs an operating emitter. Shared capacity, cruise and income cards remain broadly applicable. Science cards need operating labs.

The user plans an equipment pool at least four times its current size. Applicability should therefore use explicit equipment-family/capability metadata shared by offer eligibility and effect application, rather than research checks scattered across individual equipment IDs. New laser variants should join the laser upgrade family by declaring their capabilities. This is support for the planned expansion, not a request to create its equipment content now.

- Define a clear target family for each equipment-specific effect, including any exclusions. A family match must mean the effect actually works on that equipment; names or artwork are not enough.
- Beam Lance's exceptional unlock card matches existing laser equipment, and Bomber Bay's card matches existing flight decks. Neither requires the still-locked item.
- Reuse the same capability predicate when drawing offers, validating choices and applying effects. An upgrade cannot advertise compatibility with an item that its runtime effect ignores.
- Match living, deployed, operational equipment; inventory, destroyed ships and unequipped purchases do not qualify. Shared capacity, cruise and income effects are fleet-level and need no equipment-family match.
- Preserve saved offers without rerolling on a refit. If the fleet removes the last matching item after an offer is drawn, keep that card and disable its choice with a concise requirement until matching equipment is deployed again. Do not spend RP on the rejected choice.
- If fewer relevant cards exist, show those remaining cards rather than repeat cards or grant unrelated equipment.

Card text must state the actual change. Keep one short gameplay sentence; show a fitted-equipment requirement or an exclusive-path consequence separately only when it changes the player's decision. Do not describe an existing baseline feature as a new reward.

## Approval and verification

The user approved the complete first-pass proposal, the two rare unlocks, matching deployed equipment and a mix of stat upgrades and behavior changes. During implementation, the user replaced the ineffective turning-rate proposal with missile range; the implemented first-pass value is +25%.

Focused verification covered all changed effects, stacking, capability matching, refits, finite reserves/UIDs, saved offers and Continue. Native card checks covered three supported resolutions, disabled saved cards and restored matching equipment. A bounded opening playtest verified naturally earned choices and actual Research Methods output changes. Results are recorded in [COMPLETED.md](../COMPLETED.md); focused entry points are in [tests/README.md](../tests/README.md). No full campaign sweep or soak was run.

## 2026-11-05 - Lab size simplification

The user subsequently chose Lab (M), producing 1 RP per travel day, and Lab (XL), producing 3 RP per travel day. The L lab is removed from the active catalog. Research Methods and host bonuses still multiply both sizes. Former L-lab mounts in predefined fits receive the approved Large Plate (+100 hull, mass 8, catalog price 160 credits); the science Survey keeps its cargo hold. Starting defensive/science fleets consequently produce 1/1.25 RP per day. Earlier opening-playtest numbers above describe the preceding three-size fits.
