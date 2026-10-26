# Leviathan development TODO

## Required sprites and assets

Audit existing assets before commissioning art. Use placeholders until mechanics pass their checks. [LEVIATHAN_DESIGN_PLAN.md](LEVIATHAN_DESIGN_PLAN.md) defines footprints, effects and initial tuning.

| Group | Required assets | Stage |
|---|---|---|
| Reuse/audit 9 existing components | Command Center, Hull Plate, Armor, Mini Turret, Thruster, Shield, Laser, Double Laser, Large Thruster. Check commandcenter, plate, armor_m, mini-turret, laser, laser_m, shield and both thruster animation assets. | Baseline |
| Foundation/general: 5 new | Crew Quarters, Research Lab (three rank footprints), Repair Station, Point-Defense Turret, Missile Rack | First act |
| Energy: 6 | Focusing Lens, Beam Lance, Stellar Lance, Ion Emitter, Gravitic Snare, Singularity Projector | Later branches |
| Survival: 6 | Reactive Bulkhead, Shield Relay, Aegis Citadel, Repair Drone Bay, Nanoforge, Ark Restoration Core | Later branches |
| Force projection: 6 | Ammunition Magazine, Railgun, Siege Mass Driver, Flight Deck, Torpedo Bomber Bay, Hive Carrier Core | Later branches |
| Fleet operations: 6 | Command Uplink, Tactical Computer, Admiralty Nexus, ECM Suite, Phase Drive, Ghost Network | Later branches |
| Passengers: 4 | Passenger Cabin, Observation Deck, Luxury Suites, Grand Promenade | Economy then endpoint |
| Logistics: 4 | Cargo Hold, Tractor Array, Sorting Refinery, Industrial Foundry | Economy then endpoint |
| Science: 2 | Analysis Array, Quantum Observatory | Research progression |
| Sensors/cloak: 3 | Sensor Array, Radar Relay, Cloak Generator | Visibility then Act II |
| Mining: 5 | Mining Laser, Extraction Drill, Ore Processor, Seismic Cutter, Planetcracker Core | Mining then endpoint |
| Component presentation | 56 icons; active/idle overlays for machinery; reusable damage/disabled overlays. Shared recipes still need distinct component artwork. | Per component |
| Asteroids | Three silhouettes in each of four sizes (12 bases); stone/ice/metal variants; four scanned material overlays, empty/locked/extractable indicators, fragments and four material pickups. Never show ore before discovery. | Mining |
| Fog/radar/cloak | Procedural fog/exploration masks, sight/radar boundaries, unknown dot, stale contact, revealed-cloak outline, transition, Scan ring/area and ore labels | Visibility |
| 20 ability icons | Scan, Focus Mark, Ion Pulse, Gravity Well, Tether, Phase Step, ECM Burst, Sanctuary, Field Patch, Forecast, Seismic Cut, Planetcrack, Stellar Lance, Singularity, Aegis, Ark Restoration, Siege Volley, Hive Sortie, Admiralty Offensive, Ghost Veil | Framework then branches |
| Ability controls/effects | Target circles/lines, cooldown wedge, Auto/Manual/disabled states, hotkeys; lance/ion/gravity/repair/shield/phase/Scan/mining/fracture effects | Per ability |
| Craft/projectiles | Interceptor, bomber, repair drone, harmless decoy, rail shot, missile, torpedo, mining beam/drill, collision/dust effects | Per family |
| Enemies | Reuse existing Scout/Fighter/Sentinel/Support/Chrysalis visuals; add Lancer, Spore Carrier, Null Priest, Harvester, Hunter, Brood Guard and readable cloak variant | By act |
| Boss parts | Warden body/pylons/lance warning; Architect body/hangars/repair organ/cluster warning; Leviathan core/body/carapace organs/hangars/charging organs, phase damage, sweep/pulse warnings. Organs need independent targeting. | One boss per act |
| Map/world | Reuse station/stars; inhabited planet, Haven, Relay Outpost, Refuge Dock, Last Light, three act backgrounds; icons for all node types, hazardous edges, mining, inhabited status, goods grades | Map then polish |
| Environment | Ion storm region/timer, gravity vectors, nebula, volatile-rock radius, drift backdrop/trajectories | Hazard systems |
| Economy/research UI | Occupancy/capacity/luxury/death, goods grades, cargo value/capacity, signed credits, research concepts/multi-grants/branch locks/story gates, four-material legend. No contract UI or passenger portraits. | Economy/research |
| Story/audio/accessibility | Short checkpoint cards/illustrations, Scan/lock/cloak/collision/mining/trade/research/boss audio cues, subtitles, reduced flashes, shape-coded warnings | Polish |

Art contract: transparent grid-aligned component sprites and pivots matching existing logical cell scale (currently 26 units; verify in step 1), correct heading/exhaust transforms, explicit frame counts/timing, and appropriate import filtering. Inspect existing art before choosing export resolution. Keep an asset manifest with stable IDs, paths, dimensions, animation states and source/licenses. Prefer procedural masks/overlays for fog and targeting. Assemble Science Vessel, Civic Tender and miners from component art; standalone ship sprites are unnecessary.

## Execution rules

This is planned work, not an implementation claim. Only documentation changes are requested now. The linked design owns behavior and tuning; do not silently simplify its rules. Work in numbered order, keep the game runnable, preserve existing changes and serialized IDs, and use isolated test saves. Record changed files and actual test results when checking off a step. Hide future research until its effects and persistence work.

Invariants: proximity-only enemy strength; three regular design families plus one restricted Science and one Civic ship; mining uses a regular slot; every deployed ship consumes capacity; disconnected intact parts operate; current-run research gates construction; no duplicate transactions; passenger deaths may cause debt; cargo sells on arrival then refills; rocks/travel award no RP.

| Gate | Steps | Result |
|---|---|---|
| A | 1–9 | Stable encounters, accounting and persistence |
| B | 10–16 | Varied readable map, story and ports |
| C | 17–27 | Support fleet, research, recipes and adjacency |
| D | 28–35 | Passengers, cargo and resource handling |
| E | 36–49 | Visibility, abilities, asteroids, mining and travel |
| F | 50–54 | Complete first act |
| G | 55–61 | Intermediate doctrines and second boss |
| H | 62–70 | Endpoints, full campaign and release validation |

## Numbered development steps

1. [x] **Establish the baseline and asset inventory.**
   Inspect project.godot, current git changes, builder scale, art and tests/test_battle.gd. Locate Godot; record headless import and test commands, including --headless --path . --script res://tests/test_battle.gd with isolated save paths.
   **Done when:** baseline failures are separated from new work, fixtures are backed up, and the manifest identifies reused/missing assets.
   **Result (2026-10-26):** See docs/BASELINE.md, docs/ASSET_MANIFEST.csv and docs/EQUIPMENT_ASSET_STATUS.csv. Added tests/run_baseline.ps1, docs/.gdignore and .gitignore for isolated local artifacts. Godot 4.7.2 import exited 0; initial battle suite passed, but runner verification exposed four intermittent controller/report failures and a follow-on script error, recorded in BASELINE.md. Certificate-store diagnostic recorded separately. Save fixtures backed up under .local/baseline/fixtures; builder scale verified at 26 units. Import also updated generated .godot caches.

   **Baseline follow-up (2026-10-26):** Fixed spent cinematic-shot cleanup in physics; stabilized the controller/UI fixture and report lookup in tests/test_battle.gd. Focused controller check and full isolated import/battle suite passed, including 600 balance encounters. Final full run: 0 failures; details/log path in docs/BASELINE.md.

2. [x] **Introduce versioned definitions.**
   Define equipment, research grants, encounters, nodes/edges, abilities, environments and goods properties. Preserve existing enum values; rename displayed purple CORE to Civic and starting technology to Foundation.
   **Done when:** old blueprints load unchanged and future definitions do not appear as purchasable content.
   **Result (2026-10-26):** Added data/definitions.json, scripts/game_definitions.gd (+UID), docs/DEFINITIONS.md, tests/test_definitions.gd (+UID) and tests/fixtures/legacy_blueprints_v1.json. Updated ship_part.gd to pin IDs 0–8 and append planned IDs, ship_part_pattern.gd to attach definition identity and gate planned content, upgrades_panel.gd to display Foundation, and tests/run_baseline.ps1 to run definition checks. Civic material labels were already present. Import, definition tests and full battle suite passed (0 failures, 600 balance encounters); logs: .local/checks/af52f3e4351f43e19dc0a15498de12c7/. No future purchases or gameplay tuning activated. Generated .godot caches also updated during import.

3. [x] **Separate run state from archive knowledge.**
   Store current research, branch choices, active design families, story flags, signed credits and seed in game_state.gd.
   **Done when:** a new run preserves archived designs but resets authorization to build researched equipment.
   **Result (2026-10-26):** Updated scripts/game_state.gd with Foundation-only run authorization, RP/branch/story metadata, seeded map generation, validated metadata snapshots/restoration, and construction/rebuild checks independent of Archive. Added scripts/run_progress_data.gd (+UID), tests/test_run_state.gd (+UID), and docs/RUN_STATE.md; updated definition/battle fixtures, runner, DEFINITIONS.md and BASELINE.md. Rejected library construction no longer occupies a family slot. Full isolated import, definition, run-state and battle suites passed with 0 failures, including 600 balance encounters; logs: .local/checks/445cb0a7d30d4ebf9204ba60d17fd634/. Metadata is ready for the full save/ledger format; automatic run saving and transaction recovery remain step 4. Generated .godot caches also updated during import.

4. [ ] **Build atomic transaction accounting.**
   Add unique arrival, casualty, cargo sale, victory and ore pickup IDs; commit balance/inventory changes and ledger together with backup/recovery.
   **Done when:** replaying an event or loading during a commit never duplicates a gain or loss.

5. [ ] **Remove all fleet-dependent enemy scaling.**
   Replace fleet-size multiplication in GameState.set_destination and ship-count normalization in AlienShip.create_random_fleet; audit callers.
   **Done when:** a fixed seed/node/difficulty gives identical enemies/rewards for fleets of 1, 4 and 10 ships with different equipment.

6. [ ] **Generate frozen proximity encounters.**
   Implement p=(row-1)/23 and 100*5^p with declared difficulty/encounter multipliers; budget finite waves, craft and organs. Save generated rosters, not just seeds.
   **Done when:** reload/refit never rerolls a node and late budgets purchase stronger roles rather than unlimited ships.

7. [ ] **Separate targeting from victory membership.**
   Add faction/entity tags for combatants, neutrals, hazards, drops, decoys and summons; objectives explicitly identify required targets.
   **Done when:** neutral test rocks are attackable but do not block ordinary victory.

8. [ ] **Implement retry, withdrawal and one-time victory.**
   Reset enemies on retry but retain player losses; failures grant no RP/enemy salvage. Add persistent-field hooks for future mining.
   **Done when:** repeated failures followed by success pay once and preserve losses across save/load.

9. [ ] **Make simulation commands deterministic.**
   Keep UI outside authoritative battle state; add command/event IDs and snapshots for destruction, objectives and expenditures.
   **Done when:** replay results match at normal/accelerated speed. Review Gate A.

10. [ ] **Generate a varied map DAG.**
    Build three eight-row acts with 2–4-node ordinary rows, splits, merges, cross-lane edges and 4/5/5 mandatory combat rows.
    **Done when:** 1,000 seeds have no unreachable/dead-end/backward paths, missing forks/merges or mandatory elites.

11. [ ] **Add node types, ports and goods properties.**
    Label inhabited nodes and freeze goods grade/unit value. Guarantee port access on Act I row 4 and Acts II/III row 3, plus staging row 7.
    **Done when:** every route has preparation access and uninhabited nodes cannot trigger arrival income.

12. [ ] **Build truthful route previews.**
    Update graph_view.gd/game_map.gd with connections, roles, contact bands, objectives, hazards, material tendencies, inhabited status and goods value.
    **Done when:** encounters match previews, asteroid density is separate from alien contacts, and minimum-resolution UI remains readable.

13. [ ] **Create story checkpoints.**
    Add Haven, Relay Outpost, Refuge Dock, Last Light, boss briefs, corrupted-ark reveal and archived/skippable text.
    **Done when:** every legal route delivers required story without an exclusive-research key.

14. [ ] **Implement ports and arrival dispatch.**
    Secure destinations before sending one arrival event; opening the port UI is a separate action. Add safe offload/disembark service hooks.
    **Done when:** reopening/reloading services never repeats arrivals and failed approaches never settle them.

15. [ ] **Preview edge hazards.**
    Store hazard type, duration, seed and mining potential on edges, initially using placeholders.
    **Done when:** risks are visible, safe alternatives exist and no edge silently adds an alien battle or RP.

16. [ ] **Validate complete map traversal.**
    Test act reveals, ports, route highlights and checkpoint transitions with placeholder encounters.
    **Done when:** full runs contain 24 visits and 14 objective battles, with correct save/load progression. Review Gate B.

17. [ ] **Add regular and dedicated support slots.**
    Separate design families from physical copies/reserves. Science requires a lab and forbids passengers/cargo; Civic requires cargo/accommodation and forbids labs. Both restrict offensive hardware and forbid mining components.
    **Done when:** names/imports cannot bypass rules, and neither a fourth regular family nor a dedicated miner can deploy.

18. [ ] **Implement capacity and starter ships.**
    Charge 2+ceil(occupied cells/12)+lab level per hull against capacities 30/42/54. Add two Drones, Science Vessel and Civic Tender with Escort behavior in builtin_ships.gd.
    **Done when:** all starters fit, Drones share a regular family, reserves contribute nothing and replacing lost support ships costs resources.

19. [ ] **Centralize derived stats and component damage.**
    Share builder/battle mass, movement, actual hull footprint and equipment stats. Preserve disconnected intact parts.
    **Done when:** displayed and battle values agree, large hulls have larger collision footprints and disconnection regressions pass.

20. [ ] **Validate stable recipe identity and transforms.**
    Canonicalize material footprints under rotation/reflection; store assembled IDs and facing. Preview larger loose-tile matches without consuming assembled parts.
    **Done when:** all recipes/ranks validate and only the 12 opposite-branch pairs duplicate a canonical signature.

21. [ ] **Implement multi-grant research definitions.**
    Support equipment lists, ranks, concepts, abilities, prerequisites, story gates and exclusions. Populate design section 7's registry.
    **Done when:** Applied Energy grants both lasers and Energy Manipulation grants a modifier without an equipment item.

22. [ ] **Build grouped research UI.**
    Show family depth, costs, prerequisites, recipe grants, exclusions and story gates, emphasizing nearby options.
    **Done when:** a player can understand one purchase unlocking multiple items and see downstream exclusions before committing.

23. [ ] **Enforce research across all construction paths.**
    Validate assembly, imports, archive deployment, refits and construction against current-run grants.
    **Done when:** locked/opposite-branch equipment cannot be built or deployed, and research never morphs existing parts.

24. [ ] **Add labs and RP snapshots.**
    Implement three physical lab footprints/ranks, one operational lab per hull, deployed snapshots and support multiplier hooks.
    **Done when:** 20/40/60/75/90 RP examples work, reserves pay zero, destroyed deployed labs still count on victory, and failure/travel/rocks pay zero.

25. [ ] **Implement adjacency.**
    Add orthogonal component links, visible recipient selection, Crew +12% to up to three recipients, strongest same source and ordinary +30% cap.
    **Done when:** repeated touching edges do not multiply buffs, source destruction updates immediately, and lab crew never increases RP.

26. [ ] **Retune baseline combat and repair.**
    Start with Laser 3 DPS, Double Laser 7.2 DPS, shield 40/regeneration 4% after 4 seconds; make thrust mass-sensitive and unify repair/reconstruction/refunds.
    **Done when:** armor and different hull sizes remain useful and repair/dismantling cannot create materials.

27. [ ] **Enable useful shared research content.**
    Finish Applied Energy, Field Engineering, Guided Munitions and Energy Manipulation, including finite repair reserves and missile interception.
    **Done when:** starters can earn RP, buy grouped tech, refit and see a real next-battle benefit. Review Gate C.

28. [ ] **Add aggregate passengers and luxury.**
    Store per-component occupancy, four places per cabin/suite and luxury 1–3, with Observation Deck adjacency.
    **Done when:** occupancy follows stable IDs without individual contracts, bonds or destinations.

29. [ ] **Pay boarding on inhabited arrival.**
    Safely disembark survivors, fill operational deployed accommodation and pay 8/12/16 per passenger by luxury. New capacity waits until the next arrival.
    **Done when:** four normal places pay 32 once; UI reopening/refitting/reserves/uninhabited nodes never generate tickets.

30. [ ] **Implement passenger losses and debt.**
    Charge 20 per death, deduplicate cabin/host loss, and restore empty capacity on repair. Audit signed-credit serialization, UI and spending checks.
    **Done when:** +32 boarding then four cabin deaths nets -48, debt persists, and free/material-only actions remain possible.

31. [ ] **Implement cargo state.**
    Store 10-unit hold capacity, quantity, origin, grade and unit value; loss has no fee and repairs restore empty space.
    **Done when:** partial damage loses nothing, host/hold destruction cannot double-count, and cargo is separate from construction materials.

32. [ ] **Sell then refill at inhabited arrivals.**
    Sell surviving cargo at stored origin value before loading destination goods; settle atomically with passenger arrival.
    **Done when:** seven Basic Goods pay 21 then refill with destination goods, first empty arrival only loads, and reload/offload cannot sell twice.

33. [ ] **Add economy UI and loaded-refit rules.**
    Place held cargo value near signed credits; show occupancy, luxury and expected income. Safely offload/disembark or explicitly discard before removing capacity.
    **Done when:** cargo cannot be spent as credits and refits/reserve swaps cannot generate loads or erase passenger losses.

34. [ ] **Implement material handling and freight upgrades.**
    Add Tractor pickup reach, bounded enemy salvage pools, Sorting Refinery preference/+15 points and Freight Engineering capacity 10→15.
    **Done when:** pools cannot be exceeded, summons/player wrecks cannot farm bonuses, and capacity upgrades never refill existing holds.

35. [ ] **Validate the economy loop.**
    Play a short route with multiple inhabited stops, combat losses and refits; compare escorts versus equal-cost accommodation/trade capacity.
    **Done when:** income is readable, debt recoverable, and neither reloads nor port actions create free repeated payouts. Review Gate D.

36. [ ] **Implement sight, radar and filtered information.**
    Add team coverage, explored memory, generic contacts and 5-second stale markers. Share visibility queries across AI, targeting, UI, minimap and tooltips.
    **Done when:** radar exposes no identity/HP/parts and losing sight removes precise locks without leaking live coordinates.

37. [ ] **Add sensors and radar relays.**
    Implement base 260/480 ranges, Sensor Array 400/720 and bounded allied +120 radar; unlock both via Sensor Networks.
    **Done when:** source destruction updates coverage, duplicates do not stack and both factions obey identical rules.

38. [ ] **Build active ability controls.**
    Add bottom bar, six pinned actions plus overflow, targeting previews, optional pause, shared per-type cooldowns, source choice and Auto toggles.
    **Done when:** invalid commands cost nothing; cooldowns follow simulation time and persist through save/retry/refit; casts cancel on source loss.

39. [ ] **Implement Foundation Scan.**
    Reveal radius 180 within 450 for 6 seconds on a 25-second cooldown, including unseen ground targeting. Keep damage marking separate.
    **Done when:** Scan works without a lab, exposes a test cloaked contact and expires correctly.

40. [ ] **Implement representative attack/defense abilities.**
    Add Focus Mark/Ion Pulse and a test defensive field through the shared framework; production availability follows research.
    **Done when:** source/range/target checks and Auto policies use visible information, and Manual remains optional.

41. [ ] **Create moving asteroid actors.**
    Add neutral rocks with mass, HP, velocity and collision shapes using the weapon damage pipeline.
    **Done when:** either faction can damage them, manual targeting works and empty rocks never block ordinary victory.

42. [ ] **Add fragmentation and collision damage.**
    Use four mass classes, two-child splits, minimum size, birth grace, size-proportional impact damage and per-pair cooldown; enforce 96-rock limit with deferred fractures.
    **Done when:** mass is conserved, no invisible colliders appear, and overlapping rocks do not apply per-frame damage.

43. [ ] **Persist finite ore and pickups.**
    Partition root ore across children, award terminal pickups with cumulative rounding, and save field state with pickup IDs.
    **Done when:** destruction/retry/reload never increases root ore or duplicates collection, including alien-caused fractures.

44. [ ] **Add mineral spectroscopy.**
    Scan records empty/material/tech-locked contents and passes discoveries to fragments; render only legitimately known overlays.
    **Done when:** hidden minerals leak through neither art nor AI, and discovery does not grant permanent moving-rock tracking.

45. [ ] **Implement mining equipment and research.**
    Basic Extraction grants Laser/Drill and Offense/Defense access; Deep Extraction adds Processor/Cutter and Tech/Civic. Apply extraction snapshots and caps.
    **Done when:** 25/75/100% yield rules hold, finite ore is conserved and both dedicated slots reject all mining hardware.

46. [ ] **Add mining and collision-avoidance AI.**
    Miners pursue visible scanned eligible rocks, skip known empty rocks and Scan unknown visible ones; escorts prioritize aliens and avoidance.
    **Done when:** no omniscient mining occurs and short-range drilling works without constant collisions or mandatory empty-field clearing.

47. [ ] **Implement ion storms and an environment scheduler.**
    Share timed region effects across travel/battle, telegraph suppression and pause all effects with simulation.
    **Done when:** both factions receive the advertised effect, menus cause no hidden damage and hazard cost is part of frozen threat.

48. [ ] **Add currents, nebulae and travel controls.**
    Implement bounded drift, sensor reduction, movement, Scan/mining, optional field timers and continue/withdraw.
    **Done when:** steering remains possible, Scan counters nebula uncertainty and untested hazard combinations stay disabled.

49. [ ] **Activate hazardous travel end to end.**
    Connect previewed edges to 20–40-second simulation; record losses/pickups before secured destination settlement.
    **Done when:** preview→Scan→regular-slot mining→survival→cargo sale/refill→boarding works without RP or repeat ore. Review Gate E.

50. [ ] **Differentiate existing enemies.**
    Implement Scout flanking, Fighter pressure, Sentinel protection, Support repair and finite Chrysalis drones using visibility-aware behavior.
    **Done when:** previews predict roles and escorts protect support ships through positioning rather than invulnerability.

51. [ ] **Add objective/arena variety.**
    Build patrol, convoy escort, interception and finite-wave defense across open, corridor and drifting-field layouts.
    **Done when:** objectives/timers are explicit, ordinary encounters require no exclusive tech and consecutive battles avoid repeated objectives.

52. [ ] **Implement the Bastion Warden.**
    Add body/two pylons, 20% reduction each, 12-second lance cycle/3-second warning and body-kill victory; teach a weaker pylon encounter first.
    **Done when:** focus, disruption, movement and protection work, and boss victory unlocks lab III/capacity 42 once.

53. [ ] **Complete the first act.**
    Replace relevant placeholders and introduce research/adjacency, boarding/trade, Scan and optional mining with short contextual guidance.
    **Done when:** several ordinary fleets finish on Auto and the intended baseline lab progression is affordable.

54. [ ] **Review the vertical slice.**
    Run persistence, economy, visibility, ore conservation and full-act checks plus actual minimum-resolution/fast-forward playtests.
    **Done when:** no duplication, targeting leak or progression blocker remains. Review Gate F before expanding content.

55. [ ] **Implement Energy and Survival intermediates.**
    Add Lens/Lance versus Ion/Snare, and Bulkhead/Relay versus Drone Bay/Nanoforge.
    **Done when:** exclusive recipes stay unambiguous, repairs/shields are bounded and each path changes combat decisions.

56. [ ] **Implement Force-projection and Fleet-operations intermediates.**
    Add Magazine/Railgun versus Flight Deck/Bomber, and Uplink/Computer versus ECM/Phase.
    **Done when:** finite sorties, interception, magazine risk, synchronized fire and valid-space repositioning have working counters.

57. [ ] **Implement cloak and decoys.**
    Enable Cloaking Theory/Generator with 8-second activation delay, 6-second reveal and 60-unit proximity; apply rules to contacts/projectiles.
    **Done when:** Scan, firing and proximity counter cloak; enemy AI obeys the same rules; guided fire cannot follow hidden live coordinates.

58. [ ] **Finish intermediate economic/science content.**
    Enable Luxury Suites, Analysis Array, full refinery preference and support behavior while keeping endpoints gated.
    **Done when:** luxury, RP and recovery use separate caps and reports explain each return.

59. [ ] **Add Act II enemy combinations.**
    Introduce Lancer, Spore Carrier, Null Priest, Harvester, Hunter and Brood Guard incrementally, with announced cloak/nebula encounters.
    **Done when:** every role has understandable counters and improving the player fleet never alters encounter budgets.

60. [ ] **Implement the Brood Architect.**
    Add two finite hangars, repair organ without resurrection, cluster telegraphs and body-plus-living-escorts victory.
    **Done when:** destroyed hangars permanently stop their waves, no salvage loop exists and capstones/capacity 54 unlock once.

61. [ ] **Validate research pacing through Act II.**
    Test the worked RP ledger and science/tourism/trade/mining detours at equal resource investment.
    **Done when:** focused research reaches an endpoint before battle 13 without mandatory extra science ships, while extra labs cost combat opportunity. Review Gate G.

62. [ ] **Implement eight combat endpoints.**
    Add Stellar Lance, Singularity, Aegis, Ark Restoration, Siege Mass Driver, Hive Carrier, Admiralty Nexus and Ghost Network.
    **Done when:** one capstone per hull, shared cooldowns, finite reserves and story gates hold; each endpoint is powerful with clear limits.

63. [ ] **Implement four support/mining endpoints.**
    Add Grand Promenade/Sanctuary, Industrial Foundry/Field Patch, Quantum Observatory/Forecast and Planetcracker.
    **Done when:** they retain combat value without creating people, cargo, infinite repairs or ore; mining remains regular-slot-only.

64. [ ] **Complete Act III encounters.**
    Teach sweeps, charging organs and finite hangars separately, then combine familiar roles and at most two vetted previewed hazards.
    **Done when:** proximity increases challenge without demanding one exclusive branch or manual reflexes.

65. [ ] **Implement Leviathan and ending.**
    Use 100–70/70–35/below-35% phases, persistent organs/no healing reset, 8-second pulse warning/24-second cycle, bounded interrupts and gradual 180-second enrage.
    **Done when:** multiple responses work, protected healthy fleets can survive the pulse, organ destruction persists and ending rewards/save occur once.

66. [ ] **Finish assets and accessibility.**
    Replace placeholders for all 56 types, actors, organs, map and 20 actions. Add audio, shape cues, reduced flashes and readable effects.
    **Done when:** every asset imports, equipment is recognizable at battle zoom and visuals reveal no hidden ore/cloak information.

67. [ ] **Balance economies and fleet doctrines.**
    Compare equal-investment siege, carrier, disruption, balanced, tourism, trade, mining and distributed-science fleets across routes/seeds and Auto/Manual.
    **Done when:** record section 17's metrics; no income/science path is mandatory, mining throughput is bounded, debt recoverable and capstones timely.

68. [ ] **Run persistence/exploit/compatibility regressions.**
    Cover interrupted arrivals, debt, loaded refits, casualty deduplication, reserve swaps, imports, fragments, duplicate ability sources and boss transitions.
    **Done when:** conservation/identity invariants hold, existing intended regressions pass and changed legacy behavior is documented.

69. [ ] **Profile full battles and polish usability.**
    Stress 64 ship/craft/organ entities plus 96 rocks, carriers, Scan, fog and fractures; test actual target hardware and minimum UI resolution.
    **Done when:** agreed performance targets are recorded/met, previews remain readable and navigation never stalls indefinitely.

70. [ ] **Complete release handoff.**
    Audit 56 equipment effects, all grants, 44 distinct base recipes plus two lab-rank recipes, 12 exclusive duplicate pairs, three acts and every gate. Update help/save notes.
    **Done when:** no purchasable stub remains, several doctrines complete a clean full campaign, validation results are recorded and remaining tuning issues are explicit.
