**Leviathan Protocol — implementation handoff**

Design baseline: October 26, 2026. This document supersedes the earlier proposal. It specifies proposed behavior, not functionality already implemented. Numerical balance values are initial tuning targets. Implement the milestones in order; do not attempt the entire catalog in one change.

**1. Product decisions and scope**

- The player builds a fleet, chooses routes toward the Leviathan, researches material combinations, and fights primarily automatic battles with optional targeted abilities.
- Enemy strength depends on geographic proximity to the Leviathan, difficulty, and encounter type. It NEVER depends on player ship count, fleet strength, laboratories, passenger count, resources, or research progress.
- Keep three regular active design slots. Add one dedicated Science Vessel slot and one dedicated Civic Vessel slot. Each dedicated slot holds exactly one deployed ship. This intentionally expands the earlier three-type limit to three regular types plus two restricted support types.
- Start with two Drones, one Science Vessel, and one Civic Tender. The Drones share one regular design slot. Dedicated slots persist if their ship is lost; the ships themselves are destructible and replaceable.
- All deployed ships, including dedicated support ships, consume deployment capacity. Dedicated slots do not provide free combat power.
- Purple/Core material is **Civic**. Keep its existing serialized numeric category; change display terminology without breaking saves. Use **Foundation** for initially known technology to avoid confusing it with Civic material.
- Target 56 distinct equipment types in this proposal. Forty is a guideline, not a cap. Equipment ranks do not count as additional types; a research node can grant several components or a general concept.
- Preserve the existing component damage model. Intact disconnected equipment remains operational; destruction removes the component and its adjacency effects. Do not introduce cascading disconnection deaths in this project. Update contradictory help text.
- Ship design is free. Construction, repairs, refits, research, and deployment limits create the economic decisions.
- Research and branch commitments reset per run. Blueprints and encyclopedia knowledge persist, but cannot bypass current-run unlocks.

**2. Story premise and fixed checkpoints**

Humanity already understands the underlying technology. Research is field engineering: discovering reliable combinations of familiar materials that withstand the Leviathan's interference. This explains why the foundation is known while advanced recipes require battle observations.

The fleet is a civilian-backed expedition following a moving anomaly through failing jump lanes. Its Science Vessel interprets the signal; its Civic Tender handles supplies, paying expedition passengers, and optional rescue work. The Leviathan is an ancient autonomous ark whose corrupted preservation system is consuming settlements and assimilating ships. Its guardians are coordinated by a signal network. The expedition must break that network and reach the ark's command core.

Passenger identity and journey purpose are left to the imagination. Track aggregate occupancy and luxury, not individual contracts. At each inhabited arrival, survivors disembark and new passengers fill operational accommodation, paying upfront. Rescued civilians remain separate story objectives. Last Light follows the same arrival rules; offer a free final disembark action before departure.

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
| Scenic survey | Story observation, sensor information, or a fixed exploration reward | Explicit reward; no passenger income unless inhabited; no RP |
| Signal/event | Choose between explicit resource, repair, information, or story outcomes | Stakes before commitment; unknown story text does not hide mechanical penalties |
| Staging checkpoint | Guaranteed preparation and story delivery | Full services, next boss briefing |
| Boss | Fixed story encounter | Identity, broad phases, major telegraphs, reward/unlock |

All nodes in the current act show type, broad threat, reward tendency, and connections. Directly reachable nodes additionally show enemy role tags, a truthful contact-count range, objective, hazard, and known major abilities. Future acts show their theme and boss; reveal their route graph on entry. Exact hidden numbers must remain inside advertised bands.

The Science Vessel can improve information two steps ahead; it must not be required to understand the immediate next node. Provide route highlighting, a persistent legend, icon shapes plus colors, and enough hit area for the current small-resolution UI. Example preview: “Interception — 5–7 alien contacts — carrier / missile escorts — ion storm — destroy carrier within 75 s — Tech-rich salvage.” Asteroids have a separate density/mineral-potential preview and never inflate the alien contact band.

Every node explicitly stores whether it is inhabited and its goods grade: Basic, Uncommon, or Rare. Ports, inhabited planets, the starting anchorage, and staging checkpoints are inhabited. Other nodes are not unless labeled. Show passenger ticket estimates, cargo sale value, and the origin goods unit value before traveling. Freeze these properties with the graph.

Edges can carry a clearly previewed travel hazard or optional mining field. Safe travel is a short transition. Hazardous travel uses the battle simulation for a bounded 20–40 seconds, with movement, Scan, mining, and defensive abilities but no unannounced alien fight or RP payout. This does not add to the 14 objective battles. Offer a safe alternative at hazardous forks, never a hidden toll. Stop hazard simulation while menus or paused targeting are open.

**4. Threat scaling: proximity only**

Assign global row r from 1 through 24. Define proximity p = (r - 1) / 23. Screen position and route length do not affect p. Side-by-side nodes have identical base proximity.

Initial encounter budget:

    base_threat = 100 * 5^p
    threat = base_threat * encounter_multiplier * difficulty_multiplier

Use encounter multipliers 1.0 for standard objectives, 1.4 for elites, and 1.8 for bosses. Start with difficulty multipliers 0.8 / 1.0 / 1.25. Budget examples on Normal are roughly 100 at row 1, 293 for the first boss, 514 for the second boss, and 900 for the Leviathan. These are content-allocation units, not HP multipliers.

Each enemy definition has a threat cost that includes weapons, durability, mobility, and abilities. Encounter templates specify required roles and legal reinforcements. Spend the budget on those definitions. Introduce stronger variants as proximity increases; do not spend the whole late-game budget on hundreds of Scouts. Initial soft limits: 24 regular enemy ships, with bosses using a body plus organs and escorts; 64 total simultaneous ship/organ/craft entities including drones; asteroids have a separate 96-fragment limit. Unspent budget is acceptable within a defined template tolerance.

Waves and spawned craft are included in the encounter's total budget. Boss phases are not three independently full-budget encounters. Difficulty must not secretly modify a frozen node after preview.

Remove BOTH existing scaling mechanisms: the multiplication of fleet size in GameState.set_destination and the player_ship_count-based health/damage normalization in AlienShip.create_random_fleet. A larger or more capable player fleet should genuinely make the same encounter easier. This is progression, not a balancing defect.

**5. Fleet composition and support ships**

Three regular slots allow three design families with multiple physical copies. A design revision stays in its family. Extra archived designs do not deploy until assigned to a slot. Permit swapping active families at secured nodes; changing the physical ships still costs construction/refit resources. Reserve ships grant no research, tourism, logistics, auras, or deployment benefits.

Dedicated ships:

| Slot | Required equipment | Restrictions | Starting loadout |
|---|---|---|---|
| Science | One active Research Lab | Exactly one ship; maximum six Offense material tiles; no strike-craft bays or offensive capstones; no passenger berths or Cargo Hold | Command Center, lab I, Crew Quarters, Shield, Thruster, two Mini Turrets, protective plates |
| Civic | Cargo Hold or passenger accommodation | Exactly one ship; maximum six Offense material tiles; no labs, strike-craft bays, or offensive capstones | Command Center, Cargo Hold, Crew Quarters, Shield, Thruster, two Mini Turrets, protective plates |

Regular ships can carry any legally researched equipment, including labs, passengers, logistics, and mining hardware. Mining Laser, Extraction Drill, Ore Processor, Seismic Cutter, and Planetcracker Core are restricted to regular slots: there is no dedicated mining slot and neither bonus support slot can serve as a miner. Offensive capstones are Stellar Lance, Singularity Projector, Siege Mass Driver, and Hive Carrier Core; Planetcracker is also prohibited in dedicated slots. Other capstones are permitted there if hull and deployment limits allow them.

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

**7. Research economy, concepts, and branch rules**

Foundation is known at run start. Archive knowledge never authorizes construction. Validate current research in assembly, blueprint import, refit, construction, and deployment. Research nodes grant lists of recipes, ranks, abilities, and passive modifiers; equipment is not the tree's organizing unit.

Only one lab operates per hull. Snapshot operational deployed labs at battle start; reserves contribute nothing. Pay once on first objective victory:

    RP = 20 * sum(lab_level * (1 + analysis_bonus + observatory_bonus))

Analysis Array and Quantum Observatory each add 25% to one adjacent lab, strongest source only; maximum multiplier 1.5. Crew improves the lab's combat analysis rate, not RP. Destroyed deployed labs still earn their snapshotted output on victory. Failure, withdrawal, travel, mining, and noncombat stops award no RP. Lab I produces 20, lab II 40, lab III 60, and fully supported lab III 90 RP. A second regular-slot science ship can increase output but competes with combat/mining designs and deployment capacity.

Lab ranks are one equipment type: I recipe CCT/CTT is known; II CCT/CTT/CTT costs 40 RP; III CCTT/CCTT/CTTT costs 80 RP and requires boss I. Upgrading requires a physical refit, not a free hull expansion.

The following table is the complete shared research registry. Costs are tuning values. A comma in grants means one purchase unlocks all listed items. Dependencies are AND unless explicitly stated otherwise.

| Research | RP | Prerequisites | Grants |
|---|---:|---|---|
| Foundation | 0 | Start | Equipment 1–8 and 43; Scan ability |
| Applied Energy | 20 | Foundation | Laser, Double Laser |
| Field Engineering | 20 | Foundation | Large Thruster, Repair Station |
| Guided Munitions | 20 | Foundation | Point-Defense Turret, Missile Rack |
| Laboratory II | 40 | Foundation | Lab II rank |
| Laboratory III | 80 | Laboratory II, boss I | Lab III rank |
| Energy Manipulation | 40 | Applied Energy | +10% firing/recharge rate for beam and shield equipment; ordinary +30% efficiency cap applies |
| Civil Hospitality | 20 | Foundation | Passenger Cabin, Observation Deck |
| Luxury Habitation | 80 | Civil Hospitality | Luxury Suites |
| Grand Hospitality | 200 | Luxury Habitation, boss II | Grand Promenade |
| Material Handling | 40 | Foundation | Tractor Array; collection radius improvement |
| Selective Recovery | 80 | Material Handling | Sorting Refinery; choose salvage material preference |
| Industrial Integration | 160 | Selective Recovery, boss II | Industrial Foundry |
| Freight Engineering | 60 | Material Handling | Cargo Hold capacity 10 → 15; existing loads do not spontaneously grow |
| Analysis Methods | 60 | Laboratory II | Analysis Array; two-step map intelligence |
| Quantum Observation | 120 | Analysis Methods, Laboratory III, boss II | Quantum Observatory, Forecast |
| Sensor Networks | 20 | Foundation | Sensor Array, Radar Relay |
| Cloaking Theory | 80 | Sensor Networks | Cloak Generator; shared cloak rules |
| Mineral Spectroscopy | 20 | Foundation | Scan identifies ore type, quantity, and extractability |
| Basic Extraction | 40 | Mineral Spectroscopy | Mining Laser, Extraction Drill; extract Defense and Offense |
| Deep Extraction | 80 | Basic Extraction | Ore Processor, Seismic Cutter; extract Tech and Civic |
| Planetary Fracture | 200 | Deep Extraction, boss II | Planetcracker Core |

Add four independent exclusive combat families (table in section 8): each offers two three-node paths, costing 60/120/240 RP sequentially. Each node grants its matching component and listed ability. First purchase commits only that family; opposite paths lock for the run. Third nodes require boss II. Display exclusions and downstream rewards before confirmation. No respec in the first version. General research and economic paths are not exclusive.

This yields 45 purchasable research nodes plus Foundation for 56 equipment types and three lab ranks. After four family commitments, 33 purchasable nodes remain accessible. Use collapsible families and tier columns; emphasize near-term options. Depth comes from prerequisites, timing, and doctrines rather than a separate button per component.

Allow one capstone component per physical hull across all paths. Fleet auras use strongest source and cooldowns are shared by ability type. An exclusive endpoint must be powerful without becoming the only answer to a boss.

Worked baseline: battles 1–2 buy lab II (40); battles 3–5 supply 120, buying Applied Energy (20) and lab III (80) after boss I, leaving 20. Battle 6 supplies 60 and buys first combat branch node (60); battles 7–8 buy its second (120); battles 9–12 buy its endpoint (240). This leaves 20 RP and battles 13–14 to use it. Analysis Array takes four subsequent lab-III victories to repay its 60 RP cost through +15 RP/victory. Mining and trade generate materials/credits, not RP. Test broader science fleets before increasing costs.

**8. Complete equipment catalog — 56 types**

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
| 8 | Research Lab | CCT/CTT | Known; ranks in section 7. RP and automatic weak-point analysis: +5% damage against one visible alien target, refresh every 8 s, strongest source only. Scan is a general Foundation ability. |
| 9 | Laser | OOO | Applied Energy. Reliable ranged beam. |
| 10 | Double Laser | OOO/OOO | Applied Energy. Better damage density; concentrated vulnerability. |
| 11 | Large Thruster | OOOTT/OOOTT | Field Engineering. Heavy-hull propulsion. |
| 12 | Repair Station | CD/.D | Field Engineering. Repairs two adjacent components using a finite reserve. |
| 13 | Point-Defense Turret | OD/DT | Guided Munitions. Intercepts missiles/strike craft; weak hull damage. |
| 14 | Missile Rack | OOT/OTT | Guided Munitions. Long-range interceptable burst. |
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
| 39 | Passenger Cabin | CC/CD | Civil Hospitality. Four places, luxury 1. |
| 40 | Observation Deck | CTC/CDC | Civil Hospitality. +1 luxury to two adjacent accommodations; exterior edge required. |
| 41 | Luxury Suites | CCC/CTC/DDD | Luxury Habitation. Four places, luxury 2; greater durability. |
| 42 | Grand Promenade | CCCCC/CTCTC/CDDDC/CTCTC/CCCCC | Grand Hospitality; capstone. +1 host luxury, Sanctuary ability. |
| 43 | Cargo Hold | DCC/DCC | Known. Ten trade-goods capacity, upgraded to 15 by Freight Engineering. |
| 44 | Tractor Array | DTT/CTT | Material Handling. Doubles host pickup radius; Tether ability. |
| 45 | Sorting Refinery | DCT/CTD/TDC | Selective Recovery. +15 percentage points construction-material recovery; material preference. |
| 46 | Industrial Foundry | DDCDD/CTTTC/DTOTD/CTTTC/DDCDD | Industrial Integration; capstone. +25 recovery points; Field Patch ability. |
| 47 | Analysis Array | CTTC/TCTT | Analysis Methods. +25% to one adjacent lab; two-step map intelligence. |
| 48 | Quantum Observatory | CTTTC/TCTCT/TCCTT/TCTCT/CTTTC | Quantum Observation; capstone. Further +25% to one adjacent lab; Forecast ability. |
| 49 | Sensor Array | TCT/TTT | Sensor Networks. Host sight 260 → 400; radar 480 → 720. Strongest source only. |
| 50 | Radar Relay | TCT/CTC | Sensor Networks. +120 radar range for nearby allies within 240; no added visual detail. |
| 51 | Cloak Generator | TCT/CDC/TCT | Cloaking Theory. Automatic cloak after 8 s without attacking/taking damage; Scan and proximity counter it. |
| 52 | Mining Laser | OOT/DDD | Basic Extraction. Ranged rock destruction; 75% extraction. Regular slots only. |
| 53 | Extraction Drill | ODT/DDT | Basic Extraction. Close-range 100% extraction; must approach hazardous rocks. Regular slots only. |
| 54 | Ore Processor | DCD/CTC/DTD | Deep Extraction. +15 recovery points for asteroid ore; strongest source only. Regular slots only. |
| 55 | Seismic Cutter | OOTD/DTTC | Deep Extraction. Targeted rock-cluster fracture; low ship damage. Regular slots only. |
| 56 | Planetcracker Core | DDTDD/DOTOD/TCCCT/DOTOD/DDTDD | Planetary Fracture; capstone. Large controlled fracture, 100% extraction, limited rate. Regular slots only. |

Combat family prerequisites:

| Family | Path A | Path B | Prerequisites for first nodes |
|---|---|---|---|
| Energy | Focusing Lens → Beam Lance → Stellar Lance | Ion Emitter → Gravitic Snare → Singularity Projector | Double Laser / Laser respectively |
| Survival | Reactive Bulkhead → Shield Relay → Aegis Citadel | Repair Drone Bay → Nanoforge → Ark Restoration Core | Shield Generator / Repair Station respectively |
| Force projection | Ammunition Magazine → Railgun → Siege Mass Driver | Flight Deck → Torpedo Bomber Bay → Hive Carrier Core | Missile Rack for either path |
| Fleet operations | Command Uplink → Tactical Computer → Admiralty Nexus | ECM Suite → Phase Drive → Ghost Network | Research Lab for either path |

Scan comes from Foundation; Sensor Array and Radar Relay improve information coverage. The Research Lab retains an independent weak-point-analysis passive. Focusing Lens specializes energy weapons while Energy Manipulation is a general research modifier. Section 7 is authoritative for purchase costs and prerequisites; catalog rows describe components.

Research paths reuse exact recipes only across mutually exclusive branches. This catalog has 44 distinct base recipes for 56 types, plus two lab-rank recipes. Verify canonical rotation/reflection keys before shipping. Existing assembled components keep their identity when research changes. New assembly considers only unlocked recipes; previews resolve overlapping candidates before commitment. Larger loose-tile recipes get preview priority, but never consume already assembled components without explicit disassembly. Blueprints store stable component identities as well as materials and transforms.

**9. Passengers: capacity, luxury, upfront tickets, and losses**

Track occupied places per accommodation component, not individual people, destinations, contracts, or bonds. Passenger Cabin and Luxury Suites each hold four passengers. A normal cabin has luxury 1; suites have luxury 2. Observation Deck adds one luxury level to up to two orthogonally adjacent accommodation components and must touch a hull exterior edge. Grand Promenade adds one luxury level to accommodation on its host. Identical sources do not stack. Clamp final luxury to 1–3.

Initial ticket prices are 8 / 12 / 16 credits per passenger at luxury 1 / 2 / 3. Evaluate luxury when boarding; tickets are not recurring combat rewards.

At every newly reached, secured inhabited node, including the start:
1. Safely disembark surviving passengers.
2. Fill all operational accommodation on deployed ships.
3. Pay each newly boarded passenger's ticket immediately.
4. Save one arrival transaction before opening the port interface.

An intact four-place cabin pays 32 per inhabited visit; a luxury-3 four-place cabin pays 64. Uninhabited battles, scenic views, and salvage fields do not pay tickets. Reopening the UI, reloading, repairing, or refitting at the same arrival never triggers another payout. Newly built cabins wait until the next inhabited arrival. Reserves cannot board; safely offload before reserving or removing occupied accommodation. A later genuine visit would pay again, but the campaign map is forward-only.

Each passenger killed costs a fixed 20 credits immediately, exactly once. Credits CAN go negative, without interest or an automatic game over. Destroying an occupied cabin kills its occupants; destroying its host kills all remaining occupants without recounting earlier deaths. Partial damage does not kill passengers. Repaired or reconstructed cabins restore empty capacity, not passengers. Tickets are not refunded in addition to the loss fee.

Show occupied/available capacity, luxury, expected boarding income, and loss fees. Example: board four at luxury 1 for +32; lose their cabin for -80; net -48 before other income. Grand Promenade supplies Sanctuary protection, not insurance or another tourism subsystem.

Future income offsets debt. Positive-credit purchases require sufficient credits; free actions and construction using only owned materials remain possible in debt. Safe disembarkation at inhabited nodes is free and does not trigger a refund or fresh payout. Players can leave Last Light without civilians.

**10. Cargo trade, material handling, and mining**

Cargo goods and the four construction materials are different inventories. Cargo occupies holds and represents future credits. Building materials retain the existing general inventory; do not impose cargo capacity on them.

Each Cargo Hold adds 10 units, or 15 with Freight Engineering. At an inhabited arrival, automatically SELL surviving cargo at its stored origin value, THEN refill operational deployed holds for free with that node's goods. The user explicitly selected this order. Origin properties: Basic Goods = 3 credits/unit, Uncommon Goods = 6, Rare Goods = 10 initially. Values freeze when loaded; destination prices do not change them. No contracts or market simulation.

The first port loads cargo but sells nothing unless cargo was already held. Ten Basic Goods show potential value 30; delivering seven earns 21, then fills with the destination's grade. Losing cargo incurs no fee. Show “Credits: -12 | Cargo: 60 (10/10)” and explain that cargo value is not spendable yet.

Store quantity, grade, and unit value per hold. Destroying a hold loses its contents; host destruction clears only remaining contents. Partial damage loses none. Reconstruction gives empty capacity. Removing loaded holds requires safe sale/offload at an inhabited node or explicit discard elsewhere; neither operation boards passengers or refills cargo. Only the once-per-arrival transaction refills. Arrival sale and offloading share a ledger to prevent double sales. Sell/offload before reserving cargo ships.

Tractor Array increases pickup reach and unlocks Tether. Sorting Refinery adds 15 percentage points to construction-material recovery and a preference within the frozen salvage pool. Industrial Foundry adds 25 points and Field Patch. These do not change trade grade, passenger prices, or RP. Duplicate same-type modules use the strongest source; total recovery cannot exceed 100%.

Mining consumes a regular design slot, either as a hybrid or a specialist. Neither bonus support ship can fit mining hardware. Science can scan for miners; Civic can carry goods and help collection.

Basic Extraction permits Offense and Defense recovery; Deep Extraction adds Tech and Civic. Mining Laser starts at 12 rock DPS/range 300 and recovers 75%; Extraction Drill starts at 24 rock DPS/range 45 and recovers 100%. Measure tool range from the firing component to the rock surface. Other weapons recover 25% only when eligible operational mining equipment is deployed. Ore Processor adds 15 percentage points; refinery/foundry modifiers add as above, capped at 100%. Seismic Cutter damages a selected cluster with Mining Laser recovery. Planetcracker produces a larger controlled fracture at 100% recovery, bounded by finite ore. Mining tools have 25% of equivalent combat weapon DPS against ships; they must not replace every gun.

Enemy salvage has a frozen material pool equal to twice the base bundle (section 14), recovered at 50% plus refinery/foundry modifiers, capped at 100%. Thus the starting payout remains the base bundle. Tractor collects drops; construction materials need no Cargo Hold. Only original enemy hulls and budgeted reinforcements contribute salvage pools; summoned craft and player wrecks never create repeatable bonus salvage.

Every asteroid root has a finite mineral budget partitioned across children. Pay only terminal-fragment pickups, using stable cumulative rounding per root/material, never rounding every fragment upward. Snapshot eligible extraction rate and unlocked material types when the root first takes damage; later upgrades do not reroll that root. Empty or unextractable rocks yield nothing. Spectroscopy Scan reveals contents; discovery persists on fragments.

Miners automatically pursue visible, scanned, material-bearing rocks that current tech can extract. Ignore known empty rocks; collision avoidance overrides harvesting. Unknown rocks require Scan before automatic mining; allow explicit force-attack for clearing/prospecting. Ordinary combat ships ignore rocks unless ordered to attack, clearing an imminent collision, or finishing cleanup with “Destroy all neutral targets” enabled. AI cannot read unscanned contents.

**11. Optional active combat abilities**

Use a bottom battle action bar with cooldown wedges, source count, disabled reason, target preview, hotkeys, and tooltips. Pin up to six actions with overflow for the rest; do not hide an unlocked action merely because a seventh component is fitted. Scan is always available while a Command Center survives. Other actions require their researched source to remain operational. Fleet control remains available alongside the bar.

Use cooldowns and explicit limited repair/sortie reserves; do not add a shared Command Energy currency in this version. Cooldowns are fleet-shared per ability type and use simulation time. Multiple sources offer position/coverage choices, not multiplied activations. Choose the nearest valid source automatically with optional manual override. Destroying a source cancels its unfinished cast; replacing a source never resets cooldown.

Pause on target selection if enabled. Validate sight/range/target/source on commit; invalid or cancelled commands consume nothing. A committed cast consumes cooldown even if interrupted. Ordinary actions start ready; capstone actions begin with half their cooldown remaining in a new encounter, preventing instant opening deletion. Persist cooldowns through travel, retries, and saves; elapsed simulation time advances them. Refit/menu visits never reset them.

| Action / source | Initial cooldown | Target and effect |
|---|---:|---|
| Scan / Foundation | 25 s | Place radius-180 circle within 450 of a friendly Command Center; reveal area and cloaked entities for 6 s. Spectroscopy adds persistent ore identification. No damage bonus. |
| Focus Mark / Command Uplink | 20 s | Visible enemy within 500; +20% allied damage for 5 s, strongest mark only. Lab analysis does not stack with it. |
| Ion Pulse / Ion Emitter | 24 s | Visible target within 300; interrupt charge and suppress shield regeneration for 4 s. Boss interruption follows boss limits. |
| Gravity Well / Gravitic Snare | 30 s | Visible radius-100 area within 350; slow movement/turning 35% for 5 s; no boss immobilization. |
| Tether / Tractor Array | 20 s | Visible rock, pickup, or nonboss enemy within 300; slow and pull toward a chosen safe point for 3 s; preserve rock collision danger. |
| Phase Step / Phase Drive | 30 s | Move host up to 120 into explored, currently visible free space; cannot cross arena boundary or overlap entities. |
| ECM Burst / ECM Suite | 25 s | Break up to six enemy missile locks within 160; no invulnerability. |
| Sanctuary / Grand Promenade | 35 s | Allies within 180 gain 35% damage reduction for 6 s; applies normally to occupied cabins. |
| Field Patch / Industrial Foundry | 40 s | Repair nearby surviving parts for at most 15% of host aggregate max HP per cast; finite battle reserve 30%; no passengers/cargo resurrection. |
| Forecast / Quantum Observatory | 40 s | Show enemy targeting intent for 6 s; allies within 200 gain 25% damage reduction for 4 s. Does not reveal unseen ships. |
| Seismic Cut / Seismic Cutter | 30 s | Visible radius-100 rock cluster within 350; deal 60 rock damage, only 15 against ships. |
| Planetcrack / Planetcracker Core | 60 s | Visible radius-220 area within 450; deal 200 rock damage, only 50 against ships. Fragments still exist; finite ore budget remains. |

Combat endpoints add major actions: Stellar Lance (45 s, long piercing line after 2 s warning); Singularity (50 s, 3 s pull then area burst); Aegis (45 s, finite shield field for 8 s); Ark Restoration (60 s, repair 25% aggregate fleet max HP and reconstruct at most one non-command component per surviving hull); Siege Volley (45 s, heavy penetrating volley with 3 s host anchoring); Hive Sortie (45 s, finite mixed squadron); Admiralty Offensive (45 s, +30% allied operating rate for 6 s under the ordinary efficiency cap); Ghost Veil (45 s, cloak nearby allies for 6 s under normal reveal rules, at most three non-damaging decoys). Ark reserves limit total reconstruction to two components per battle. Each carrier starts with a finite, displayed craft reserve and never manufactures endless salvage.

Capstone damage should initially deliver about 6–8 seconds of an equivalent-cost conventional weapon battery's output, then be tuned against telegraphs, area coverage, and cooldown. Do not silently substitute unlimited healing or summons for missing balancing.

Every equipment effect must have a useful passive/automatic function. Provide optional Auto per ability: defensive casts at explicit HP/threat thresholds, attacks on visible valid targets, Scan on unknown visible rocks or radar uncertainty (never hidden mineral contents). Manual play improves timing; Normal must remain viable on Auto. A player can disable Auto for every action.

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

Failure/retreat policy: a surviving fleet may retry the same frozen node. Enemy state resets for that retry; player losses and expended persistent resources remain. No RP, victory credits, or enemy salvage until first success. Passenger deaths and cargo losses apply immediately. Collected asteroid ore persists even on withdrawal, with its finite field/ledger also persisted; retries cannot regenerate rocks or ore. Passenger tickets and trade occur only at secured inhabited arrivals. Previously destroyed player material is never refunded twice. A terminal fleet defeat ends the run. This policy must be implemented before escort/interception objectives are introduced.

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

Base material bundle size starts at 12 / 18 / 24 per act. Initial weights are Defense 35%, Offense 30%, Tech 20%, Civic 15%, with visible route-specific adjustments. Deterministic rounding preserves the bundle total; the finite-pool recovery formula in section 10 adds the logistics yield. Avoid Civic becoming a mandatory bottleneck. Ports sell all four types, and build costs can automatically purchase shortages with a preview.

Science buys long-term technology. Passenger accommodation pays tickets on inhabited arrivals with death penalties. Cargo pays only on delivery. Mining and recovery yield construction materials. All consume hull/deployment space and need protection; report their returns separately.

Target ordinary battle duration 45–90 s and boss duration 90–150 s at normal speed. A normal run has 14 battles plus ten noncombat/preparation stops; allow fast-forward and optional ability Auto mode. Target one major combat capstone before battle 13 for a focused baseline science fleet. Extra science can buy breadth or a second endpoint, but should not trivially complete all four chosen combat paths before the final act.

**15. Data and implementation boundaries**

Use explicit definitions and simulation-owned state. UI renders state and issues validated commands; it must not award resources or reveal hidden entities.

- EquipmentDefinition: stable ID, footprint/transforms, stats, effects, ability IDs, capstone and role flags.
- ResearchNode: cost, prerequisite IDs, story gates, exclusions, arrays of granted equipment/ranks/abilities/modifiers.
- CampaignNode/Edge: persistent ID, act/row/proximity, connections, inhabited flag, goods grade/unit value, frozen encounters/rewards, hazard and travel duration, previews, completion.
- AbilityDefinition/State: source/target rules, range/radius, cooldown, finite reserves, automatic policy, current cast.
- AccommodationState: stable component ID, capacity, occupants, current luxury; no individual passenger identity.
- CargoState: stable hold ID, capacity, quantity, origin node, grade, stored unit value.
- VisibilityState: per-team sight/radar coverage, current contacts, explored mask, last-seen timestamps, detected-cloak timers; keep full world state inaccessible to UI queries.
- AsteroidState: root/fragment IDs, mass, velocity, HP, finite ore partition, discovery, extraction snapshot, pickups already claimed.
- EnvironmentDefinition/State: region, effect, phase/timer, preview tags; use simulation time.
- TransactionLedger: arrival ID, sold quantities, refill, boarding income, casualty event IDs, encounter victory/RP snapshot, ore pickup IDs. Write amounts and resulting balances atomically.
- RunState: version, seed, saved graph, progression, research/exclusions, fleet/reserves, support slots, signed credits, construction inventory, economy states, encounter/environment persistence.

Current integration points:

| File | Responsibility |
|---|---|
| scripts/game_state.gd | Run state, transitions, idempotent arrivals/rewards, signed credits |
| scripts/alien_ship.gd | Enemy definitions; remove fleet-count scaling |
| scripts/graph_view.gd; scripts/game_map.gd | Varied graph, previews, goods/inhabited properties, ports |
| scripts/ship_part.gd; scripts/ship_part_pattern.gd | Stable identities, recipes, effect metadata |
| scripts/build_tilemap_area.gd | Unlock validation, recipe previews, adjacency |
| scripts/ship.gd; scripts/fleet_ship.gd | Shared derived stats, role restrictions, occupancy/load |
| scripts/builtin_ships.gd | Drone, Science Vessel, Civic Tender |
| scripts/battle_simulation.gd | Visibility, hazards, neutral targets, abilities, objectives, fragments |
| scripts/auto_battle.gd; scripts/battle_visuals.gd | Filtered rendering, bottom bar, telegraphs, Scan/mineral overlays |
| scripts/battle_report.gd | Separate RP, trade, tickets, losses, mining, enemy salvage |
| scripts/upgrades_panel.gd | Grouped concepts, multi-unlocks, branch consequences |
| tests/test_battle.gd | Preserve regressions; add focused suites for new state machines |

Extract focused helpers/resources from large scripts as needed; do not force every system into one file. Keep the authoritative rules callable in headless tests. Preserve numeric material/equipment IDs. Version saves; legacy archived designs load but cannot bypass unlocks. Store generated graphs and transaction results, not just seeds. Back up saves and recover interrupted transactions. Preserve unrelated working-tree changes.

**16. Ordered implementation milestones**

TODO.md owns the numbered implementation sequence and its acceptance checks. Deliver progressively:
1. Stable encounters, persistence, and outcome accounting.
2. Readable map, story checkpoints, inhabited arrivals.
3. Dedicated support ships, research, stable recipes, adjacency.
4. Passenger/cargo economy and material handling.
5. Visibility, Scan/abilities, neutral asteroids, mining and travel hazards.
6. Complete Act I vertical slice.
7. Intermediate doctrines, cloak, Act II, and capstones.
8. Full Leviathan campaign, economy/AI balancing, assets, and release validation.

Gate new research on actual working effects. Use placeholder art while systems settle. Do not expose purchases that only change a label or unlock a nonfunctional component.

**17. Balance validation and completion definition**

Compare equal-resource fleets across balanced escort/science, siege, carrier, mobile disruption, tourism, trade, mining, and distributed research. Include regular fleets with no mining, no tourism, or no manually activated abilities. Rotate seeds/routes rather than balancing against one encounter.

Record capstone timing, branch choice/win rate, battle duration, passenger net income/deaths/debt duration, delivered/lost cargo, mined materials per minute, extraction efficiency, science payback, repairs, unused materials, ability impact, adjacency uptime, visibility uptime, and collision damage to each faction. An extra scientist or miner must cost enough deployment/combat opportunity to remain a choice. Compare specialized equipment to the same investment in ordinary weapons.

Regression examples: four luxury-1 passengers board for 32; losing their cabin costs 80 even if balance goes negative; host death does not charge twice. Ten Basic Goods deliver 30, then load destination goods; three units lost means only 21 delivered and no fee. UI reopening and reload never replay arrivals. Repair never creates passengers or cargo. A mined root cannot yield more than its budget across children, retries, and reloads. Fog must not leak hidden units through targeting, tooltips, damage indicators, minimap, or AI. Cloaked threats have Foundation Scan and proximity counters.

Also test reserve ships, lost support ships, duplicate ability sources, intact disconnected modules, reconstruction of buff sources, locked blueprint imports, all exclusive recipe pairs, travel withdrawal, simulation speed, boss transitions during casts, and capstone availability before battle 13. Run automated economy/graph checks plus actual playtests; simulations alone cannot establish readability or fun.

Release requires three complete acts, all catalog effects and unlocks implemented, useful economics without a mandatory investment path, readable encounters and hazards, multiple boss counters, and safe save/load. Passing tests does not make these initial tuning values final.

**18. Design references**

- Cosmoteer: layout, autonomous crew efficiency, and individually destructible modules. Borrow placement consequences without implementing individual crew pathfinding. https://cosmoteer.net/
- Backpack Battles: spatial combinations and preparation as the main decision space. Borrow readable combinations while preventing unwanted automatic recipe reassignment. https://store.steampowered.com/app/2427700/Backpack_Battles/
- Into the Breach: readable telegraphs and understandable counters. Adapt responses to automatic behaviors and optional player activation. https://store.steampowered.com/app/590380/Into_the_Breach/
- Slay the Spire 2: route legibility and planning. Mega Crit specifically discusses larger, colored map icons and map drawing; this plan's enemy-preview schema is our own design. https://megacrit.com/news/2024-11-07-neowsletter-issue-4/

The references inform the proposal; they are not evidence that these exact numbers or combinations are already balanced. Complete the implementation gates and playtesting before treating tuning values as final.

**19. Fog of war, radar, and cloak**

Adopt Cosmoteer's documented distinction between local sight, dark unseen space, and generic radar contacts, plus Sensor Arrays extending sight. Its official Classic 0.11.0 changelog also describes dropping component targeting when sight is lost. Source: [Cosmoteer official changelog](https://cosmoteer.net/history.html). The finite radar ranges, mineral discovery, and cloaking below are this game's proposed extensions, not claims about current Cosmoteer behavior.

All ranges below use battle-world units and need one shared conversion to current scene scale. Each operational Command Center gives sight 260 and radar 480. Sensor Array changes these to 400/720. Radar Relay adds 120 radar range to allies within 240; duplicate relays do not stack. Team visibility is the union of its surviving sources. These effects work identically for enemy factions. Sources do not recursively amplify one another.

| Information state | Presentation | Permitted targeting |
|---|---|---|
| Unexplored, outside radar | Dark space; no live entity details | Move or ground-target Scan |
| Explored but currently unseen | Dim terrain memory; no live ship updates | Move; explicitly ground-target areas where an ability permits |
| Radar contact outside sight | Generic pulsing dot; no identity, HP, parts, ore, or exact loadout | Investigate or Scan; no precise weapon lock |
| In sight, not cloaked | Current hull, visible parts, HP and targeting | Normal valid attacks |
| Previously seen, now unseen | Clearly stale last-known marker, expires after 5 s | No lock or live tracking |
| Scanned area | Temporary full local visibility for 6 s | Normal targeting while revealed; ore knowledge persists afterward |

Cloak Generator activates after 8 s without firing or taking damage, concealing normal radar and visual contact outside 60-unit proximity. Weapon fire, damage, Scan, or proximity reveal a cloaked ship for 6 s; firing/damage also restart the 8 s recloak delay. A friendly cloak never hides the ship from its own UI. Scan beats cloak without requiring an exclusive branch. Ghost Veil applies these same reveal rules to nearby allies; it cannot grant uninterrupted firing invisibility.

Target locks drop when visibility is lost. A projectile already fired continues to its last known aim point or ballistic path; it must not magically track hidden live coordinates. Area effects can hit hidden units through simulation, but must not reveal identity/HP in tooltips or reports until legitimately detected. Decoys have contact/target identities but no salvage or RP.

Scan can be centered in unseen space within source range; it is deliberately useful for searching. Radar does not reveal ore. With Mineral Spectroscopy, a Scan labels rocks empty, extractable, or tech-locked, with material and estimated yield. Persistent knowledge does not grant permanent live tracking of a moving rock outside visibility. Scan every unknown visible rock is a valid Auto policy; reading its secret contents before casting is not.

Keep strategic route previews separate from tactical visibility. Fog cannot erase promised next-node threat/hazard information. Introduce normal radar in Act I, nebulae and a weak cloak enemy in Act II, and coordinated cloaked hunters in Act III only after teaching Scan. Fog masks, minimap contacts, offscreen indicators, tooltips, selection, health bars, and AI must all use the same visibility query.

**20. Asteroids and non-alien targetable entities**

Asteroids participate in the same damage/weapon-target pipeline as enemies, but carry neutral-hazard and optional-resource tags. Ordinary victory counts only the encounter's declared hostile/objective entities. An in-game “Destroy all neutral targets” checkbox, off by default and saved per run, additionally requires all living targetable neutral objects; player Auto clears them after hostile threats. Drops, decoys and summons are excluded from this implicit cleanup requirement. A mining objective can explicitly require a quota. Neutral cleanup never grants another victory/RP reward.

Initial deterministic rock classes: mass 8/4/2/1, radius 8 × sqrt(mass), HP 12 × mass. On destruction, a mass greater than 1 splits into two children of half mass; minimum-size rocks disappear into debris/pickups. Conserve mass and ore across splitting, and give children seeded separation velocities plus 0.5 s birth collision grace. Fracture is a visual explosion, not extra area damage unless a separately previewed volatile-rock tag says so.

A collision inflicts 6 × mass damage on the contacted ship component, ally or alien, and removes 25% of the rock's maximum HP. Resolve each rock/ship pair at most once per 0.75 s while overlapping; separate bodies to avoid persistent unavoidable grinding. Rock damage is based on the mass before impact, before any resulting fragmentation. Large rocks are dangerous and durable, not convenient free damage sinks. Add visible trajectories/proximity warnings and automatic avoidance before making dense fields mandatory.

Use up to 96 live rocks in addition to the ship/craft entity budget. Initial fields must contain at most 48 roots to leave fragmentation headroom. If splitting would exceed the limit, retain a pending fracture until space opens; the parent remains an inert non-colliding, non-targetable fragment container, with its mass/ore budget preserved. Do not delete mineral value or create invisible colliders. Profile heavy fields, carrier fleets, Scan, and fragmentation together.

Seed root identity, ore budget, empty/ore distribution, motion, and hazard regions with the node/edge. Once entered, persist field damage, fragment lineage, discovered contents, pickups, and consumed ore across withdrawals/retries. Enemy ships may reset for retry; asteroid resources never regenerate. Save collected construction materials and pickup ledger together. Destruction by aliens can leave recoverable fragments, but cannot duplicate resource budgets.

Initial fields should contain 40–60% empty roots, clearly described as a tuning target. Scan saves mining time; do not force players to waste minutes shooting every empty rock. Give a mining field a visible optional time budget and a “continue journey” control. No infinite respawning rocks. Asteroids obscure physical shots through ordinary collision, but do not add complex line-of-sight occlusion to the first fog implementation.

**21. Passive environmental effects and encounter variety**

Start with asteroids and ion storms, then add gravity currents and nebulae. Effects operate in travel and battle through the same simulation system and affect both sides unless a preview explicitly describes an asymmetric source.

| Environment | Initial rule | Player choices and preview |
|---|---|---|
| Asteroid drift | Moving, destructible collision hazards; optional ore | Density, motion direction, mineral potential; avoid, Scan, mine, or use as physical cover |
| Ion storm | Every 15 s, telegraph 3 s then suppress shield recharge by 50% for 5 s | Visible timer/region; armor, timing, repositioning, repair |
| Gravity current | Visible vector field adds bounded drift up to 20% of base ship speed | Approach angle, thrust, formation, Phase Step; does not disable steering |
| Sensor nebula | Inside patch, sight and radar range reduced 35% for either faction; Scan circle unaffected | Scout, Scan, close engagement, alternate route |
| Volatile debris | Explicitly tagged rocks detonate in a visible radius on destruction | Keep distance, deliberate chain reaction, Tether; rare until fragment limits are tested |

Normal encounters use at most one environmental modifier initially; asteroids count as that modifier. Elites and Act III can combine two only after combined previews and avoidance work. Budget dangerous terrain as part of the node's frozen threat, not a free difficulty increase added after roster generation. Tune a template's enemy allocation downward for hazardous terrain; never inspect the player fleet to choose that adjustment.

Build level variety through objective and geometry, not only larger rosters: an open patrol, narrow drifting field, finite-wave relay defense, fleeing carrier interception, neutral convoy crossing, optional resource survey, and cloak ambush with clearly advertised contact uncertainty. Use at least three geometries per act and avoid repeating an objective on consecutive ordinary battle rows. Mandatory objective timers start when the encounter begins, pause with simulation, and are visible in briefing and battle.

Travel does not secretly add mandatory alien encounters. Environmental casualties/cargo loss are real and immediately recorded; asteroid material pickups persist. Safe edges remain available so economic fleets can choose risk. On reaching an inhabited destination, settle arrivals only after travel and any declared hostile objective are secured. A failed approach never sells cargo or boards passengers.

Implement one complete example of each system before expanding content. The first integrated route should let players preview a drift field, Scan ore, send a regular-slot miner while escorts avoid rocks, reach a port, sell surviving cargo, board passengers, and spend battle-earned RP on a grouped research node.
