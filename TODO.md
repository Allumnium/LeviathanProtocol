**Leviathan Protocol development checklist**

This is the execution order for [LEVIATHAN_DESIGN_PLAN.md](LEVIATHAN_DESIGN_PLAN.md). That document owns the game rules, numerical starting values, equipment recipes, and story. This file breaks the work into implementable changes from the current Godot project. All tasks are initially unchecked; writing this checklist does not mean any feature has been implemented.

Work in numerical order. Each task assumes earlier tasks are complete; complete its verification before proceeding. A task can take several small changes, but leave the game runnable between changes. Use placeholder visuals until mechanics work. Register future content as unavailable until its effects, UI, persistence, and tests are implemented; never offer a research purchase that unlocks a nonfunctional item.

For each completed task, change `[ ]` to `[x]` and append a short completion note with the relevant test results. Preserve existing working-tree changes. Keep existing equipment/material numeric IDs stable. Do not silently change design rules to make a test pass; record any intentional design amendment in the design plan.

Non-negotiable invariants: enemies never adapt to player fleet size or strength; three regular design slots plus one Science and one Civic ship; all deployed ships consume capacity; only current-run research permits construction; disconnected intact equipment remains functional; rewards cannot be claimed twice; tourism, logistics, and research use separate accounting; Manual abilities are optional on Normal.

| Review gate | Tasks | Required playable result |
|---|---|---|
| A | 1–10 | Stable encounters, proximity difficulty, saved progress, safe outcome accounting |
| B | 11–18 | Varied readable map, noncombat stops, ports, and story progression |
| C | 19–32 | Starter support fleet, research, adjacency, and useful material recovery |
| D | 33–40 | Optional tactical abilities, targeting, interception, and repair |
| E | 41–46 | Tourism, logistics, and science investment loops |
| F | 47–50 | Varied missions and a complete playable first act |
| G | 51–56 | All research families, support endpoints, and the second boss |
| H | 57–63 | Full Leviathan campaign, balance, presentation, and release validation |

1. [ ] **Establish a reproducible baseline.**

   Inspect `project.godot`, the existing working-tree changes, and `tests/test_battle.gd`. Locate a compatible Godot executable and record the exact headless import/test commands. The existing test entry point is `res://tests/test_battle.gd`; invoke it with the installed Godot executable using `--headless --path . --script res://tests/test_battle.gd`. Run baseline checks against isolated test save paths, and record existing failures separately from new failures. Preserve blueprint/archive fixtures and representative battle seeds.

   **Done when:** another developer can run the same checks, baseline failures are documented, and normal startup, design, deployment, and battle return have been exercised. Do not repair unrelated features as part of this task.

2. [ ] **Stabilize identifiers and player-facing terminology.**

   In `scripts/ship_part.gd`, catalog/UI code, and serialization helpers, establish stable equipment IDs and preserve existing enum values. Keep the purple material's serialized category while displaying **Civic**. Display initially known technology as **Foundation**. Audit name-based ship identity so future slots do not rely on stripping display-name suffixes.

   **Done when:** old blueprints round-trip without changing material or equipment identity; UI no longer confuses Civic material with Foundation technology.

3. [ ] **Make equipment definitions data-driven.**

   Extend `ship_part_pattern.gd` or introduce a small equipment-definition/catalog module containing recipe, transforms, base stats, effect IDs, ability IDs, prerequisites, exclusion family, capstone flag, and role restrictions. Port the existing nine equipment definitions without changing their behavior. Reserve IDs for the design plan's complete catalog; do not expose unimplemented content.

   **Done when:** existing designs and previews still work, duplicate IDs and malformed material footprints are rejected, and behavior can be looked up by stable ID rather than display name.

4. [ ] **Introduce explicit run, node, and encounter records.**

   Add focused records for RunState, CampaignNode, EncounterDefinition, and RewardLedger, integrated through `game_state.gd`. Include run seed, node ID, act/row/proximity, outgoing edges, frozen roster/rewards, objective, completion status, and encounter-attempt ID. Start moving responsibilities into helpers rather than expanding the GameState singleton indefinitely. Keep compatibility adapters for the existing map until task 14.

   **Done when:** current travel and battles use identifiable records, and a node's encounter data can be inspected without starting combat.

5. [ ] **Add versioned run saves and recovery.**

   Serialize the generated graph and frozen encounter records, credits/materials, fleet/component health, current node, and reward ledger. Keep archive and blueprint persistence separate. Save atomically through a temporary file with a last-good backup. Add explicit migration/default handling for missing new fields and unknown versions. Initially support saves at secured nodes; preserve the pending deployment record rather than treating a pending battle as a fresh reward opportunity.

   **Done when:** a secured-node save restores the same fleet, graph, roster, rewards, and progression; malformed saves fail safely without overwriting the last good save.

6. [ ] **Separate deterministic random streams.**

   Use run-seeded streams for graph generation, encounter selection, reward composition, and combat. Remove encounter rerolls from UI inspection and deployment. Make combat seeds independent of visual effects and camera behavior. Store generated outcomes rather than regenerating old saves with a newer generator.

   **Done when:** opening map panels, changing camera options, or inspecting nodes does not change enemy/reward data for the same saved run.

7. [ ] **Implement proximity-based encounter budgets.**

   In enemy/encounter generation, calculate `p = (global_row - 1) / 23`, then `100 * 5^p * encounter_multiplier * difficulty_multiplier`. Define threat costs and role-constrained templates for the existing enemies. Include all finite waves in total budget. Use stronger variants as depth increases and enforce entity limits. Until the new graph lands, adapt old column positions to normalized proximity without feeding fleet data into the calculation.

   **Done when:** budget increases with proximity, same-depth nodes share the same base budget, and encounter/difficulty modifiers are explicit data. Budgets allocate content rather than multiplying every enemy stat indiscriminately.

8. [ ] **Remove both player-fleet scaling mechanisms.**

   Remove `base_fleet_size * player_ship_count` from `GameState.set_destination()`. Remove the player-count-dependent health and damage normalization in `AlienShip.create_random_fleet()`, including obsolete parameters and test assumptions. Deploy the already frozen encounter instead of generating it from current fleet state.

   **Done when:** a regression test compares the same node with 1, 4, and 10 player ships and gets identical enemy IDs, stats, formations, waves, rewards, and previews. More player ships can actually make that fixed encounter easier.

9. [ ] **Centralize one-time victory settlement.**

   Implement a RewardLedger transaction keyed by encounter ID. Move victory credits and eligible material bundles into a single settlement function in a reward helper used by `game_state.gd`. Remove incremental resource grants from presentation callbacks in `auto_battle.gd`; battlefield pickups may remain visual. Reserve separate settlement fields for research, logistics, and passengers. Persist completion and rewards together.

   **Done when:** calling settlement twice, reopening the report, or loading after settlement grants exactly one reward. Closing a report is not required to make a victory durable.

10. [ ] **Define failure, withdrawal, and retry behavior.**

    Route simulation outcomes through one transition path. Retrying uses the same frozen encounter with reset enemies, while player casualties and persistent costs remain. Failed objectives and withdrawal grant no RP, fares, victory credits, or enemy material bundle. Persist irreversible losses independently from victory rewards. Total fleet destruction ends the run.

    **Done when:** repeated failed attempts cannot generate rewards or refund lost material; retrying cannot reroll enemies; victory after a failed attempt pays once. **Gate A:** finish the encounter and accounting regression tests before expanding content.

11. [ ] **Generate the new three-act graph.**

    Replace `_generate_campaign_graph()` with a seeded DAG generator: three acts, eight rows each, 2–4 nodes on ordinary rows, 1–3 forward edges, branching, cross-lane connections, and merges. Converge at row 7 staging and row 8 boss. Preserve the design's combat rows: Act I 1/3/5/8; Acts II and III 1/2/4/5/8. Assign immutable global proximity rows.

    **Done when:** a path visits 24 nodes and 14 battles, and the graph visibly differs from two parallel lanes between forced convergence points.

12. [ ] **Populate node types, services, and encounter previews.**

    Assign patrol/elite content only to combat rows and ports, salvage, surveys, and events to noncombat rows. Guarantee ports on Act I row 4 and Acts II/III row 3, plus every staging checkpoint. Preserve a non-elite continuation, prohibit consecutive elites, and never hide a fight in a noncombat node. Freeze truthful contact bands, role tags, hazards, objectives, and reward tendencies. Keep escort/interception/defense templates unavailable until task 48 implements their objectives.

    **Done when:** each available node has complete playable content and briefing data, with no unsupported objective or missing service.

13. [ ] **Validate generation across many seeds.**

    Add a map validator and deterministic seed suite. Check reachability, exit reachability, forward-only edges, node/edge bounds, combat counts on every possible route, port access, forks/merges, and elite restrictions. Provide a known-valid fallback graph after bounded generation retries.

    **Done when:** at least 1,000 seeds pass, invalid fixtures fail with actionable errors, and every generated route can reach the final boss without a required exclusive technology.

14. [ ] **Render the new map and route choices.**

    Update `graph_view.gd` and map scenes for variable row widths, clear edge connections, node-type icons, completed/reachable states, and route highlighting. Show the current act graph and future act themes/boss identities. Preserve pan/zoom and adequate hit targets at the current 640×360 base resolution.

    **Done when:** dense and sparse generated maps remain readable, edge crossings cannot be mistaken for connections, and nodes are selectable without relying on color alone.

15. [ ] **Add actionable node briefings.**

    Update `game_map.gd` with selected-node details: enemy contact band, roles, objective, time/wave limits, hazard, threat, services, and reward tendency. Immediate-next-node information is available without a Science Vessel. Reserve a two-step intelligence extension for Analysis Array. Preview and deployment must read the same frozen record.

    **Done when:** the player can explain the next encounter's main challenge before deploying, and actual encounters stay inside their advertised bands.

16. [ ] **Handle noncombat visits and typed node transitions.**

    Replace assumptions that every destination starts `auto_battle.tscn`. Add explicit handlers for salvage, scenic survey, ports, events, staging, and bosses. Apply noncombat outcomes once and advance only along legal edges. Add event data with visible mechanical costs/outcomes; no hidden casualty or combat penalty. Use placeholders for story text, not for unresolved mechanics.

    **Done when:** a full map can be traversed without launching combat at service nodes, revisits cannot farm rewards, and only combat victories award research.

17. [ ] **Implement ports, refitting, and consistent material economics.**

    Update construction, repair, purchase, and salvage helpers plus fleet UI. Apply initial material prices O5/D2/T8/C6 and repair prices O1/D0.2/T3/C2. Separate repairing a surviving component from reconstructing a destroyed one at material cost. Preview shortages bought with credits. Refund surviving material only when dismantling; support material credits during healthy component replacement.

    **Done when:** repairing/reconstructing/dismantling cannot create materials or credits, and each transaction has a correct preview. Full port services work at guaranteed ports and staging checkpoints.

18. [ ] **Connect fixed story checkpoints and act gates.**

    Add Haven Anchorage, Relay Outpost, Refuge Dock, Last Light, and the three boss transitions. Deliver required story information at fixed checkpoints, archive it, and allow repeat-view skipping. Persist first-/second-boss flags used by lab/capstone research and capacity increases. Placeholder bosses may exercise transitions until their combat implementations arrive.

    **Done when:** story progression survives save/load, optional route choices cannot remove required information, and boss gates apply exactly once. **Gate B:** manually traverse a complete placeholder campaign.

19. [ ] **Add the missing starter equipment definitions.**

    Append Crew Quarters, Research Lab ranks I–III, and Cargo Hold with exact recipes from design sections 7–8. Add typed research/recovery/effect fields rather than overloading DPS or integrity. Initially register them for the forthcoming starter loadouts; do not advertise not-yet-working bonuses as implemented. Labs retain one equipment identity across ranks.

    **Done when:** components serialize, render with placeholders, occupy/cost their correct cells, and restore with the same identity and rank.

20. [ ] **Implement stable fleet families and dedicated support slots.**

    Update `game_state.gd`, `fleet_panel.gd`, `fleet_ship.gd`, and library UI. Support three regular deployed families, one Science ship, one Civic ship, and reserves. Validate Science requires a lab, Civic requires cargo or accommodation, and both obey their six-Offense-tile and equipment restrictions. Use IDs rather than names; a renamed ship must not bypass limits.

    **Done when:** dedicated roles cannot be used as unrestricted extra battleships, reserves contribute nothing to deployed effects, and losing a dedicated ship leaves a replaceable slot.

21. [ ] **Enforce deployment capacity and progression.**

    Calculate each hull's cost as `2 + ceil(occupied_tiles / 12) + active_lab_level`. Include loose tiles and both dedicated ships. Use capacity 30/42/54 across the acts. Show per-ship and fleet totals and explain rejected deployments. Count physical copies, not just design types.

    **Done when:** over-capacity fleets cannot deploy, reserve ships do not count, and adding a lab rank or new hull changes the displayed and validated totals consistently.

22. [ ] **Give support ships useful autonomous behavior.**

    Add Escort, hold formation, spread, and priority-target behavior data to deployed ships. Implement Escort in `battle_simulation.gd`: follow a chosen regular ally, remain behind the fighting line, avoid chasing distant targets, and retreat locally when threatened. Reassign an escort target if it dies. Do not make support ships untargetable.

    **Done when:** Science/Civic ships neither charge blindly into enemies nor become stuck when their escort target is destroyed. Behavior is deterministic for a saved formation and seed.

23. [ ] **Create and activate the new starter fleet.**

    Add `science_vessel()` and `civic_tender()` in `builtin_ships.gd`. Build legal protective layouts with command, crew, shield, engine, two Mini Turrets, and their required lab/cargo. Start runs with two Drones plus those two support ships, 300 credits, and existing starting materials. Validate slot assignment and capacity before finalizing startup.

    **Done when:** a new run starts with four ships in three distinct design families, both dedicated slots populated, and enough capacity to deploy. No starter uses a locked recipe.

24. [ ] **Implement research state, prices, and exclusions.**

    Add per-run RP, known Foundation recipes, lab ranks, purchased shared recipes, branch commitments, and story gates. Define the four combat forks and independent tourism/logistics/science paths. Validate prerequisite graphs and purchases in one service. Leave future nodes visible as planned/locked without accepting payment until their implementation tasks finish.

    **Done when:** purchases are atomic, invalid purchases spend nothing, opposing branches cannot both unlock, and starting a new run resets research without deleting the archive.

25. [ ] **Enforce research at every construction entry point.**

    Make `is_equipment_available()` authoritative for assembly, construction, blueprint import/load, refit, and deployment. Preserve locked legacy blueprints in the library with a reason they cannot be built. Separate encyclopedia discovery from permission. Decide explicitly how standalone sandbox design displays unavailable parts without granting campaign unlocks. Retire or migrate the old credit/material laser-upgrade purchase so it cannot remain an undocumented second progression system.

    **Done when:** imports, old saves, direct purchase calls, standalone designs, and name changes cannot bypass current-run technology or branch exclusions.

26. [ ] **Turn the existing technology display into a usable research screen.**

    Extend `upgrades_panel.gd` with RP balance, costs, prerequisites, full branch consequences, story gates, recipes, and purchase feedback. Distinguish known, affordable, unaffordable, story-locked, excluded, and unimplemented nodes. Show lab and economic upgrade output before purchase.

    **Done when:** a player can research a supported recipe, see its result in the builder immediately, and understand why every other node is unavailable.

27. [ ] **Make recipe assembly stable and deliberate.**

    Refactor `build_tilemap_area.gd` so a full reevaluation does not silently reconstruct all existing components into different recipes. Retain assembled IDs/footprints; only examine loose cells for candidates. Preview larger candidates and resolve overlaps before assembly. Require explicit disassembly before merging existing parts. Validate all rotations/reflections, including holes and engine exhaust.

    **Done when:** unlocking a new recipe cannot alter an existing ship, alternate branches can safely reuse a pattern, and adding one tile never unexpectedly consumes a completed component.

28. [ ] **Implement adjacency and its builder visualization.**

    Build a component-neighbor graph from orthogonal occupied-cell contact. Implement Crew Quarters' +12% bonus to at most three eligible recipients, stable default assignment, and player-adjustable links. Enforce strongest identical source, additive different bonuses, and +30% ordinary efficiency cap. Show links, recipients, effective stats, and cap explanations in the designer.

    **Done when:** extra shared edges do not multiply bonuses; diagonal contact grants nothing; support loops cannot amplify themselves; destruction removes a source's links immediately.

29. [ ] **Unify live statistics and retune basic combat.**

    Share derived-stat logic between `ship.gd`, `fleet_ship.gd`, previews, and combat, including damage and adjacency. Apply initial Laser/Double Laser/shield tuning, mass-sensitive mobility with diminishing returns, and sensible hull-size scaling in battle. Preserve destroyed-weapon shutdown and intact disconnected equipment behavior. Make mount positions and hit geometry agree with displayed size.

    **Done when:** designer and battle stats agree for the same healthy ship; damaged ships recalculate correctly; large engines cannot ignore mass; basic armor, turret, and shield tradeoffs are measurable.

30. [ ] **Award laboratory research from deployment snapshots.**

    Capture one active lab per deployed hull and its effective level at deployment. Award `20 * sum(level * efficiency)` on first victory via the ledger. Support future Analysis/Observatory bonuses without applying Crew Quarters to RP. Persist snapshots across report transitions and retries. An initially operational lab still contributes if destroyed during the winning battle.

    **Done when:** lab I yields 20 RP, lab III 60, reserves yield zero, withdrawal yields zero, and replaying settlement cannot duplicate RP. Lab-rank upgrades require physical refits and correct material credits.

31. [ ] **Deliver the first useful Cargo Hold effect.**

    Add eligible base material bundles and Cargo Hold's strongest-source +10% recovery contribution to victory settlement. Require the source to have deployed and remain operational at victory. Keep a saved fractional remainder. Exclude player wrecks, purchased material, summons, and bonus material itself. Add the basic material breakdown to the report.

    **Done when:** the Civic Tender visibly increases eligible recovery without introducing an inventory cap or creating repeatable salvage value from failed battles.

32. [ ] **Validate the first complete gameplay loop.**

    Play from Haven through several previewed nodes with the four starter ships. Earn RP/materials, research a supported recipe, refit, change formation, and replay a seeded comparison to demonstrate the change. Check Science/Civic losses, replacement, reserves, port access, save/load, and an unaffordable purchase.

    **Done when:** progression works end to end without debugging grants or no-op equipment. **Gate C:** fix foundational issues before adding tourism, combat abilities, or large content batches.

33. [ ] **Add deterministic effects and combat event records.**

    Introduce typed timed effects, durations, stack groups, damage categories, finite reserves, and event records in simulation helpers. Establish the damage/prevention/repair ordering and loop guards. Keep ability time in simulation ticks; rendering only observes effects. Record damage, mitigation, healing, status applications, and source component IDs for later reports.

    **Done when:** effects expire consistently at normal and fast-forward speeds, duplicate buffs obey their limits, and redirected/prevented damage cannot trigger an infinite chain.

34. [ ] **Support targetable enemy components and organs.**

    Introduce target handles for ship, component/organ, and world point. Give enemies targetable exposed systems where needed while keeping ordinary enemies simple. Define parent-body identity, target validity, health, destruction, and shared-victory behavior. Keep ally component targets compatible with existing FleetShip units.

    **Done when:** targeting an organ can destroy it independently without accidentally killing or healing its parent, and stale/dead target handles fail safely.

35. [ ] **Implement the tactical ability execution service.**

    Add ability definitions/states, a four-type fleet loadout, source selection, shared cooldowns, and Command Energy starting at 60 with cap 100 and 1.5/s regeneration. Add deterministic command ordering, source/target validation, charges, windups, and cancellation. Spend resources only on successful execution. Additional copies improve source coverage but not cooldown count or energy.

    **Done when:** duplicate sources cannot spam the same ability, invalid commands spend nothing, and a command replay produces the same simulation outcome.

36. [ ] **Build pause-and-target tactical controls.**

    Update `auto_battle.gd`, scenes, and `battle_visuals.gd` with four ability slots, costs, timers, source selection, range/area previews, valid-target feedback, and cancel input. Default manual targeting pauses; allow an explicit preference to keep time running. Queue at most one command per ability while paused and revalidate on resume.

    **Done when:** the player can select, aim, cancel, and execute abilities at every supported display size; targeting does not conflict with camera controls or accidentally consume resources.

37. [ ] **Implement Auto ability policies and telegraph responses.**

    Add per-slot Auto/Manual settings and deterministic policies using threat, damage, charge state, and target priority. Route Auto through the same execution service as Manual. Add basic automatic avoidance of marked danger areas while respecting escort/formation intent. Persist preferences and support fast-forward.

    **Done when:** ordinary battles can be played without manual clicks, automated casts obey identical costs/limits, and players can override timing without requiring a different ruleset.

38. [ ] **Ship the first active abilities.**

    Implement Lab Scan, Ion Emitter/Ion Pulse, and the shared charge-interruption behavior. Complete the first Disruption research node before exposing its purchase. Add Evacuate's validated command interface and tests with fixtures; keep it hidden from ordinary play until passenger accommodations exist. Use design section 11 costs and cooldowns.

    **Done when:** Scan replaces rather than stacks with the weaker passive mark, Ion can interrupt a charging system, destroyed sources invalidate queued casts, and Auto/Manual behavior is comparable.

39. [ ] **Implement missiles and real interception.**

    Add Missile Rack, Point-Defense Turret, projectile categories, lock state, interception targeting, and finite projectile lifetimes. Differentiate beams from interceptable shots. Retain guaranteed ordinary hits where intended rather than introducing undocumented evasion rolls. Make interceptions observable and reportable.

    **Done when:** point defense trades damage output for measurable protection, missiles can overwhelm finite interception capacity, and beams are not accidentally intercepted.

40. [ ] **Implement repair reserves and shared repair equipment.**

    Add Repair Station with bounded adjacent recipients and a finite battle reserve. Separate restoration of current HP from reconstruction of a destroyed component. Integrate Crew Quarters throughput and component-loss behavior. Add reusable reconstruction hooks but do not enable Nanoforge/Ark until their content tasks.

    **Done when:** repair cannot exceed maximum HP, create resources, heal destroyed command centers, or sustain an infinite battle without spending its finite reserve. **Gate D:** run command timing, damage, interception, and repair regressions.

41. [ ] **Add persistent passenger contracts and cabin assignments.**

    Implement Passenger Cabin and PassengerContract with stable passenger, host, and cabin IDs; alive/evacuated/dead/disembarked states; paid-stop count; and escrow. Support four cabin berths, eight paying passengers per ship, and 24 across the deployed fleet. Dedicated Science ships reject passenger accommodation. Repairs and design copies must not copy live passengers.

    **Done when:** passenger identity survives save/load and refits, capacity changes cannot silently delete or duplicate passengers, and empty cabins do not imply a free replacement population.

42. [ ] **Add booking, transfer, and disembarkation at ports.**

    Extend port UI to show available berths, fare, three-stop contract, 20-credit bond, spendable funds, and escrow separately. Let players choose booking quantity. Permit safe transfer and disembarkation at ports; return bonds once. Keep rescued story civilians separate from paying contracts.

    **Done when:** booking cannot overspend spendable credits, bonds are never displayed as profit, and changing host ships preserves the same passenger contracts.

43. [ ] **Settle fares and casualties without duplication.**

    Tie cabin/host destruction to passenger state changes. Add successful-combat and Scenic Survey fare settlement with a three-paid-stop lifetime cap and maximum six-credit fare. Charge casualties by forfeiting escrow, not by applying an extra second deduction. Persist deaths/forfeitures on failed attempts even though those attempts grant no fares.

    **Done when:** four ordinary survivors earn 12 credits; a later casualty forfeits exactly one 20-credit bond; lifetime fare is at most 18; repeated reports/reloads, retries, reserves, and repairs cannot duplicate fares or revive passengers.

44. [ ] **Complete ordinary tourism amenities and evacuation.**

    Implement Observation Deck's exterior-edge requirement and adjacency to at most two cabins, plus Luxury Suites and fare calculation from surviving amenities. Connect Evacuate to real passengers, including windup, cabin destruction race, bond return, and forfeiture of the current stop's fare. Add Auto evacuation and a clear passenger-risk display. Leave Grand Promenade for task 56.

    **Done when:** physical layout changes tourism value, losing an amenity changes the explained fare, and evacuation preserves passengers without granting the interrupted stop's income.

45. [ ] **Extend logistics through Tractor Array and Sorting Refinery.**

    Add their sequential research unlocks, +15% recovery contributions each, strongest-source limits, deployment preference capture, and material selection. With Refinery, allocate half of bonus units to the chosen material and distribute the remainder deterministically. Implement Tether using the tactical service. Leave Industrial Foundry for task 56.

    **Done when:** Cargo + Tractor + Refinery gives 40% bonus recovery, small bundles accumulate fractional carry correctly, and changing preferences cannot reroll reward quantity or process player wrecks.

46. [ ] **Add science-support equipment and deeper intelligence.**

    Implement Analysis Array, its +25% output for one adjacent lab, and two-step map intelligence. Show research output by ship, source, lab rank, and efficiency. Keep Quantum Observatory's final implementation for task 56, while validating the formula with fixtures for both supports and the 150% cap.

    **Done when:** lab III earns 75 RP with one support and 90 with both fixture supports; duplicates cannot exceed the cap; immediate-node information remains available without science equipment. **Gate E:** compare science, tourism, and logistics returns over several fixed encounters.

47. [ ] **Give existing enemies distinct roles and add the first specialists.**

    Implement Scout flanking, Fighter pressure, Sentinel protection, Support repair, and Chrysalis finite incubation. Add Lancer and Spore Carrier. Keep role selection and power within frozen budgets. Provide clear visual cues and target-priority tags, including support hunters that do not unrealistically know hidden player state.

    **Done when:** enemy names correspond to observable behavior, each has multiple counters, and different role combinations create different battles at comparable budgets.

48. [ ] **Implement escort, interception, and relay-defense objectives.**

    Add neutral convoy paths/extraction, marked-target escape timers, and finite announced defense waves. Define success/failure and cleanup explicitly. Count waves and summons in node threat. Enable their map templates only after objective handlers and reports work. Reuse task 10 retry/settlement rules.

    **Done when:** the same objective shown in the preview determines victory, failed objectives cannot farm kills/rewards, and summons cannot turn an encounter into an endless source of resources.

49. [ ] **Add the first two environmental hazards.**

    Implement asteroid cover with visible line-of-fire behavior and ion storms with announced shield-regeneration intervals. Apply environmental rules consistently to both sides. Integrate preview descriptions, telegraphs, and Auto response. Do not stack multiple ordinary-battle hazards in the initial content set.

    **Done when:** effects are visible and predictable, formation or equipment choices can respond, and no unavoidable hidden stat penalty substitutes for the advertised mechanic.

50. [ ] **Build the Bastion Warden and finish Act I.**

    Implement its two shield pylons, 20% reduction per living pylon, vulnerability window, telegraphed frontal lance, and body-death victory condition. Add a weaker preceding pylon encounter. Hook victory to lab III eligibility and capacity 42. Replace placeholder encounters/story text throughout Act I.

    **Done when:** several ordinary fleet configurations can finish Act I through different tactics; Manual abilities are optional; story/reward/gate transitions survive save/load. **Gate F:** play the whole first act before completing the remaining catalog.

51. [ ] **Complete the Optics and Disruption research paths.**

    Build Focusing Lens, Beam Lance, Stellar Lance, Gravitic Snare, and Singularity Projector around the existing Ion Emitter. Implement range/windup tradeoffs, penetration, line/area targeting, bounded slow/pull, and delayed detonation. Activate final-node purchases only behind the second-boss flag and enforce one capstone per ship. Use test fixtures to verify endpoints before the real second boss is available.

    **Done when:** each path has three sequential working nodes, reused recipes are unambiguous, and both concentrated damage and control provide viable answers without permanent boss lockdown.

52. [ ] **Complete the Bastion and Renewal research paths.**

    Implement Reactive Bulkhead, Shield Relay, Aegis Citadel, Repair Drone Bay, Nanoforge, and Ark Restoration Core. Use finite shield/repair reserves, interceptable repair drones, one-time reconstruction, and shared ability cooldowns. Recompute adjacency on reconstructed components without reapplying permanent bonuses.

    **Done when:** protection and recovery have different strengths; neither resurrects commands/passengers or creates infinite healing, material production, or recursive absorption.

53. [ ] **Complete the Siege and Carrier research paths.**

    Implement Ammunition Magazine, Railgun, Siege Mass Driver, Flight Deck, Torpedo Bomber Bay, and Hive Carrier Core. Add local magazine explosions with loop guards, anchoring during heavy volleys, craft targeting, finite sortie/replacement reserves, and entity limits. Summons do not occupy design slots and never carry labs, passengers, cargo rewards, or recursive carrier equipment.

    **Done when:** heavy guns and carriers are distinct viable investments; point defense counters strike craft; summons cannot exceed budgets or produce research/salvage loops.

54. [ ] **Complete the Command and Covert research paths.**

    Implement Command Uplink, Tactical Computer, Admiralty Nexus, ECM Suite, Phase Drive, and Ghost Network. Add target coordination, synchronized bursts, bounded lock breaking, valid-space repositioning, concealment, and finite decoys. Restore targeting correctly when concealment expires; area attacks and sensors retain counterplay.

    **Done when:** fleet coordination and deception have readable effects, duplicate auras/copies do not stack activations, and teleports cannot leave the arena or bypass objective restrictions.

55. [ ] **Build the Brood Architect and finish Act II.**

    Add alternating interceptor/bomber hangars, three waves per hangar, a repair organ that cannot resurrect destroyed hangars, and a telegraphed attack on the largest cluster. Preserve destroyed-organ effects. Require body and currently living escorts to be destroyed, with no new spawns after body death. Deliver Refuge Dock story, capacity 54, and final-combat research eligibility.

    **Done when:** interception, organ focus, spreading, and direct pressure all provide meaningful responses; the real second-boss victory unlocks endpoints without test/debug flags.

56. [ ] **Complete all three support research endpoints.**

    Implement Grand Promenade's fare bonus, one passenger rescue per battle, and Sanctuary; Industrial Foundry's final +20% recovery, selected material-weight preset, and Field Patch; Quantum Observatory's additional +25% research and Forecast. Enforce research/story prerequisites, capstone-per-hull restriction, source survival where required, and shared cooldowns. All three retain combat utility with no passengers or future purchases.

    **Done when:** the full logistics chain adds 12 units to a 20-unit eligible bundle; a fully supported lab III yields 90 RP; passenger rescue cannot create bookings; every one of the catalog's 48 equipment types now has a functional implementation. **Gate G:** audit recipes, prerequisites, and exclusions for the full catalog.

57. [ ] **Build the Leviathan's persistent three-phase encounter.**

    Add core/organ parent relationships, Carapace at 100–70%, Brood at 70–35%, and Exposed Core below 35%. Implement the sweep, finite hangars, Hunters, charging organs, 8-second pulse telegraph, interruption resistance, and eventual visible enrage. Carry organ/core damage across phases; do not heal or respawn at transitions. Complete victory, ending, and final report.

    **Done when:** destroying a charging organ removes its pulse contribution, interruptions delay it, prepared fleets can survive a full pulse, and every research family has useful responses. Test phase changes during ongoing casts and volleys.

58. [ ] **Complete Act III encounters, hazards, and story content.**

    Add Null Priest, Harvester, Hunter, and Brood Guard roles; teach the final boss's mechanics in earlier encounters. Finish moving-debris, gravity-current, and nebula hazards only after their Auto responses are reliable. Populate route variations, optional rescue/events, scenic surveys, and rewards across all acts. Add Last Light's explicit refit/disembark flow and final briefing.

    **Done when:** all 24 visited nodes have appropriate finished content, every final mechanic is introduced before the boss, and no route requires an exclusive technology or hides an unannounced mandatory fight.

59. [ ] **Make battle reports and progression costs explainable.**

    Extend `battle_report.gd` and relevant UI with damage, mitigation, healing, reconstruction, interceptions, adjacency uptime, ability usage, RP by lab, base/bonus materials, passenger fares, casualties, and escrow changes. Distinguish refunded principal from earned income. Explain lost bonuses when their source was destroyed.

    **Done when:** a player can understand why a support ship helped, why a reward changed, and what caused a loss without reading debug output or implementation details.

60. [ ] **Run full-campaign balance comparisons and adjust tuning data.**

    Add a deterministic campaign harness using legal research, purchases, refits, deployment limits, and route choices. Compare equal-investment balanced, siege, carrier, disruption, tourism, logistics, and distributed-science fleets across seeds; exercise Auto and recorded Manual commands. Measure capstone timing, battle duration, losses, resource bottlenecks, passenger profit, and economic payback. Adjust data rather than adding hidden fleet-adaptive difficulty.

    **Done when:** a focused baseline can use a major capstone before battle 13; ordinary/boss durations approach 45–90/90–150 seconds; multiple doctrines finish Normal; extra science does not trivially unlock everything; Civic is useful without being a universal bottleneck. Record results and unresolved balance limits.

61. [ ] **Finish onboarding, visuals, sound, and accessibility.**

    Replace placeholder component/ship/node/ability visuals, add clear activation/destruction/telegraph sounds, and keep dangerous effects readable at fast-forward. Update help text for Civic, intact disconnected equipment, support slots, research, passengers, and optional abilities. Add short contextual tutorials and persistent legends. Verify keyboard/mouse input, target cancellation, UI scaling, color-independent cues, and report readability.

    **Done when:** a new player can complete the first research/refit loop and understand an incoming major attack without prior knowledge of the plan; no help text describes obsolete rules.

62. [ ] **Harden saves, migration, and interrupted battles.**

    Round-trip every new system, including all 48 equipment IDs/ranks, branches, reserves, dedicated slots, passenger contracts/escrow, fractional recovery, abilities, and pending transactions. Complete mid-battle recovery using a deployment snapshot plus persisted simulation tick/command history or a complete equivalent snapshot; do not restore a fresh battle that refunds recorded casualties. Exercise shutdown during settlement and restore from backup. Revalidate legacy blueprint/archive compatibility.

    **Done when:** saves cannot reroll encounters, duplicate rewards, revive passengers, reset branch choices, or double-charge losses; interrupted runs resume a coherent state and invalid saves leave the last good backup intact.

63. [ ] **Perform release validation and close the checklist.**

    Run the complete regression suite, 1,000-seed map validation, representative full campaigns, and manual UI smoke tests. Profile the 64-entity cap, dense adjacency layouts, large recipes, carrier waves, and boss phases. Check all catalog entries against the design plan, all node types against working handlers, and all active abilities in Auto and Manual modes. Document installation/run instructions, remaining known issues, and final tuning values.

    **Done when:** the three-act campaign is playable from a clean start to the Leviathan ending, gates A–H pass, no unimplemented content is purchasable, and all completed tasks have evidence recorded. **Gate H:** only then call the complete vision implemented.

**Per-task completion note template:** `Completed: <date/change reference>. Validation: <commands, scenarios, results>. Remaining limitation: <specific issue or none>.`
