**Leviathan Protocol — implementation handoff**

Design baseline: October 25, 2026. This document supersedes the earlier proposal. It specifies proposed behavior, not functionality already implemented. Numerical balance values are initial tuning targets. Implement the milestones in order; do not attempt the entire catalog in one change.

**1. Product decisions and scope**

- The player builds a fleet, chooses routes toward the Leviathan, researches material combinations, and fights primarily automatic battles with optional targeted abilities.
- Enemy strength depends on geographic proximity to the Leviathan, difficulty, and encounter type. It NEVER depends on player ship count, fleet strength, laboratories, passenger count, resources, or research progress.
- Keep three regular active design slots. Add one dedicated Science Vessel slot and one dedicated Civic Vessel slot. Each dedicated slot holds exactly one deployed ship. This intentionally expands the earlier three-type limit to three regular types plus two restricted support types.
- Start with two Drones, one Science Vessel, and one Civic Tender. The Drones share one regular design slot. Dedicated slots persist if their ship is lost; the ships themselves are destructible and replaceable.
- All deployed ships, including dedicated support ships, consume deployment capacity. Dedicated slots do not provide free combat power.
- Purple/Core material is **Civic**. Keep its existing serialized numeric category; change display terminology without breaking saves. Use **Foundation** for initially known technology to avoid confusing it with Civic material.
- Target 48 distinct equipment types in the complete catalog. Forty was a guideline. Equipment ranks do not count as additional types.
- Preserve the existing component damage model. Intact disconnected equipment remains operational; destruction removes the component and its adjacency effects. Do not introduce cascading disconnection deaths in this project. Update contradictory help text.
- Ship design is free. Construction, repairs, refits, research, and deployment limits create the economic decisions.
- Research and branch commitments reset per run. Blueprints and encyclopedia knowledge persist, but cannot bypass current-run unlocks.

**2. Story premise and fixed checkpoints**

Humanity already understands the underlying technology. Research is field engineering: discovering reliable combinations of familiar materials that withstand the Leviathan's interference. This explains why the foundation is known while advanced recipes require battle observations.

The fleet is a civilian-backed expedition following a moving anomaly through failing jump lanes. Its Science Vessel interprets the signal; its Civic Tender handles supplies, paying expedition passengers, and optional rescue work. The Leviathan is an ancient autonomous ark whose corrupted preservation system is consuming settlements and assimilating ships. Its guardians are coordinated by a signal network. The expedition must break that network and reach the ark's command core.

Tourists are informed expedition passengers, observers, and patrons. Rescued civilians are separate story objectives: never automatically convert refugees into paying tourists. Boarding paying passengers is optional.

| Act | Story and environment | Fixed checkpoints and unlocks |
|---|---|---|
| I — The Broken Lanes | Outer settlements, abandoned tourist routes, scattered alien patrols. Establish that the attacks are coordinated rather than random. | Start at Haven Anchorage. At the pre-boss Relay Outpost, decode the first signal. Defeat the Bastion Warden to open the inner route, unlock lab III research, and raise deployment capacity to 42. |
| II — The Graveyard Current | Wreck fields and ship nurseries. Discover that the Leviathan is repurposing ships and infrastructure. | At the pre-boss Refuge Dock, evacuate civilians and identify the brood network. Defeat the Brood Architect to expose the Leviathan's approach, unlock major capstone research, and raise deployment capacity to 54. |
| III — The Whispering Dark | Distorted space, coordinated guardians, unstable shielding, and visible Leviathan anatomy. | At Last Light Anchorage, receive the final briefing, refit, and disembark passengers. Defeat the Leviathan to sever the corrupted command system. |

Mandatory story information is delivered at fixed checkpoints; optional routes add context and rewards, not required quest keys. No exclusive technology is required to advance the story. Major checkpoint scenes are short, skippable after the first viewing, and archived.

**3. Campaign map specification**

Use a seeded directed acyclic graph with three acts, eight forward rows per act, plus the starting anchorage. A normal run visits 24 nodes and fights 14 battles. Noncombat stops are additional decisions, not replacements that accidentally starve research.

| Act | Mandatory combat rows | Other rows |
|---|---|---|
| I | 1, 3, 5, 8 | Rows 2, 4, 6 are noncombat choices; row 7 is the staging checkpoint. |
| II | 1, 2, 4, 5, 8 | Rows 3 and 6 are noncombat choices; row 7 is the staging checkpoint. |
| III | 1, 2, 4, 5, 8 | Rows 3 and 6 are noncombat choices; row 7 is the staging checkpoint. |

Combat rows can offer patrols, elites, defense objectives, interception, or convoy battles. For the first implementation, noncombat nodes never hide surprise fights. This preserves the 4/5/5 battle cadence. Later optional battles require explicit preview and separate pacing validation.

Graph generation rules:

1. Ordinary rows contain 2–4 nodes. Use visibly different lane positions with bounded visual jitter.
2. Edges always advance exactly one row. Nodes have 1–3 outgoing edges; prohibit cycles, backward edges, and dead ends.
3. Generate lane paths first, then add selected cross-lane edges. Allow routes to split, briefly merge, and split again. Do not retain the current two parallel lanes for an entire act.
4. Each act contains at least two reachable forks and one merge before the staging checkpoint. At least one fork has three distinct choices.
5. Row 7 converges at the named staging checkpoint; row 8 is the boss. The boss leads to the next act or the ending.
6. Every node is reachable from the start and can reach its act boss. Validate these properties after generation; use a known-valid fallback map if generation fails.
7. No mandatory elite. No consecutive elites. A non-elite continuation must exist at each elite fork. No normal battle has more than one environmental hazard in the first release.
8. Each act offers a noncombat port before its staging checkpoint, reachable from every route's first combat node. Place this port on row 4 in Act I and row 3 in Acts II/III; alternate nodes on that row can offer different port services. All staging checkpoints also provide full port services.
9. Freeze graph, encounter templates, rewards, enemy rosters, and environmental modifiers at run creation. Preserve them in the save. Inspecting, reloading, or changing the fleet never rerolls a node.

Node types and previews:

| Node type | Gameplay | Visible information |
|---|---|---|
| Patrol | Standard combat | Role tags, contact-count band, threat, reward band |
| Elite | More dangerous combination of familiar enemies | Elite identity, abilities, larger reward; optional route |
| Convoy escort | Protect a neutral convoy until it reaches extraction | Escort count, route, flanking threat, objective timer |
| Interception | Destroy a marked carrier before its withdrawal timer | Target role, time limit, escort composition |
| Relay defense | Hold an objective through finite announced waves | Wave count, total threat, enemy roles |
| Port/shipyard | Repair, refit, buy resources, board/disembark passengers | Services and indicative prices |
| Salvage field | Choose a guaranteed material bundle or a costed recovery option | Material tendencies and costs; no surprise battle |
| Scenic survey | Safe optional tourist fare opportunity and story observation | Passenger eligibility, reward, no RP |
| Signal/event | Choose between explicit resource, repair, information, or story outcomes | Stakes before commitment; unknown story text does not hide mechanical penalties |
| Staging checkpoint | Guaranteed preparation and story delivery | Full services, next boss briefing |
| Boss | Fixed story encounter | Identity, broad phases, major telegraphs, reward/unlock |

All nodes in the current act show type, broad threat, reward tendency, and connections. Directly reachable nodes additionally show enemy role tags, a truthful contact-count range, objective, hazard, and known major abilities. Future acts show their theme and boss; reveal their route graph on entry. Exact hidden numbers must remain inside advertised bands.

The Science Vessel can improve information two steps ahead; it must not be required to understand the immediate next node. Provide route highlighting, a persistent legend, icon shapes plus colors, and enough hit area for the current small-resolution UI. Example preview: “Interception — 5–7 contacts — carrier / missile escorts — ion storm — destroy carrier within 75 s — Tech-rich salvage.”

**4. Threat scaling: proximity only**

Assign global row r from 1 through 24. Define proximity p = (r - 1) / 23. Screen position and route length do not affect p. Side-by-side nodes have identical base proximity.

Initial encounter budget:

    base_threat = 100 * 5^p
    threat = base_threat * encounter_multiplier * difficulty_multiplier

Use encounter multipliers 1.0 for standard objectives, 1.4 for elites, and 1.8 for bosses. Start with difficulty multipliers 0.8 / 1.0 / 1.25. Budget examples on Normal are roughly 100 at row 1, 293 for the first boss, 514 for the second boss, and 900 for the Leviathan. These are content-allocation units, not HP multipliers.

Each enemy definition has a threat cost that includes weapons, durability, mobility, and abilities. Encounter templates specify required roles and legal reinforcements. Spend the budget on those definitions. Introduce stronger variants as proximity increases; do not spend the whole late-game budget on hundreds of Scouts. Initial soft limits: 24 regular enemy ships, with bosses using a body plus organs and escorts; 64 total simultaneous combat entities including drones. Unspent budget is acceptable within a defined template tolerance.

Waves and spawned craft are included in the encounter's total budget. Boss phases are not three independently full-budget encounters. Difficulty must not secretly modify a frozen node after preview.

Remove BOTH existing scaling mechanisms: the multiplication of fleet size in GameState.set_destination and the player_ship_count-based health/damage normalization in AlienShip.create_random_fleet. A larger or more capable player fleet should genuinely make the same encounter easier. This is progression, not a balancing defect.

**5. Fleet composition and support ships**

Three regular slots allow three design families with multiple physical copies. A design revision stays in its family. Extra archived designs do not deploy until assigned to a slot. Permit swapping active families at secured nodes; changing the physical ships still costs construction/refit resources. Reserve ships grant no research, tourism, logistics, auras, or deployment benefits.

Dedicated ships:

| Slot | Required equipment | Restrictions | Starting loadout |
|---|---|---|---|
| Science | One active Research Lab | Exactly one ship; maximum six Offense material tiles; no strike-craft bays or offensive capstones; no passenger berths or Cargo Hold | Command Center, lab I, Crew Quarters, Shield, Thruster, two Mini Turrets, protective plates |
| Civic | Cargo Hold or passenger accommodation | Exactly one ship; maximum six Offense material tiles; no labs, strike-craft bays, or offensive capstones | Command Center, Cargo Hold, Crew Quarters, Shield, Thruster, two Mini Turrets, protective plates |

Regular ships can carry any legally researched equipment, including labs, passengers, and logistics. Equipment restrictions are for the two bonus slots, not global class locks. Offensive capstones are Stellar Lance, Singularity Projector, Siege Mass Driver, and Hive Carrier Core. Other capstones are permitted in dedicated slots if the hull and deployment limits allow them.

All hulls require exactly one Command Center. The dedicated ship designation must be validated from the loadout, not merely the saved name. Default support behavior is Escort: remain behind a selected regular ship, avoid pursuit, and retreat locally under threat. Dedicated ships are not invulnerable and cannot be replaced for free by repeatedly scuttling them.

Deployment cost per physical ship:

    2 + ceil(occupied_material_tiles / 12) + active_lab_level

Capacity is 30 / 42 / 54 across the three acts. Count all dedicated ships, all assembled component cells, and loose material tiles. Count actual occupied cells rather than the bounding rectangle. Start with 300 spendable credits and the current starting material stock, in addition to the four free starter ships. Tune these values using full-run simulations.

**6. Materials, construction, adjacency, and baseline balance**

| Material | Symbol | Function | Initial purchase price |
|---|---|---|---:|
| Offense | O | Weapons and destructive force | 5 |
| Defense | D | Structure, armor, shielding, protected machinery | 2 |
| Tech | T | Engines, energy, control, sensors | 8 |
| Civic | C | Crew, science, passengers, logistics, coordination | 6 |

Use recipes with mixed materials to make advanced systems draw on different supplies. Do not implement a global power grid or individual crew pathfinding in this project. Ordinary equipment works without Crew Quarters; crew improves it.

Adjacency rules:

- Only orthogonal contact between component footprints counts. Multiple touching edges do not multiply the bonus.
- Crew Quarters supplies +12% operating rate to up to three eligible adjacent equipment components. Selection is visible and player-adjustable; otherwise choose a stable component-ID order.
- Weapons gain firing rate; engines gain acceleration/turning; repairs gain throughput; shields gain recharge rate, not a shorter damage-interruption delay. Labs gain faster combat analysis, not extra RP from crew.
- Identical named buffs use the strongest source. Different ordinary efficiency buffs add, capped at +30%. Research bonuses use their own explicitly bounded calculation.
- Support-to-support amplification is disabled unless a specific recipe says otherwise. Bonuses never recursively amplify their source.
- Destruction immediately removes the source's buffs. Reconstructed equipment recomputes links once. Intact severed sections retain only the adjacency that actually remains.
- Concentrating components improves efficiency but creates a target for area attacks. Exposed observation equipment creates a tourism-specific placement risk.

Initial retuning targets: Laser approximately 3 DPS, Double Laser approximately 7.2 DPS, basic shield capacity 40, shield regeneration 4%/s after four seconds without damage. Armor should remain the cheapest persistent protection. Use one shared live-stat calculation for designer and battle. Derive speed, acceleration, and turning consistently from thrust and mass, with diminishing returns; do not leave top speed proportional to thrust alone. Give larger hulls a larger battle footprint rather than normalizing every design to the same apparent size. Validate these changes together before settling numerical weapon values.

Initial repair cost per fully damaged material tile: O 1, D 0.2, T 3, C 2. Round the final repair invoice upward, not each tile. Surviving damaged components can be repaired. Between-battle reconstruction of destroyed components requires their material cost, automatically buying shortages if affordable; it must not create cheaper infinite materials through repair-and-salvage. Dismantling refunds surviving material only. A full structural unit exists until its HP reaches zero, matching the current atomic component model.

**7. Research economy and branch rules**

Foundation equipment is known from the start. The archive records discoveries but is not an authorization source for construction. Validate research in the builder, imported blueprints, refits, construction, and deployment.

One lab can operate per ship. Capture each deployed lab's level and research support bonuses at battle start. Research payout on first successful completion of the encounter is:

    RP = 20 * sum(lab_level * (1 + analysis_bonus + observatory_bonus))

Analysis Array and Quantum Observatory each provide +25% to one adjacent lab; duplicate sources do not stack. Maximum research efficiency is 150%. No crew, combat firing-rate buff, passenger, drone, or reserve ship modifies this formula. Losing a deployed lab does not reduce that battle's earned payout. Withdrawal and failed objectives grant no RP; later success can pay once. A permanent total-fleet defeat ends the run. Research is not awarded at noncombat nodes.

Examples: lab I = 20 RP; lab III = 60; lab III with one support module = 75; lab III with both = 90; two fully supported lab III ships = 180. Extra scientific equipment therefore increases output while preserving proportionality to effective laboratory level.

| Laboratory rank | Recipe | Unlock cost | Gate |
|---|---|---:|---|
| I | CCT/CTT | Known | Start |
| II | CCT/CTT/CTT | 40 RP | Lab I |
| III | CCTT/CCTT/CTTT | 80 RP | Lab II; first boss defeated |

Ranks unlock larger recipes. Each hull must be physically refitted. Replacing a healthy smaller lab credits its intact material value. Lab rank upgrades are not additional equipment types.

Shared unlocks cost 20 RP each. Four combat families each have two mutually exclusive three-node paths costing 60, 120, and 240 RP. Buying the first node commits that family for the run; the three nodes within the selected path are sequential. Final combat nodes require the second boss. Choices across families are independent. No respec or opposite-branch salvage equipment in the first release; show the full consequences before committing.

Tourism, logistics, and science support are independent sequential paths; they do not exclude the combat families or each other. One capstone component per physical ship, including economic/science capstones. A capstone's fleet-wide buff does not stack with duplicates; shared ability cooldowns prevent copies from multiplying activations.

Baseline pacing without science support: battles 1–2 fund lab II (40); battles 3–5 fund Laser, Double Laser, and lab III (120); battle 6 funds Focusing Lens (60); battles 7–8 fund Beam Lance (120); battles 9–12 fund Stellar Lance (240). This leaves battle 13 and the Leviathan to use it. Adding Analysis Array costs one lab-III battle's income and earns an extra 15 RP per subsequent lab-III battle: a four-battle economic payback. Quantum Observatory has a longer RP payback and also supplies a major defensive combat ability; it is not compulsory research acceleration.

**8. Complete equipment catalog — 48 types**

These row numbers are documentation labels, not serialized enum values. Preserve existing equipment IDs and append new stable IDs. A slash starts a recipe row; a period is outside the footprint and may contain unrelated hull tiles. Rotation/reflection transform both footprint and material labels. Weapon facing and exhaust direction transform with the recipe. Initially preserve existing engine exhaust restrictions; do not silently remove occupied exhaust material cells from costing.

| # | Equipment | Recipe | Unlock / function |
|---:|---|---|---|
| 1 | Command Center | CT/TC | Known. Exactly one per ship; losing it destroys the ship. |
| 2 | Hull Plate | D | Known. Cheap basic protection. |
| 3 | Armor Block | DD/DD | Known. Dense durable structure; heavier than loose plate. |
| 4 | Mini Turret | O | Known. Flexible small-target weapon. |
| 5 | Thruster | OOT | Known. Basic movement. |
| 6 | Shield Generator | DDD/DTD/DDD | Known. Renewable protection with a recharge interruption. |
| 7 | Crew Quarters | CC | Known. Bounded adjacency operating-rate bonus. |
| 8 | Research Lab | CCT/CTT | Known. RP, automatic weak-point analysis, and targeted Scan ability; improved ranks above. |
| 9 | Laser | OOO | 20 RP. Reliable ranged beam; prerequisite is Mini Turret. |
| 10 | Double Laser | OOO/OOO | 20 RP after Laser. Better damage density, concentrated vulnerability. |
| 11 | Large Thruster | OOOTT/OOOTT | 20 RP after Thruster. Efficient heavy-hull propulsion. |
| 12 | Repair Station | CD/.D | 20 RP after Crew Quarters. Repairs up to two adjacent damaged components, using a finite reserve. |
| 13 | Point-Defense Turret | OD/DT | 20 RP after Mini Turret. Intercepts missiles and strike craft; weak hull damage. |
| 14 | Missile Rack | OOT/OTT | 20 RP after Mini Turret. Long-range burst; interceptable. |
| 15 | Focusing Lens | OT/TT | Optics I. Improves two adjacent beam weapons' damage/range; longer windup. |
| 16 | Beam Lance | OTO/TTT | Optics II. Charged shot through exposed components. |
| 17 | Stellar Lance | OOTOO/TTCTT/ODDDO | Optics III, capstone. Targeted piercing beam through aligned ships and organs. |
| 18 | Ion Emitter | OT/TT | Disruption I. Shield pressure; targeted interruption ability. |
| 19 | Gravitic Snare | OTO/TTT | Disruption II. Slows target movement/turning; targeted control field. |
| 20 | Singularity Projector | OOTOO/TTCTT/ODDDO | Disruption III, capstone. Pulls enemies together, then detonates. |
| 21 | Reactive Bulkhead | DCD/.DT | Bastion I. Reduces projectile hull damage to two adjacent components. |
| 22 | Shield Relay | DTD/TCT/DTD | Bastion II. Transfers a bounded amount of host shield to a nearby ally. |
| 23 | Aegis Citadel | DDDDD/DTCTD/DCCCD/DTCTD/DDDDD | Bastion III, capstone. Large finite protective field for nearby allies. |
| 24 | Repair Drone Bay | DCD/.DT | Renewal I. Interceptable drones repair allies using a finite reserve. |
| 25 | Nanoforge | DTD/TCT/DTD | Renewal II. Reconstructs one destroyed non-command component on its host, once per battle. |
| 26 | Ark Restoration Core | DDDDD/DTCTD/DCCCD/DTCTD/DDDDD | Renewal III, capstone. Emergency fleet repair and bounded reconstruction. |
| 27 | Ammunition Magazine | OC/.T | Siege I. Accelerates two adjacent projectile weapons; local destruction blast. |
| 28 | Railgun | OOOT/OCCT | Siege II. Slow, long-range armor penetration. |
| 29 | Siege Mass Driver | OOOOT/OCCCT/OTTTO | Siege III, capstone. Devastating targeted penetrating volley; host temporarily anchors. |
| 30 | Flight Deck | OC/.T | Carrier I. Interceptor squadron; finite replacement craft. |
| 31 | Torpedo Bomber Bay | OOOT/OCCT | Carrier II. Heavy strike craft, vulnerable to point defense. |
| 32 | Hive Carrier Core | OOOOT/OCCCT/OTTTO | Carrier III, capstone. Coordinated mixed strike wave with a finite sortie reserve. |
| 33 | Command Uplink | .C./TTT | Command I. Marks priority targets and coordinates nearby allies. |
| 34 | Tactical Computer | CCT/CTT/TTD | Command II. Synchronizes up to three adjacent weapons into a vulnerability-window burst. |
| 35 | Admiralty Nexus | CCTCC/CTTTC/TTDTT/CTTTC/CCTCC | Command III, capstone. Major temporary coordinated fleet offensive. |
| 36 | ECM Suite | .C./TTT | Covert I. Breaks a bounded number of missile locks and weakens enemy target coordination. |
| 37 | Phase Drive | CCT/CTT/TTD | Covert II. Short targeted reposition, with valid-space and range checks. |
| 38 | Ghost Network | CCTCC/CTTTC/TTDTT/CTTTC/CCTCC | Covert III, capstone. Conceals nearby allies briefly and creates finite decoys. |
| 39 | Passenger Cabin | CC/CD | Tourism I, 20 RP after Crew Quarters. Four berths; base fare 3 credits per survivor per eligible stop. |
| 40 | Observation Deck | CTC/CDC | Tourism II, 60 RP. +1 fare for passengers in up to two adjacent cabins; must touch a hull exterior edge. |
| 41 | Luxury Suites | CCC/CTC/DDD | Tourism III, 120 RP. Four berths; base fare 4; improved durability over ordinary cabins. |
| 42 | Grand Promenade | CCCCC/CTCTC/CDDDC/CTCTC/CCCCC | Tourism IV, 240 RP after second boss; capstone. +1 fare aboard host, one emergency passenger rescue per battle, and Sanctuary ability. |
| 43 | Cargo Hold | DCC/DCC | Known. +10 percentage points to eligible material recovery. Required starting Civic Tender component. |
| 44 | Tractor Array | DTT/CTT | Logistics II, 40 RP after Cargo Hold. +15 recovery points; targeted Tether ability. |
| 45 | Sorting Refinery | DCT/CTD/TDC | Logistics III, 80 RP. +15 recovery points; choose the material preference for bonus salvage. |
| 46 | Industrial Foundry | DDCDD/CTTTC/DTOTD/CTTTC/DDCDD | Logistics IV, 160 RP after second boss; capstone. +20 recovery points; turns bonus recovery into chosen material bundles; Field Patch ability. |
| 47 | Analysis Array | CTTC/TCTT | Science support I, 60 RP after lab II. +25% output of one adjacent lab; improved two-step map intelligence. |
| 48 | Quantum Observatory | CTTTC/TCTCT/TCCTT/TCTCT/CTTTC | Science support II, 120 RP after Analysis Array and lab III; capstone. A further +25% output of one adjacent lab and Forecast ability. |

Combat family prerequisites:

| Family | Path A | Path B | Prerequisites for first nodes |
|---|---|---|---|
| Energy | Focusing Lens → Beam Lance → Stellar Lance | Ion Emitter → Gravitic Snare → Singularity Projector | Double Laser / Laser respectively |
| Survival | Reactive Bulkhead → Shield Relay → Aegis Citadel | Repair Drone Bay → Nanoforge → Ark Restoration Core | Shield Generator / Repair Station respectively |
| Force projection | Ammunition Magazine → Railgun → Siege Mass Driver | Flight Deck → Torpedo Bomber Bay → Hive Carrier Core | Missile Rack for either path |
| Fleet operations | Command Uplink → Tactical Computer → Admiralty Nexus | ECM Suite → Phase Drive → Ghost Network | Research Lab for either path |

The Lab absorbs the earlier standalone Scanner role. Focusing Lens and specific adjacency modules replace the earlier generic Reactor bonus. Do not add those two older proposal entries accidentally, which would produce a different catalog.

Research paths reuse exact recipes only across mutually exclusive branches. This catalog has 36 distinct base recipes for 48 types, plus two lab-rank recipes. Verify canonical rotation/reflection keys before shipping. Existing assembled components keep their identity when research changes. New assembly considers only unlocked recipes; previews resolve overlapping candidates before commitment. Larger loose-tile recipes get preview priority, but never consume already assembled components without explicit disassembly. Blueprints store stable component identities as well as materials and transforms.

**9. Tourism: income, contracts, and casualties**

Passengers are persistent run entities assigned to a specific cabin component. They are not inferred from cabin capacity every battle. Boarding takes place at a port. The player chooses how many passengers to accept after seeing fare and risk. Initial limits: eight paying passengers per physical ship and 24 across the deployed fleet. Dedicated Science Vessels cannot board them.

Each passenger contract covers at most three paid stops. A qualifying stop is a first victory at a combat node or a marked Scenic Survey node. A passenger must be aboard a deployed ship and alive at settlement. No fares for reserve ships, failed objectives, withdrawal, repeated nodes, or waiting. Each node pays each passenger at most once.

Fare per surviving passenger is the cabin's base rate (3 ordinary, 4 luxury), plus 1 for a qualifying adjacent Observation Deck, plus 1 if an intact Grand Promenade is aboard the host. Cap at 6. Compute amenities from the surviving layout at settlement, and show the calculation. Paid stops count individually per passenger. After three paid stops, the passenger remains aboard without further fare until disembarking; no automatic refill.

At boarding, escrow a **20-credit safety bond per passenger** from spendable credits. Return the bond when that passenger safely disembarks or is evacuated. On death, forfeit it as the casualty penalty. Do not also deduct a second 20 credits. Track escrow separately from spendable money and from earned profit. No negative-balance debt system is required.

This prevents deliberate deaths from being profitable: even the maximum lifetime fare is 3 × 6 = 18, less than the 20-credit forfeiture. Cabin and ship losses add further cost. Example: four ordinary passengers survive one victory, earn 12 credits, and keep 80 credits in escrow. If one dies on the next fight, the three survivors earn 9; the dead passenger's 20-credit bond is lost once.

Destroying a cabin kills the passengers assigned to it unless a successful evacuation or a remaining Grand Promenade rescue charge saves them. Destroying the host kills all remaining aboard. Damaged cabins do not randomly kill passengers before destruction. Passenger IDs, statuses, contract counters, escrow, and settlements persist across saves. Repairs never resurrect passengers or create replacement bookings.

Cabins provide the Evacuate tactical ability. Successful evacuation removes the selected cabin's passengers from the fleet immediately, refunds their bonds at settlement, and forfeits that stop's fares. Escape pods are abstract in the first implementation: do not add shootable passenger entities yet. Grand Promenade automatically performs one emergency rescue of all host passengers on the first otherwise-fatal passenger event per battle. Rescue creates no new passengers or fares.

Passengers can transfer or disembark at ports. Offer a clear disembark action at Last Light before the final boss. Grand Promenade's Sanctuary ability still works without passengers, so the tourism endpoint retains combat value after responsible disembarkation. Story rescues have explicit separate rewards and must not use tourist fares or bonds.

**10. Logistics: finding more material without mandatory cargo bookkeeping**

The base material inventory remains unlimited. Cargo Hold grants recovery capability, not a small inventory cap that forces players to discard routine rewards.

Recovery bonus = strongest active Cargo Hold contribution (10%) + strongest Tractor Array (15%) + strongest Sorting Refinery (15%) + strongest Industrial Foundry (20%), for a maximum of 60%. Duplicates of a component do not add contributions. Each contributing component must be deployed and operational at battle end. Capturing its identity at deployment prevents constructing it after the battle to claim that reward.

For a victory, first generate the node's fixed base eligible enemy/environment material bundle. Extra material count = floor(base_total × recovery_bonus + saved_fraction). Carry the fractional remainder forward in the run so small bundles do not lose all low-percentage bonuses. Example: 20 eligible material units with the full chain gives 12 extra units.

Only the fixed node reward bundle is eligible. Player wrecks, dismantled ships, purchased material, spawned drones, reconstructed components, and previous bonus salvage are never inputs. Do not award bonus rolls per enemy spawn or per battlefield pickup. This prevents salvage multiplication and carrier farming.

Without Refinery, distribute bonus units using the node's fixed material weights and reward seed. With Refinery, allocate half of bonus units to the selected preferred material and distribute the remainder normally. With Foundry, allocate all bonus units according to a player-selected four-material weighting preset. Changing preference does not reroll the bonus count. Selection locks at deployment; reward settlement is idempotent.

Tractor Array also offers battlefield control; Foundry also supplies emergency repair. This keeps a Civic Tender relevant in the final battle even when more construction materials no longer matter. Laboratory bonuses, logistics, and fares are independent economies, each with its own readable report.

**11. Optional active combat abilities**

Keep movement, ordinary weapons, repairs, and default targeting automatic. Add up to four equipped tactical ability types per fleet. Each slot can be set to Manual or Auto. Auto is the default for new players. Fleet formation, target priority, and withdrawal remain separate controls and do not consume tactical slots.

Use a shared **Command Energy** meter: start at 60, maximum 100, regeneration 1.5 per simulation second. It does not scale with ship count. Identical ability types share a fleet cooldown, even when several ships mount the source. The player can choose the emitting ship; otherwise choose the closest valid source. Additional sources improve coverage/redundancy, not energy or activation count. Dedicated ships use these same four slots.

| Ability/source | Initial energy / cooldown | Target and behavior |
|---|---|---|
| Scan / Lab | 15 / 12 s | Enemy ship or exposed organ; +20% damage received for 5 s. Replaces, rather than stacks with, the lab's passive +5% analysis mark. |
| Ion Pulse / Ion Emitter | 25 / 18 s | Interrupt one charging system and slow its next cycle; boss rules below. |
| Gravity Well / Gravitic Snare | 30 / 20 s | Small area slow for 5 s; maximum 40% movement reduction. |
| Stellar Shot / Stellar Lance | 50 / 24 s | Aim a line; 3 s visible windup, then penetrating damage. |
| Collapse / Singularity Projector | 50 / 28 s | Area pull, limited slow, delayed explosion. |
| Aegis / Aegis Citadel | 40 / 24 s | Protect allies near source for 6 s using a finite barrier reserve. |
| Restoration / Ark Core | 60 / once per battle | Repair 25% of each nearby ally's initial hull capacity; reconstruct at most one non-command component per target. Never resurrect a ship or passenger. |
| Siege Volley / Mass Driver | 50 / 24 s | Target ship/organ; host anchors during a 3 s firing sequence. |
| Launch Strike / Hive Core | 40 / 24 s | Designate target for a mixed strike wave; consumes finite sortie reserve. |
| Coordinated Offensive / Admiralty Nexus | 40 / 24 s | Nearby allies gain +60% firing rate against marked target for 6 s; a signature effect separate from ordinary adjacency. |
| Jam / ECM | 25 / 18 s | Break at most six eligible missile locks in a target area; beams are unaffected. |
| Phase Jump / Phase Drive | 30 / 22 s | Move host to a valid nearby point; no teleport through arena boundaries or objective restrictions. |
| Ghost Screen / Ghost Network | 45 / 28 s | Brief concealment plus finite decoys for nearby allies; area damage and scanners counter it. |
| Evacuate / passenger accommodation | 20 / 10 s | One cabin; 1.5 s preparation. If the cabin dies first and no rescue charge applies, occupants die. |
| Sanctuary / Grand Promenade | 40 / 28 s | Nearby allies take 50% less hull damage for 5 s; useful after passengers disembark. |
| Tether / Tractor Array | 20 / 16 s | Slow one small/medium enemy or weaken one marked environmental obstacle; bosses receive only reduced movement effect. |
| Field Patch / Industrial Foundry | 35 / 24 s | Repair a targeted allied component from a fixed per-battle repair reserve; never consumes or generates saleable materials. |
| Forecast / Quantum Observatory | 40 / 28 s | Nearby allies gain 40% damage reduction for 6 s. |

Abilities must support pausing and targeting. Selecting a manual target pauses by default; allow disabling that preference. Show range, area, source, cost, cooldown, and invalid-target reason. Queue one command per ability while paused; execute in stable input order on simulation resume. Spend energy and start cooldown only when a command actually executes with a valid source and target. If its source dies or target becomes invalid, cancel without spending. Cooldowns, energy, telegraphs, casts, and durations use simulation time, never wall-clock time. Log commands for deterministic replay.

Auto targeting examples: Scan the current priority target; Aegis when multiple allies face a telegraphed volley; Evacuate a cabin below 25% HP; Phase Jump away from an announced danger area; Ark when several allies are substantially damaged. Auto and Manual use identical costs and rules. Normal difficulty must be completable with Auto enabled; manual timing offers an advantage rather than being mandatory to survive scripted attacks.

Apply a maximum 60% combined ordinary damage reduction. Aegis absorption has finite capacity and cannot trigger another Aegis recursively. Redirected or prevented damage cannot create new damage events that re-trigger itself. Bosses receive half-duration control effects, and after a successful charge interruption gain 6 s of interruption resistance. Their escorts and exposed organs remain ordinary targets. Never grant blanket immunity to an entire researched path.

**12. Enemy and objective roster**

| Enemy | Role | Counterplay |
|---|---|---|
| Scout | Flanks toward exposed support | Escort positioning, turrets, interception |
| Fighter | Direct close-range pressure | Armor, sustained weapons, controlled retreat |
| Sentinel | Shields nearby allies | Focus, penetration, disruption |
| Support | Repairs or replenishes allies | Target priority, long-range fire |
| Chrysalis | Incubates a finite number of drones | Destroy early, area damage, point defense |
| Lancer | Charges a penetrating shot | Telegraphed movement response, armor, interruption |
| Spore Carrier | Finite aircraft waves | Point defense, interceptors, carrier focus |
| Null Priest | Local shield-regeneration suppression | Leave radius, armor, focus source |
| Harvester | Gains a capped buff from nearby wrecks | Early focus or displacement; no resource generation |
| Hunter | Pursues isolated or retreating ships | Escorts, decoys, protective abilities |
| Brood Guard | Intercepts attacks on a priority target | Flanking, penetration, exhaust its protection reserve |

Introduce roles separately in Act I, pair them in Act II, and combine three or four familiar roles in Act III. Every encounter specifies the objective, failure condition, enemy roles, formation, hazard, and reward. No ordinary encounter requires a single exclusive research choice.

Initial environment set: asteroid cover with visible line-of-fire effects; ion storms with announced shield-recharge suppression intervals; moving debris with marked impact areas; gravity currents that modify steering; nebula patches that shorten sensors for both sides. Implement two before expanding to five. Never make a hazard merely an invisible stat penalty. Basic automatic danger avoidance must exist before shipping avoidance-dependent hazards.

Failure/retreat policy: a surviving fleet may retry the same frozen node. Enemy state resets for that retry; player losses and expended persistent resources remain. No research, fare, victory credits, or bonus recovery until the first success. Do not grant ordinary enemy salvage on an unsuccessful attempt. Previously destroyed player material is never refunded twice. A terminal fleet defeat ends the run. This policy must be implemented before escort/interception objectives are introduced.

**13. Boss encounter specifications**

**Bastion Warden — first boss.** Two shield pylons support a slow main body. Each pylon grants 20% main-body damage reduction; destroying both creates a 6 s shield vulnerability window. Every 12 s the Warden telegraphs a frontal lance for 3 s. Players can kill pylons, sustain pressure through the reduction, interrupt the charge, or absorb/reposition. No invulnerable phase. Defeating the body wins even if a pylon survives. Introduce a weaker pylon escort encounter beforehand.

**Brood Architect — second boss.** Two hangars alternate interceptor and bomber waves every 15 s, with a fixed reserve of three waves per hangar. A repair organ restores surviving hangars but cannot resurrect destroyed ones. Every 20 s the body marks the largest allied cluster, waits 3 s, then attacks that fixed area. Destroyed hangars permanently reduce waves. Players can intercept, focus organs, spread, or burst down the body. Remaining spawned craft must be cleared or withdrawn when the body dies according to one explicit victory rule: first release ends the battle when body and currently living escorts are destroyed, with no further spawns.

**Leviathan — final boss.** One persistent encounter with three phases, not three full heals. Structural organs are targetable combat entities with shared parent identity; damage and destroyed organs persist across phases.

| Phase | Trigger | Threat | Answers |
|---|---|---|---|
| Carapace | 100–70% core HP | Two defensive organs reinforce the body; sweeping beam telegraphed 3 s in advance | Destroy organs, pierce, disrupt, spread, absorb |
| Brood | 70–35% | Two hangars release finite waves; Hunters pressure isolated support; cluster attack returns | Escort support, point defense, kill hangars, coordinated strikes |
| Exposed Core | Below 35% | Core takes +25% damage while two charging organs prepare a pulse every 24 s | Burst core, destroy/interrupt charging organs, use mitigation/recovery |

Each charging organ accounts for half of the pulse's damage. Destroying it permanently removes that contribution; interrupting it delays its contribution by 6 s for that cycle. A pulse at full strength is survivable by a reasonably healthy, protected late-game fleet and is never an unavoidable full-fleet kill. The pulse has an 8 s visible charge. Phase transitions do not heal the core or respawn organs. At 180 s, start a visible gradual enrage to prevent indefinite stalling; tune only after ordinary victory timing is established.

All branches need at least two viable answers across fleet design, automatic behavior, and optional activation. Last Light previews the mechanics. Act III ordinary battles teach sweeping beams, finite hangars, and charging organs individually before the combined final encounter.

**14. Rewards, durability, and run pacing**

Victory credits initially equal 90 + 10 × combat index, where combat index advances from 1 to 14. This reward schedule is unrelated to enemy adaptation. Elites multiply credits/material bundle by 1.4; bosses by 1.5. RP uses laboratory output without an elite multiplier. Noncombat rewards are fixed in their node definitions.

Base material bundle size starts at 12 / 18 / 24 per act. Initial weights are Defense 35%, Offense 30%, Tech 20%, Civic 15%, with visible route-specific adjustments. Deterministic rounding should preserve the intended bundle total; logistics adds its separate bonus afterward. Avoid Civic becoming a mandatory bottleneck. Ports sell all four types, and build costs can automatically purchase shortages with a preview.

Science is the long-term technology investment. Tourism yields spendable credits with casualty exposure and locked safety bonds. Logistics yields construction materials. All three require deployment space, components, and protection. Their bonuses must be reported separately so players understand their payback.

Target ordinary battle duration 45–90 s and boss duration 90–150 s at normal speed. A normal run has 14 battles plus ten noncombat/preparation stops; allow fast-forward and optional ability Auto mode. Target one major combat capstone before battle 13 for a focused baseline science fleet. Extra science can buy breadth or a second endpoint, but should not trivially complete all four chosen combat paths before the final act.

**15. Data and implementation boundaries**

Use explicit data definitions rather than adding special cases throughout UI scripts. Suggested records:

- EquipmentDefinition: stable ID, material footprint, allowed transforms, base stats, passive effects, abilities, prerequisite IDs, exclusive family/path, capstone flag, role restrictions.
- ResearchNode: ID, RP cost, prerequisites, story gate, granted recipe/rank, exclusion group.
- CampaignNode: stable node ID, act/row/proximity, type, outgoing IDs, template ID, frozen roster seed/data, rewards, objective, hazard, preview bands, completion state.
- EncounterDefinition: budget, role roster, formations, finite waves, boss organs, success/failure rules.
- AbilityDefinition and AbilityState: source rules, target schema, energy, cooldown, charges, execution behavior, auto policy, current timers.
- PassengerContract: stable passenger ID, host/cabin ID, fare class, paid-stop count, escrow, alive/evacuated/dead/disembarked state.
- RewardLedger: encounter ID, completion state, RP snapshot, base bundle, logistics snapshot/fraction, passenger settlement, committed transaction ID.
- RunState: seed, graph, research, chosen branches, fleet/reserves, dedicated slots, deployment capacity, passenger contracts, spendable credits/escrow, reward ledger, current node.

Relevant current files:

| File | Planned responsibility |
|---|---|
| scripts/game_state.gd | Run progression, research, fleet slots, node transitions, one-time settlement |
| scripts/alien_ship.gd | Data-based enemies; remove every player-fleet scaling input |
| scripts/graph_view.gd | Variable map graph, icons, previews, route highlighting |
| scripts/game_map.gd | Selected-node briefing, ports, passenger/research/economy UI |
| scripts/ship_part.gd and ship_part_pattern.gd | Stable equipment identity, recipes, effect metadata |
| scripts/build_tilemap_area.gd | Research-gated assembly, collision previews, stable assembled parts, adjacency display |
| scripts/ship.gd and fleet_ship.gd | Shared derived stats, live component effects, dedicated-loadout validation, passengers |
| scripts/builtin_ships.gd | Default Drone, Science Vessel, Civic Tender |
| scripts/battle_simulation.gd | Deterministic abilities, effects, objectives, organs, finite spawns |
| scripts/auto_battle.gd and battle_visuals.gd | Tactical controls, targeting previews, telegraphs, readable effects |
| scripts/battle_report.gd | Damage, protection, repairs, interceptions, RP, passengers, credits, salvage |
| scripts/upgrades_panel.gd | Research purchases, paths, exclusions, recipes, payoff previews |
| tests/test_battle.gd | Existing regression coverage; extend/split into focused suites as needed |

Preserve existing numeric enum identities and blueprint compatibility. Append new IDs; never renumber from the catalog table. Version new saves. Legacy designs load into the archive but remain unbuildable if their components are not researched. Store the generated run graph rather than regenerating it from current algorithms on load. Write reward transactions and run saves atomically, with a recovery backup. Do not overwrite unrelated working-tree changes; this repository already contains ongoing changes.

**16. Ordered implementation milestones and acceptance gates**

| Milestone | Deliverable | Acceptance criteria before moving on |
|---|---|---|
| M1 — Fixed encounter progression | Frozen seeded encounter data; proximity budgets; remove adaptive scaling | For the same seed/node/difficulty, fleets of 1, 4, and 10 ships produce identical enemy rosters, stats, waves, rewards, and previews. Reloading does not reroll. |
| M2 — New map and story skeleton | Three eight-row acts, typed nodes, previews, checkpoints, placeholder bosses | Validate 1,000 seeds for reachability, forward-only edges, 4/5/5 mandatory fights, ports, meaningful forks, and no mandatory elites. UI handles 2–4-node rows. |
| M3 — Foundation research and support fleet | Science/Civic slots, starter ships, lab ranks, Cargo Hold, RP, deployment capacity | Start with four ships and three distinct design families; dedicated slots reject illegal hulls. RP examples reproduce exactly, including destroyed deployed labs and zero reserve contribution. Branch/research restrictions cannot be bypassed through imports. |
| M4 — Recipes and adjacency | Crew, stable assembly, shared stat calculation, first useful research purchases | Bonuses obey contact/recipient/stack limits; losing a component removes effects. Unlocking tech cannot silently morph existing parts. All allowed transforms preserve recipe meaning. |
| M5 — Tactical abilities | Four-slot bar, Command Energy, pause targeting, Scan, Ion Pulse, Evacuate, auto policies | Commands replay deterministically. Paused/fast-forward behavior uses simulation time. Invalid commands spend nothing. Duplicate sources do not multiply cooldowns. Normal battles work with Auto. |
| M6 — Tourism and logistics | Contracts, fares, escrow, casualty settlement, full material recovery chain | Three-stop/18-credit fare cap and 20-credit forfeiture hold; death is charged once; repair does not resurrect passengers. Twenty eligible materials with full logistics yields twelve bonus units. No bonus from player wrecks or summoned units. |
| M7 — First complete act | Distinct existing enemies, two hazards, escort/interception objectives, Warden | Preview matches actual threat. First act is completable with several ordinary fleet layouts. Failure/retreat yields no repeatable rewards. Warden has multiple viable counters. |
| M8 — Full research and Act II | Four mutually exclusive combat families; all intermediate equipment; Brood Architect | Every recipe has a validated unlock path and transform signature. Opposite-branch recipes cannot coexist. Carrier reserves and repair/reconstruction are finite. |
| M9 — Act III and final endpoints | All 48 types, full support paths, capstones, Leviathan, ending | Final organs persist across phases; no full heal or mandatory exclusive counter. A capstone can be obtained and used before the final boss. Tourism/logistics/science endpoints retain a combat purpose. |
| M10 — Balance and presentation | Full-run simulations, reports, tutorial, persistence, final tuning | Comparable investments support multiple successful fleet doctrines. All economies and losses are explained. Existing regression tests pass or are deliberately updated for documented design changes. |

Each milestone should be a small sequence of reviewable changes with its own relevant tests. Use placeholder art until behavior is stable. Do not defer map/encounter determinism, research validation, or reward idempotence until the content phase.

**17. Balance validation and completion definition**

Run deterministic comparisons at equal starting resources for at least: balanced escort/science, siege, carrier, mobile disruption, tourism-heavy, logistics-heavy, and distributed research fleets. Test both Auto and Manual abilities. Vary route, enemy formations, and seeds rather than optimizing against one encounter.

Record purchase frequency; branch win rates; first capstone timing; battle length; ships lost; passenger profit/casualties; science and logistics payback; repair expenditure; unused materials; damage prevented; repair delivered; interceptions; adjacency uptime; and ability impact. No universal target win rate is assumed before establishing player skill and intended difficulty.

Required regression scenarios include zero passengers, full escrow, destroyed cabins, evacuation during a lethal volley, lost support ships, duplicated ability sources, disconnected intact modules, reconstruction of a buff source, reserve ships, imported locked blueprints, repeated failed objectives, reload during settlement, and a boss phase transition while an ability is charging.

The first meaningful playable milestone is: two Drones, a Science Vessel, and a Civic Tender can choose between clearly previewed routes, fight an encounter whose strength does not change with their fleet, earn understandable research/material rewards, and make a consequential refit. The complete release adds tourism, targeted decisions, all research paths, and the three-boss story without undermining that loop.

**18. Design references**

- Cosmoteer: layout, autonomous crew efficiency, and individually destructible modules. Borrow placement consequences without implementing individual crew pathfinding. https://cosmoteer.net/
- Backpack Battles: spatial combinations and preparation as the main decision space. Borrow readable combinations while preventing unwanted automatic recipe reassignment. https://store.steampowered.com/app/2427700/Backpack_Battles/
- Into the Breach: readable telegraphs and understandable counters. Adapt responses to automatic behaviors and optional player activation. https://store.steampowered.com/app/590380/Into_the_Breach/
- Slay the Spire 2: route legibility and planning. Mega Crit specifically discusses larger, colored map icons and map drawing; this plan's enemy-preview schema is our own design. https://megacrit.com/news/2024-11-07-neowsletter-issue-4/

The references inform the proposal; they are not evidence that these exact numbers or combinations are already balanced. Complete the implementation gates and playtesting before treating tuning values as final.
