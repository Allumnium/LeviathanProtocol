# Continuous Space Expedition - Implementation Plan

Planning baseline: 2026-11-01. This file contains unfinished tasks and design contracts; completed entries and their verification history live in [COMPLETED.md](COMPLETED.md). An isolated core prototype does not mean a feature is integrated into the playable run.

This replaces the previous V1-V6/node-route backlog. The immediate target is a complete navigation conversion using existing physical ships, equipment, research, trade and autobattle. Deliver a representative mechanical slice before expanding content. The player's job is to choose destinations, manage the expedition and control time, not pilot individual ships.

The story specification is [docs/STORY_SPEC.md](docs/STORY_SPEC.md). Do not implement its plot, dialogue, act encounters, branches, bosses or endings in this work. Provide the mechanical event/location/gate hooks that a later story pass can populate. Existing campaign content is not the specification for the new story.

## Demo vertical slice status (2026-11-02)

A playable Act I demo now runs end to end; see "Demo vertical slice" in [docs/HANGAR.md](docs/HANGAR.md) and [tests/test_expedition_demo.gd](tests/test_expedition_demo.gd). Owner decisions for this slice, overriding the items below where they conflict:

- Combat uses a Dragon Warrior-style transition into the existing battle scene and returns to the expedition at the same position (instead of E11's in-world combat). E11's runtime combat codec is therefore not needed for the demo; Continue mid-battle restarts that encounter.
- Light Act I flavor from the story spec (charter briefing, alien contacts, Leviathan Protocol broadcast, Bastion Warden finale). No branches or endings.
- Missing art is a pink square and missing SFX play `dialogue_type.mp3` (see Placeholder assets in HANGAR.md).
- No scrollbars: shops offer a seeded subset of each shipyard's own stock that fits on screen; the Ships roster is ship sprites.
- No destination or routine arrival modal: local repair/refuel/shipyard and encounter-retry actions live in the existing side panels. Courses are set on the Map (Engage, GO TO or double-click) at any time, including mid-flight. This supersedes the "required onward-destination modal" preference in section 3.4.
- Game speed is retained across interruptions instead of dropping to 1x (supersedes the 1x rules in sections 3.3-3.4).

Partially delivered from the plan: authored distance/zone/arrival events with effects (E06/E07), the expedition Map overlay (E08), docked trade/refuel (E09), distance research and self-repair (E10), and combat admission/settlement keyed by event ID (E11). Still open: procedural POIs/cells, rescue/tow, refuel quotes, the expedition checkpoint format, and the E12-E14 pacing/performance work.

## Remaining UI work

The completed U1-U4 pass and its acceptance history are in [COMPLETED.md](COMPLETED.md). Preserve its implemented behavior; follow the current concise, visual-first UI policy in [AGENTS.md](AGENTS.md).

- [ ] ART DEPENDENCY: recognizable derelict/distress/anomaly/gate and remaining equipment artwork is not supplied/approved yet. Preserve full POI/equipment names, effects and the intentional pink missing-art marker; do not substitute unrelated ship/asteroid art or remove identifiers. Existing named map labels and fitted-equipment text fallbacks stay. Asset creation/approval is the only deferred content item in this UI pass.

## Fleet-command direction (owner review 2026-11-02)

The player commands fleets, not parts. Cut equipment busywork, make research feel powerful, and scale to fleets of 30-50 ships. Where this conflicts with older sections (shared stock, equipment buying/selling, drag-fitting, research-gated equipment, single-ship UI), this section wins. U1-U4 and D1-D3 are delivered apart from the approved-art dependency; continue remaining D4 work before D5. Verify each change with focused tests only.

### Development workflow

- Record actionable plans here before implementation. Move verified finished items into [COMPLETED.md](COMPLETED.md), rather than leaving checked-off entries; preserve open work and design contracts.
- Run the smallest relevant tests, with isolated saves and focused native checks for visible UI changes. Broad baselines, all-campaign runs and whole-project native acceptance require an explicit user request.
- Keep UI text concise and nonredundant. Prefer clear icons/in-world feedback; show only what players need and cannot readily infer. Preserve essential names, costs, consequences and errors. Research gets one short gameplay sentence, not duplicate effects or prerequisite explanations.

D1-D3 are delivered; task details and acceptance history are in [COMPLETED.md](COMPLETED.md). Preserve these current contracts:

- Ships are bought fully fitted; free shipyard refits replace parts without stock. Every predefined fit fills all mounts. Most equipment starts available; only Beam Lance, Bomber Bay, Tactical Computer and Lab III require research. New Run starts with Foundation only, without forced branches; Continue preserves existing progress and ownership.
- Map is home; Fleet arranges same-chassis squadrons. Stances, per-ship overrides and group refit/repair/purchase/move operations retain atomic saves and formation spacing.
- Battles/events award credits, RP, finite fleet missiles and occasional rescued ships. Preserve once-only settlement, command-capacity compensation, loaded-equipment restrictions and persistent equipment IDs.
- Current behavior and exact mechanics live in [docs/HANGAR.md](docs/HANGAR.md); older contracts below are overridden where they conflict with these owner decisions.

### D4 - Research that you can feel

- Owner clarification: research primarily changes fleet behavior, not access to ordinary equipment. Keep the implemented prismatic/splinter/pulse upgrades earned. Equipment-only prerequisite nodes still need meaningful effects in the remaining D4 work; do not present starting equipment access as a new research reward or mark branches completed to make fits legal.

- [ ] Remaining travel research: faster cruise / fewer random encounters.
- [ ] Activated combat abilities with cooldowns (build on the existing ability bar).
- [ ] Research raises the command limit as long-term fleet growth. Keep a few exclusive branch choices so runs differ.

### D5 - Scale to large fleets

- [ ] Support 20-30 fighters and 10-20 transports: raise the live battle-entity cap (currently 64 shared) and command budgets, profile 50-vs-40 battles at 5x, and cheapen distant AI if needed.
- [ ] Squadron-level battle HUD, health and reports; squadron-grouped Ships/Fleet views.

## 1. Confirmed owner decisions

1. One continuous expedition world. Flagship and escorts remain visible; travel, hazards, combat, regrouping and docking never replace the gameplay scene. Cruise reads as upward flight with scenery scrolling downward.
2. Free travel between discovered, accessible destinations. Existing beacon edges no longer constrain travel. Rerouting starts at the current physical position, including partway through a journey. Stop and Pause are different actions.
3. Header controls are Pause, Play (1x) and Fast Forward (10x) icons in a compact panel beside the existing top-row items, visible on every tab. No Clear button or destination dropdown. Older 5x/20x state remains readable by the prototype; these are not exposed in the UI. Threat detection immediately reduces speed to 1x and starts autobattle **without an automatic pause**. Important decisions and fuel exhaustion pause. Optional discoveries reduce fast-forward to 1x.
4. Management interfaces stay live. Opening Fleet, Ships, Research or Map does not pause. Threats surface immediately even while a panel is open. A player pause or unresolved decision must never be cleared by another event.
5. Keep a pannable three-act strategic map as an overlay, showing real fleet position, destinations, discoveries and route. Its act regions/layout are navigation scaffolding, not a requirement to retain old story encounters or boss progression.
6. Fleet-wide fuel is in scope. Fuel is spent by actual distance, not speed multiplier; stations sell refueling for credits. An explicit rescue/tow option prevents an unwinnable empty-tank state.
7. Ship/equipment purchases, fitting/unequipping/transfers, stock sales, chassis salvage and credit-paid repairs require docking at a shipyard. Ships/equipment remain inspectable while flying. Paid repairs remain instant. Do not add construction or a timed paid-repair queue.
8. Research progresses continuously as travel distance is covered. Combat, stopped travel and docking generate no research or campaign travel days. No offline progression.
9. Add slow, free, chassis-specific hull self-repair **whenever unpaused outside combat**, including stopped and docked time. Waiting at 20x to heal is deliberately permitted. Do not substitute travel-only healing.
10. Combat uses existing automatic AI in the same world. Strategic travel stops during engagements; surviving ships regroup and resume the retained route at 1x. Players can edit/cancel their destination during combat, but orders cannot teleport away or bypass the engagement.
11. New expedition runs may use a new save format. No migration, old-run compatibility or maintained legacy node-navigation mode is required. Do not spend effort deleting user files. Reliable atomic saves and Continue for the new game remain required.
12. Story/content expansion, ECM/Phase, new boss phases, mining/materials, designers, recipes and undefined equipment effects remain out of scope.

### Preserve the implemented physical game

Use the current executable code/catalogs rather than restoring older descriptions:

- The inspected runtime uses whole-ship hull, no component HP, and physical checkpoint version 2. Shields absorb first; hull at exactly zero is alive, below zero is destroyed. Preserve these mechanics; regeneration cannot resurrect a ship or recreate cargo.
- Preserve current flagship selection, starter fleet, budgets, bonuses, mount restrictions and exact-size matching. Keep one mandatory flagship and all-owned-ship deployment. Flagship loss remains terminal; no story-specific exception in this conversion.
- Preserve equipment UIDs, research gates, free transfers when service access permits, loaded-equipment restrictions and atomic inventory ownership. No free replacement copies.
- Preserve current lab rates and flagship research bonus. Current code allocates to focused projects and banks unfocused/overflow RP, without a fleet baseline. Change allocation timing, not the production formula.
- Preserve active weapons/support/carriers, finite allowances, source-loss behavior, supplied artwork/maps, sprite collision and surface lighting. Do not turn active equipment into decorative placeholders.
- Preserve current shared theme, Starhull, crisp rendering, shared X, direct-art fitting, display-only mount callouts, installed-drag unequip target, inline UID selling, shop modes/filters and pannable management views. No hover tooltips or UI focus cycling.
- Continue using the existing score rules where applicable. Use event receipts so rewards, damage accounting and research completion cannot duplicate. No new narrative victory bonus trigger in the prototype.

## 2. Existing code: reuse and replacement boundaries

Paths here exist at planning time. Proposed new files are identified separately in section 5.

| Surface | Current implementation | Required change |
| --- | --- | --- |
| Entry and root | [project.godot](project.godot), [scripts/main_menu.gd](scripts/main_menu.gd), [scenes/game_map.tscn](scenes/game_map.tscn) | New Run/Continue enter one expedition root; pending combat no longer routes to another scene. |
| Authoritative state | [scripts/hangar_state.gd](scripts/hangar_state.gd) | Retain GameState and physical transaction facade. Replace current-node/pending-destination travel with continuous expedition state. |
| Travel settlement | [scripts/hangar_state.gd](scripts/hangar_state.gd): `travel_to`, `settle_battle`, `set_destination` | Today departure immediately charges days and prepares/settles arrival. Replace this, not just its animation. Combat victory must no longer imply destination arrival. |
| Save application | [scripts/hangar_state.gd](scripts/hangar_state.gd): `_commit_hangar`, `_apply_hangar` | Current application recreates every ship and inventory dictionary. Routine live commits must instead reconcile stable objects by ship ID/equipment UID, without detaching combat actors. |
| Storage/validation | [scripts/atomic_run_store.gd](scripts/atomic_run_store.gd), [scripts/hangar_checkpoint.gd](scripts/hangar_checkpoint.gd), [scripts/save_validation.gd](scripts/save_validation.gd) | Reuse atomic envelope/generation semantics and generic checks; introduce an expedition payload validator rather than pretending version-2 node invariants still apply. |
| Management shell | [scripts/hangar_screen.gd](scripts/hangar_screen.gd) | Split embedding/lifecycle from reusable Fleet/Ships/Research/shop content; remove full-screen replacement and travel-time tab lockout. |
| Map | [scripts/graph_view.gd](scripts/graph_view.gd), [scripts/campaign_graph.gd](scripts/campaign_graph.gd), [scripts/campaign_content.gd](scripts/campaign_content.gd) | Reuse map geometry, input and icons; replace reachability, node-only marker and 2-3 second `start_travel` tween. Do not bind old encounter/boss rules automatically. |
| Encounter content | [scripts/encounter_generator.gd](scripts/encounter_generator.gd), [scripts/swarm_navigation.gd](scripts/swarm_navigation.gd) | Reuse combat definitions where appropriate; encounter identity moves from destination node to persistent encounter ID. Old departure-based Swarm pressure is not the new story clock. |
| Combat lifecycle | [scripts/auto_battle.gd](scripts/auto_battle.gd) | Extract HUD/audio/result orchestration; remove active-run map/battle scene changes and opaque result backdrop. Do not mount this script unchanged as a second game loop. |
| Combat simulation | [scripts/battle_simulation.gd](scripts/battle_simulation.gd) | Reuse AI, targeting, projectiles, collisions and doctrines. Separate world ticking/actor lifetime from engagement setup/completion. |
| Combat persistence | [scripts/battle_simulation.gd](scripts/battle_simulation.gd): `authoritative_snapshot` | This is explicitly diagnostic, **not** a restore format. Implement/test an actual runtime codec, including referenced actors, timers and RNG. |
| Visuals | [scripts/battle_visuals.gd](scripts/battle_visuals.gd), [scripts/fleet_ship_preview.gd](scripts/fleet_ship_preview.gd), [scripts/surface_art.gd](scripts/surface_art.gd), [scripts/ship_exhaust.gd](scripts/ship_exhaust.gd) | One live fleet renderer/camera; keep mounted art, exhaust, silhouettes, lighting and cached textures. Previews remain previews, not duplicate live fleets. |
| Formation | [scripts/hangar_formation.gd](scripts/hangar_formation.gd) | Reuse selection and atomic group-order semantics; formation orders change desired offsets, not instantaneous live positions. |
| Environment | [scripts/main_menu_starfield.gd](scripts/main_menu_starfield.gd), [scripts/node_environment.gd](scripts/node_environment.gd), [scripts/asteroid_field.gd](scripts/asteroid_field.gd), [scripts/sprite_collision.gd](scripts/sprite_collision.gd) | Extend seeded identity to spatial cells/locations, stream deterministic scenery, and run real hazards outside dedicated battles. |
| Activities/economy | [scripts/science_rules.gd](scripts/science_rules.gd), [scripts/hangar_research.gd](scripts/hangar_research.gd), [scripts/hangar_trade.gd](scripts/hangar_trade.gd), [scripts/hangar_carriers.gd](scripts/hangar_carriers.gd) | Distance-based research, genuine dock/undock trade, chassis self-repair, encounter-ID/UID carrier accounting. |
| Results | [scripts/battle_report.gd](scripts/battle_report.gd), [scripts/defeat_dialog.gd](scripts/defeat_dialog.gd), [scripts/run_score.gd](scripts/run_score.gd) | Nonblocking saved victory summary; terminal defeat still interrupts. No reward claim tied to opening a panel. |
| Validation | [tests/run_baseline.ps1](tests/run_baseline.ps1) | Select focused cases/files for each change and isolate APPDATA. Maintain expedition regression coverage; the broad runner is available only on explicit request. |

## 3. Runtime contracts

### 3.1 One owner, one simulation, one fleet

- Keep `GameState` as the autoload API for physical ownership, transactions and save coordination. It owns the expedition runtime for a loaded run; UI reads state and submits commands.
- Rework [scenes/game_map.tscn](scenes/game_map.tscn) into the persistent expedition shell, retaining this entry path to avoid an unnecessary scene rename. It owns a world view, expedition HUD and overlay host, not a second independent simulation.
- Initialize player actors once when creating/loading a run. Cruise, docking, combat and regrouping retain those actors and their stable IDs. Purchases add actors; actual destruction/salvage removes them.
- Extend `BattleSimulation` with an expedition lifecycle using the same actor registry and existing combat functions. Its existing `setup_owned` resets positions, shields, lists and RNG and rejects an empty enemy fleet: it is not a per-encounter entry method.
- Factor reusable world/actor initialization and noncombat advancement from engagement setup. Preserve the standalone setup path for focused existing battle tests; it is not a second playable navigation mode.
- One fixed-step owner advances movement, hazards, combat, activities and events. No independent `_process` repair timer, travel Tween, second combat clock or scene-owned reward logic.
- Save commits serialize authoritative runtime and physical state together. They must not reset actor velocity, shields, weapon cooldowns, active sorties, camera, route or overlay selection.
- No root/world replacement until explicit return to main menu or new-run creation. Add/remove child encounter entities and UI panels freely.

### 3.2 Coordinates, upward presentation and formation

Maintain two explicit spaces:

1. **Navigation space:** continuous 2D campaign coordinates, measured in navigation units (NU). Location positions, route segments, discovery radii and fuel use this space. These coordinates never depend on viewport size or map zoom.
2. **Local tactical space:** nearby physical actors, rocks, shots and stations in existing combat world units. Project navigation displacements with one documented scale. Use a floating local origin/rebase before large coordinates degrade precision.

Cruise direction is presented as screen-up, regardless of whether the strategic map course is east, west or returning to a visited port. Smoothly adjust the travel frame on course changes, preserving relative actor positions and scenery continuity. Do not teleport/respawn the fleet or use a fresh scrolling background per leg. Combat ships may turn/maneuver normally; "vertical scroller" is not a prohibition on combat headings.

- Camera follows the fleet with an unobscured fleet area when overlays are open. Preserve user camera offset/zoom; do not auto-fit on every commit or panel refresh.
- During combat, strategic position/route distance is held. Tactical movement does not secretly spend fuel or advance travel research. Engagement bounds are centered on the current encounter, not the old fixed origin/left-versus-right starting formation.
- Fleet formation stores desired offsets in the existing bounded formation coordinate system. Autopilot maintains/rejoins them with existing ship mobility limits. No individual piloting or automatic changes to saved formation after a loss.
- Formation editing remains an atomic group order with spacing preserved. Permit it outside combat; reject/cancel edits during an engagement. Other management inspection remains available.
- Cruise has one fleet speed draft, independent of combat thrust. Do not invent mass-based fuel or slowest-ship travel penalties in this conversion.
- Rebase all authoritative local coordinates together, including targets, projectiles, asteroid records, spawn anchors and pending event positions. Presentation-only rebasing must not change NU distance, collision results or RNG.

### 3.3 Clock and speed contract

| Clock | Advances when | Consumers |
| --- | --- | --- |
| Real/UI seconds | Rendering/UI is active | Input, panel animation, cosmetic twinkle; never rewards, healing or movement |
| Simulation seconds | Unpaused, at effective 1x/5x/20x | Tactical movement, hazards, combat, shield behavior, free self-repair outside combat |
| Campaign travel days | Actual self-propelled cruise distance is covered | Research and future explicitly travel-based event timers |

- Draft conversion: `travel_days += distance_nu / nu_per_day`. Stops, combat maneuvers, regrouping, docking alignment and towing do not generate travel days/RP.
- Pause freezes **all authoritative state**, including regeneration and hazards. UI remains usable. No wall-clock catch-up on focus regain, Continue or application restart.
- Use fixed 1/30-second simulation ticks for existing combat behavior. Multiply budget, not damage/heal/fuel formulas a second time. At 20x, process all required ticks on the reference machine; never silently discard elapsed simulation budget.
- Current `auto_battle` caps at six steps/frame and discards excess: do not reuse this policy for a nominal 20x expedition.
- Bound per-frame work and accumulated backlog. Under overload, visibly reduce achievable/effective speed rather than silently losing time, tunneling through encounters or freezing input. Coarse cruise stepping is not required for the initial version.
- Clamp movement to the earliest arrival, fuel depletion, discovery/event boundary or research completion; handle that boundary before consuming remaining budget. Sweep segments, not just endpoints. Re-evaluate speed/state after every tick/boundary, including events raised by that tick.
- A hard interruption discards the old fast-forward wall-time budget; it does not carry a 20x backlog into a decision or combat. This is an explicit boundary, not a performance shortcut.
- Separate requested speed, effective speed and pause reasons. Closing a panel must not clear user pause, decision pause, terminal state or save-error pause. Resume never jumps back to 20x after a threat.
- Continue restores the exact world state but opens paused, with the last requested speed visible; resuming an active fight is capped at 1x.

### 3.4 Travel states and interruption policy

Current owner navigation preference: arrivals always open a required onward-destination modal describing what happens at each option. It cannot be dismissed without selecting a destination. The initial station has a Depart action that opens the same chooser. The story-neutral prototype describes exploration/station services; later story content will supply richer choices. Map is informational rather than a free-choice destination picker. This supersedes older map-selection/dropdown UI tasks below.

Use a typed travel state independent of pause reasons and overlay state:

`DOCKED -> CRUISING -> STOPPED / ENGAGED / DOCKED`

`ENGAGED -> SETTLING -> REGROUPING -> CRUISING or STOPPED`

`STOPPED -> TOWING -> DOCKED`

Terminal defeat is a run state, not a route destination. Mandatory event decisions suspend whichever valid travel state was active.

| Trigger/action | Required behavior |
| --- | --- |
| Select map location | Inspect/preview only. Show distance, ETA at selected speed, fuel and service/known-hazard information. |
| Travel/Change course | Validate discovered/access-permitted target, atomically replace route from current position; explicit action can undock. Never pay fuel/days for the whole leg up front. |
| Stop | Stop strategic progress immediately at a tick boundary, retain destination for Resume; no docking privileges, fuel use or RP. Free self-repair continues if unpaused. |
| Cancel destination | Clear active/retained route atomically; remain stopped. |
| Threat detected | Make approaching enemies visible under normal visibility rules, cap at 1x, stop cruise and engage automatically. Do not unpause a user/decision pause. Surface combat above management. |
| Optional POI discovered | Record/mark it, reduce fast-forward to 1x, offer Investigate/Continue in a compact notification. Continue does not restore 20x. |
| Investigate POI | Store the previous destination as a single optional return target; route to POI from current position. No automatic reward or teleport. |
| Leave investigated POI | Offer Resume previous route; do not silently chain detours. Preserve/cancel the return target explicitly. |
| Choice/NPC decision | Persist pending decision, stop simulation and show concise options. Resolve once; resume at 1x only after acknowledgment and if no other pause reason remains. |
| Research completes | Commit project completion and stop fast-forward at that exact threshold; pause with Set Focus/Continue. No RP wallet, auto-focus or excess-project spillover. |
| Repair completes | Coalesced notification and reduce 5x/20x to 1x once for that completion; no modal per ship and no repeated notification at full health. |
| Fuel reaches zero | Stop exactly at affordable distance and pause; show rescue/tow and map options. No negative fuel or hidden teleport. |
| Arrival at chosen station | Commit actual arrival/docking once; travel stops, speed becomes 1x and service interface opens. Docked regeneration continues unless paused. |
| Victory | Commit outcome, display compact nonblocking report, regroup and resume retained route at 1x. Expanded report does not replace the world. |
| Save fails | Freeze at last safe tick with explicit error and retry; never show a successful purchase, event choice, reward or departure that did not commit. |
| Flagship destroyed | Stop navigation/events/healing, atomically settle losses and terminal state, then show existing defeat UI. Menu exit is allowed. |

Priority within the same tick: terminal loss, save failure, mandatory decision/fuel exhaustion, combat threat, research completion, optional discovery, repair notification, ordinary arrival. Collect coincident facts; defer lower-priority UI, never drop its event receipt or reward. Destination arrival cannot dock a fleet still under an unresolved threat.

An existing combat withdrawal/stalemate must not masquerade as victory or clear enemies. Leave the route stopped and retain surviving enemies/encounter state, with visible retry/resume information. Automatic ten-second inactivity handling must not award loot, start an endless engagement loop or strand the UI. Manual tactical retreat expansion is not part of this task.

### 3.5 Live management and station services

- Default Fleet view is the live expedition, not a second formation-rendered world. Clicking Fleet closes management overlays and exposes fleet selection/details.
- Ships, Research and Map are reusable nonmodal panels. Keep a continuously visible, unobscured fleet area and time/threat controls. An opaque full-screen tab with the world merely running underneath does not meet the requirement.
- Initial responsive layout draft: full world at rest; management occupies the lower/side region and reserves at least one-third of viewport area around the fleet. At 640x360 use compact/scrollable management panes, not unreadably shrunken text. Validate fitting geometry before locking this layout.
- Reuse fitting/stock/callouts and shop center-panel behavior inside the available management region. Retain selection, scroll, filters, pan/zoom and pending-action cancellation rules. Opening/closing these panels must not rebuild the world.
- Outside a docked shipyard, allow inspection and research focus changes; show a short reason on unavailable service actions. Enforce all restrictions in GameState, not just disabled buttons.
- Shipyards provide buying, fitting, stock selling, salvage and paid hull repairs. Other stations expose only their declared services: refuel, automatic trade, communications. Do not turn every inhabited location into a shipyard.
- Noncombat station arrivals are safe by default in the mechanical fixture. Passing near an unselected station discovers it but does not auto-dock, sell/deliver loads or open its shop.
- If a threat invalidates service access, close/preempt transient shop/drag interactions and revalidate queued commands before committing. Do not consume a click intended for shop UI as a combat order.
- Save/economy updates are tick-boundary commands. Instant paid repairs quote current damage after any prior self-repair tick; display changed prices and require reconfirmation for a stale quote rather than overcharge.
- Settings retains pause behavior; management panels do not inherit settings' pause. Manual target/ability controls that currently work remain optional, never required to navigate.

### 3.6 Fuel and rescue

- One bounded fractional tank on the expedition, unrelated to equipment cargo UIDs. Start full; capacity and NU consumption are explicit validated tuning, not new equipment.
- `fuel_used = distance_nu * fuel_per_nu`. Rerouting, discovery, stopping, opening menus and changing speed do not spend fuel independently.
- Plot routes longer than current range with a clear warning and explicit confirmation. Unreachable/inaccessible locations still cannot be selected. Display reachable range on the map.
- Refueling is an atomic quoted credit purchase, clamped to tank capacity. Reject invalid/negative/nonfinite amounts, insufficient ordinary funds, duplicate submits and undocked access. No silent partial charge.
- Emergency rescue is available when stranded outside combat; unresolved threats must be resolved first. Always include a known safe starting/refueling station as a fallback candidate.
- Show nearest accessible safe refuel station, tow distance, fee, fuel refill and debt before confirmation. Rescue preserves fleet and loads, consumes no tank fuel, and earns no travel RP. It uses the same visible scrolling journey, no random encounters and no scene transition.
- Draft fee: normal credit cost of the refill plus a base rescue fee and distance fee. It may leave credit debt; this exception is explicit and atomic. Ordinary purchases may not create debt.
- Tow ends docked with a full tank paid for by that quote. If already at a refueling station, offer emergency refill on the same disclosed debt terms without fake travel. No softlock when credits are zero/negative.
- Tow cannot be rerouted into free ordinary travel; Stop pauses its progress and Resume continues the contracted tow. This is the one non-self-propelled navigation contract, not a new piloting system.
- Research and travel-day event pressure do not advance during towing. Self-repair still advances with unpaused simulation seconds. Delivery occurs under the same genuine-arrival/origin rules as ordinary docking.

### 3.7 Research, regeneration and trade

**Research**

- Each moving interval allocates `current_active_lab_rp_per_day * distance_nu / nu_per_day` to the current focus. Preserve Lab I/II/III = 1/2/3 and current chassis modifiers; no added baseline.
- Focus changes while flying take effect at a committed tick boundary. Allocate prior distance to the old focus first; no retroactive production or duplicated departure/arrival settlement.
- Preserve fractional progress. Recompute cached production after actual fleet/equipment/research changes, not every draw or every tick. Lost labs cease producing for all subsequent travel.
- Unfocused RP and completion overflow accumulate in a persistent research-point balance. Choosing focus automatically allocates the balance to that project; retain any excess for the next focus.

**Free self-repair**

- Add one explicit nonnegative `self_repair_hp_per_second` tuning field per chassis in [data/slot_chassis.json](data/slot_chassis.json); expose its rate in ship inspection.
- Heal surviving hull by `rate * unpaused_noncombat_sim_seconds`, clamped to current maximum hull. No credit consumption, paid job, equipment requirement or component rebuilding.
- Applies during cruise, stopped time, docking and towing. Suspend through ENGAGED/SETTLING and unresolved defeat, including the tick on which a threat is admitted. It resumes after successful settlement.
- Exactly-zero hull may regenerate; destroyed hull may not. Do not lose fractional healing on save/load. Do not replay regeneration for offline time.
- Leave working combat repair equipment distinct and unchanged. Do not regenerate its finite reserves. Preserve existing shield recharge behavior and shield state across encounters; no free shield reset caused by reopening a panel or reinitializing battle.
- Initial rates are balance drafts: derive explicit HP/second from base chassis hull divided by 900 seconds for Defensive/Corsair/Frigate, 1200 seconds for Combat/Fighter/Drone, and 1500 seconds for Civic/Research/Transport. Write numeric values into all nine catalog records; do not hide missing values behind a runtime default. Armor increases repairable HP, not chassis regeneration rate.
- Document that full recovery by waiting at 20x is allowed and paid repair is the instant alternative. Tune rates through playtesting rather than changing that rule.

**Trade**

- Keep load ownership by equipment UID, capacities 10 goods/4 passengers, existing prices/bonuses and once-only casualty fees.
- Replace leg-start loading with genuine station undocking. Load cargo from inhabited origins; board passengers at inhabited origins when departing toward an inhabited destination. Never create passengers/cargo at a mid-space reroute or POI.
- A course change preserves existing loads and origin; it neither duplicates nor refunds them. As in current automatic delivery, the next eligible inhabited arrival can deliver without a load-management modal.
- Prevent same-origin redocking, zero-length routes and repeated arrival callbacks from minting credits. Loads returning to their origin stay aboard until a different inhabited destination.
- Noninhabited detours keep loads. Host destruction clears them and charges passenger fees once, even if settlement is retried or continued.
- Supply explicit departure/arrival transaction IDs. Do not reuse a completed station-visit receipt for every later legitimate visit; do not award a location's one-time salvage on each visit.

### 3.8 Encounters, discovery and persistent space

- Author locations and events as validated data with stable string IDs, positions, region/act, service flags, discovery/access conditions, trigger and effects. UI text may reference existing localization patterns; do not hard-code narrative callbacks into travel.
- Event triggers needed now: entering a region/radius, crossing a route interval, docking, traveled-day threshold, completion of another encounter, and a seeded optional/random encounter. Choices support flags, credits/fuel, revealing/changing locations and starting an existing combat template.
- Minimum prototype content: neutral communications decision, derelict salvage, distress POI, ambient anomaly, asteroid corridor, ambient nebula, hostile patrol and two service destinations. Use existing enemies/art and neutral placeholder text, not the incoming storyline.
- Retain three act regions and gate hooks. Start with public Act-I navigation destinations discovered; later regions require an explicit fixture gate. Do not make inaccessible regions reachable by drawing a straight line across them.
- Derive optional POIs from seed + generator version + spatial cell + candidate index, not frame rate, the number of reroutes or a new random roll on each selected leg.
- Use independent deterministic RNG streams for world generation, encounter scheduling/combat, loot and cosmetic effects. Persist authoritative RNG states/cursors as decimal strings where integer precision requires it.
- Random encounter admission uses traveled distance and persisted pacing/cooldown, never wall-clock time. Do not roll repeatedly while stopped, paused, docked or re-opening the map. Going back and forth cannot reset a cell's cleared enemies or salvage.
- Discoveries are global world facts. Ignored optional contacts remain discovered on the map and do not repeatedly interrupt until another explicit state change warrants it.
- Materialize authoritative POIs/enemies/hazards before they affect the fleet. Generate decorative cells lazily, cull them by camera, and unload inactive physical cells only after recording durable mutations.
- Store visited stations separately from discovery; neither implies all nearby threats/loot are cleared. Location modifications, completed choices, consumed salvage and destroyed enemies survive revisit/Continue.
- Suspend unloaded areas rather than simulating the whole galaxy. Retain mutable enemy/hazard records and last local state; no offline respawn, regeneration or random reward roll.
- Seed stationary station scenery by location identity and streamed scenery by cell identity. Preserve the normalized menu-starfield principle: resizing and UI actions do not change layout. Do not copy transient star arrays into saves.
- Nebulas initially provide visible environmental presentation and map metadata only. Solar/nebula equipment modifiers remain deferred unless already functional; do not invent new debuffs.
- Asteroids are actual neutral physical hazards during travel and combat: drift, interception, silhouette collision and persistent fracture. No mining/material payouts. Slow to 1x before entering a dangerous field so automatic navigation is readable; no manual dodging requirement.

## 4. Persistence contract

Use a fresh `user://expedition_run.json` namespace with payload `format: "continuous_expedition", version: 1`, wrapped by existing `AtomicRunStore`. No migration or old-run chooser. New Run/Continue use this namespace; old files remain untouched and are not prerequisites.

Do not remove `.next`/`.bak` reliability for new saves merely because old-save compatibility is unwanted.

### Required saved state

| Group | Required authoritative data |
| --- | --- |
| Identity | Run ID, seed, difficulty, payload version, world-generator/tuning version |
| Physical economy | Ship IDs/chassis/hull/formation, equipment UIDs/ranks/mounts/loads, next IDs, credits, research/focus/fractions, score |
| Navigation | NU position, local origin/frame, travel state, target, route origin/progress, retained detour destination, dock location/visit ID, traveled days/distance |
| Time/resources | Simulation tick/time, fractional fuel/capacity, requested speed, durable pause/event state; no accumulated offline wall time |
| World | Discovered/visited IDs, materialized mutable locations/cells, encounter statuses, destroyed entities, claimed salvage, flags/gates, generation/pacing cursors |
| Events | Stable event instance IDs, pending decisions/options, already-applied effect receipts, admission ordering/cooldowns |
| Active encounter | Encounter ID/template/version, objectives/waves, engagement-local origin, current phase, enemies and player actors, damage/score deltas, pending settlement/result |
| Combat runtime | Hull references, shields, poses/velocities/headings, cooldowns, targets/orders by ID, projectile/beam gameplay state, RNG, command sequence/receipts, ability/visibility state, doctrine/carrier timers/sorties/ammo, repair reserves, asteroid records |
| Rescue | Contract/quote ID, destination, distance/progress, paid fee/refill terms, completion receipt |

Derived caches, textures, masks, UI nodes, cosmetic particles, interpolated poses and star arrays are not saved. Rebuild them without changing simulation facts. Store references by stable IDs and resolve in two passes; no serialized live Godot object references.

### Durability and transactions

- Full validation before applying a loaded payload: finite coordinates/fuel/time/health, bounded arrays/counters, unique IDs, legal mounts, required flagship or terminal-loss invariant, valid graph-independent routes, valid service/dock state, reachable entity references and mutually consistent event/settlement receipts.
- Factor common physical payload validation for reuse rather than weakening `HangarCheckpoint.valid` to accept contradictory old/new shapes. Move shared scalar validation dependencies in trade/science toward `SaveValidation` where required by the new validator.
- Routine transactions stage a proposal at a simulation tick boundary, validate/save, then apply only the accepted delta to stable runtime entities. Never recreate the whole fleet on a research-focus or credit update.
- Periodic autosave: every five **real** seconds of active play when dirty, not five multiplied simulation seconds. Also save on route/stop commands, docking, discovery/decision boundaries, research completion, purchases/refits, encounter admission/settlement, terminal loss and orderly exit.
- Smooth simulation may have up to five real seconds of crash rollback between autosaves. Gameplay transactions and event receipts are durable immediately; this rollback allowance is not permission to show success before commit.
- Serialize an immutable snapshot from one tick. Queue input during commit; simulation does not race snapshot mutation. Start with the simplest measured implementation; add a writer thread only if profiling proves it necessary.
- Failed transactions leave pre-command state and RNG/IDs unchanged. A failed periodic save pauses the current consistent runtime and offers retry; do not quietly continue accumulating uncheckpointed events.
- Commit outcome, lost equipment/loads, passenger fees, credits, physical loot UID, score, carrier state and encounter/world receipts together. Keep a pending settlement idempotent across retry/crash/Continue.
- Restore mid-cruise, stopped, docked, mid-choice, mid-tow and mid-combat. Do not reset combat to the encounter start, heal enemies, refill shields or replay the whole journey.
- Carrier allowances remain per encounter and per equipment UID, matching current semantics. Only a genuinely new encounter initializes a new allowance; revisits/reloads/transfers/re-engagements of the same encounter do not.
- Main-menu summary must distinguish no save, unsupported expedition version, corrupt save and valid ongoing/terminal run. Never silently turn a failed Continue into New Run.

## 5. Work packages and dependencies

All proposed paths below are recommendations, not permission to build a generic framework. Reuse existing classes where a small extraction suffices. Keep types and module ownership clear; do not create one manager per event type.

**Shared-file rule:** designate one integration owner for [scripts/hangar_state.gd](scripts/hangar_state.gd), [scripts/battle_simulation.gd](scripts/battle_simulation.gd), [scripts/hangar_screen.gd](scripts/hangar_screen.gd) and the baseline runner in each implementation batch. Parallel agents may own isolated modules/tests; they must not independently rewrite these files.

### Phase 1 - Continuous flight prototype

#### E01 - Establish data/command contracts and mechanical fixture

**Depends on:** none. **Owner area:** schema/content foundation.

- [ ] Adapt `CampaignGraph` geometry into generated NU locations without treating edges as route restrictions. The current checked-in fixture is a deliberate hand-authored prototype, not final generated campaign geometry.
- [ ] Define GameState commands: preview/select course, stop/resume/cancel, choose event, dock/undock, quote/buy fuel, quote/accept rescue, and existing physical services. Return repository-standard explicit error information.

**Acceptance:** one deterministic, story-neutral world fixture has three represented act regions, usable initial service destinations, a gated later region and stable IDs. No old story sequence starts automatically.

#### E02 - Add one fixed-step expedition clock and state machine

**Depends on:** E01. **Owner area:** simulation core.

- [ ] Add all travel-state transitions and interrupt priorities from section 3.4; this prototype covers cruise, stop, dock and fuel interruption only.
- [ ] Add boundary proposal/commit coordination so world/economic effects are durable before the UI receives success. Current typed boundary signals are test/core events only.
- [ ] Add overload profiling/backlog handling that preserves input responsiveness and reports reduced effective speed. Prototype preserves tick debt and does not yet budget work per frame.

**Acceptance:** a headless route can be stopped/rerouted repeatedly at arbitrary fractions with no teleport, extra days, duplicate arrivals or leftover fast-forward ticks after interruption.

#### E03 - Mount continuous travel in the existing game UI

**Depends on:** E01, E02. **Owner area:** world view plus combat lifecycle integration.

- [ ] Factor player initialization/noncombat movement from `BattleSimulation.setup_owned`; support a valid fleet in an empty world without immediately declaring victory/withdrawal.
- [ ] Add world-space camera-follow/upward travel projection, smooth reroute frame changes, floating-origin handling and deterministic location-seeded star cells. The current view uses deterministic campaign-seeded stars and distance-driven vertical drift only.
- [ ] Handle pause/stop exhaust, resizing and overlay-safe camera framing without regenerating stars or resetting pan/zoom.

**Acceptance:** the flagship and escorts cruise upward, stop and reverse strategic course without scene replacement, actor respawn, background reseeding or formation teleport. No combat AI runs merely because an empty cruise world exists.

#### E04 - Establish fresh expedition saves and stable live commits

**Depends on:** E01, E02, E03. **Owner area:** GameState/persistence.

- [ ] Add `scripts/expedition_checkpoint.gd`; reuse AtomicRunStore and shared physical validation without node-pending constraints. The thin slice currently stores an optional expedition snapshot inside the physical-hangar-v2 envelope; replace this temporary wrapper before broad rollout.
- [ ] Replace routine `_apply_hangar` reconstruction with validated reconciliation by ID/UID. Preserve runtime actor references and update only affected stats/caches.
- [ ] Add `tests/test_expedition_persistence.gd`: crash-stage recovery, bad payload rejection, generation conflicts and object identity preservation beyond the focused arrival tests.

**Acceptance:** Continue resumes the exact prototype position paused; a focus/credit/save operation does not move or reset the live fleet. Old user files are neither read as expeditions nor rewritten.

#### E05 - Add travel controls to existing management pages

**Depends on:** E03, E04. **Owner area:** UI.

- [ ] Keep Ships/Research/Map accessible during travel and add their remaining service/overlay behavior without replacing their current panels.
- [ ] Remove `traveling` UI lockout and graph Tween authority. Basic map route controls call new commands; final discovery/range map is E08.
- [ ] Wire alert priority/input cancellation so threats and decisions cannot be hidden behind management or inherit stale clicks.
- [ ] Add proposed `tests/test_expedition_ui.gd` native layout/interaction coverage at 640x360, 1280x720 and 1920x1080.

**Acceptance:** opening and using Research/Map while cruising at 5x keeps simulation live and the actual fleet visible. Pause stops simulation, not UI. No management close action silently resumes a paused game.

#### E06 - Add event admission and interruption plumbing

**Depends on:** E01, E02, E04, E05. **Owner area:** event system.

- [ ] Extend the foundation to radius/arrival triggers, general validated effects and multiple encounter priorities/segment sweeps. Hook combat admission to E11's eventual adapter; add multiple-boundary and competing-event coverage. The single signal is not a random encounter/loot system.

**Phase 1 gate:** native demo shows continuous fleet travel, mid-leg course change, Stop versus Pause, all speeds, a scripted interruption, live management and working Continue. No scene swaps. It is a prototype, not the complete feature; fuel, persistent POIs and seamless combat remain mandatory.

### Phase 2 - Physical destinations and persistent exploration

#### E07 - Add deterministic world discovery and mutable locations

**Depends on:** E01, E02, E04, E06. **Owner area:** world model.

- [ ] Implement proposed `scripts/expedition_world.gd` for location/cell identity, lazy materialization, discovery, visitation and mutations.
- [ ] Generate the five requested optional POI classes: derelict, asteroid field, distress signal, anomaly and hidden location, using stable spatial seeds.
- [ ] Separate discovered/visited/cleared/claimed states and persist them; add detour return-target handling.
- [ ] Persist materialized hostile/hazard state before unload; reload cannot recreate destroyed entities or loot.
- [ ] Add fixture gates and reject illegal cross-region segments without reinstating beacon-edge routing.
- [ ] Extend world/persistence tests for revisits, detour cancellation, seed reproducibility, resize independence, RNG separation and repeated rerouting.

**Acceptance:** the same seed and traveled area give the same contacts regardless of frame rate, overlay use or route replanning. Returning to a derelict does not restore claimed salvage.

#### E08 - Finish the strategic overlay

**Depends on:** E05, E07. **Owner area:** map UI.

- [ ] Bind `GraphView` to expedition locations/position rather than `get_reachable_nodes(current)`. Reuse its pan/zoom/hit testing and station art.
- [ ] Show three act regions, discovered/public stations, unknown-region treatment, current continuous position, chosen destination and straight planned segment.
- [ ] Show current range, remaining distance, travel-day ETA, selected-speed ETA and destination services/known conditions; calculations must match actual route physics.
- [ ] Retain optional-discovery markers, planned detour/return target and visited/cleared distinctions without exposing hidden enemies.
- [ ] Preserve map pan/zoom on state refresh and while the fleet marker moves. Do not re-run `set_current_node` camera reset for every tick.
- [ ] Validate hit targets and readable details at all supported sizes; selecting inspects, explicit Travel changes course.

**Acceptance:** at a mid-leg stop the marker and fuel/ETA preview are correct; the player can route to a discovered non-neighbor and a discovered detour, but not a locked region.

#### E09 - Fuel, docking, service access and rescue

**Depends on:** E04, E05, E07, E08. **Owner area:** economy/service integration.

- [ ] Add distance-accounted fractional fuel with exact depletion clipping and speed-independent quotes.
- [ ] Physically render/approach selected stations, dock once within arrival radius and open only declared services. Do not trigger services on mere proximity.
- [ ] Invalidate/reconfirm stale repair quotes when continuous self-repair changes the displayed cost; wire this with E10.
- [ ] Implement refuel amount/price/confirm using shared UI; commit tank and credits atomically.
- [ ] Implement quoted rescue contract, visible tow, emergency station refill, explicit debt and no softlocks. Save/restore mid-tow.
- [ ] Adapt HangarTrade to undock/dock visit IDs, reroute-safe UID loads, distinct-origin delivery and once-only fees.
- [ ] Add proposed `tests/test_expedition_services.gd`: 1x/20x same fuel, zero fuel mid-tick, insufficient credits, debt rescue, reload tow, duplicate dock, service rejection and trade exploit cases.

**Phase 2 gate:** depart a shipyard with trade loads, discover/investigate a POI, reroute to a nonadjacent port, dock/refuel/refit, return to a changed location and Continue. Exhaust fuel with no credits and recover through the actual UI. Nothing reloads the gameplay scene.

### Phase 3 - Continuous activities, combat and pacing

#### E10 - Continuous research and chassis self-repair

**Depends on:** E02, E04, E05, E09. **Owner area:** activity/economy integration.

- [ ] Replace `journey_rp` departure/arrival settlement in the expedition path with distance-interval focus allocation.
- [ ] Preserve fractional project progress and existing rates/bonuses; stop precisely on research completion and persist completion/score once.
- [ ] Make live focus changes safe while traveling; retain current tree camera/interaction behavior and clear, nonduplicated rate/progress display.
- [ ] Add explicit catalog regeneration rates, validation and ship inspection text. Advance hull from noncombat simulation seconds, not travel days or real seconds.
- [ ] Requote instant repair after regeneration, coalesce repair-completion interruption and avoid notifications every tick at max hull.
- [ ] Test all clock combinations: cruise/stop/dock/tow/combat/pause; 1x/5x/20x; zero hull; destruction; full hull; lost lab; focus switch; failed save/reload.

**Acceptance:** equal traveled distance yields equal research at all speeds. Equal noncombat simulation time yields equal healing whether moving or docked; stopped time earns no RP. No healing occurs during combat or Pause.

#### E11 - Admit and resolve combat without rebuilding the world

**Depends on:** E03, E04, E06, E07, E09, E10. **Owner area:** combat integration.

- [ ] Add encounter admission to the existing long-lived actor registry: stable enemy IDs, nearby entry positions and per-encounter context/objectives. Keep player poses, shields, cooldowns and environment.
- [ ] Separate engagement phase from persistent-world liveness. No empty-world victory, idle auto-withdrawal or global entity reset.
- [ ] Center existing AI arena assumptions on encounter position; keep combat bounds/targeting/visibility coherent with upward travel and rebasing.
- [ ] Freeze cruise, reduce speed to 1x before hostile simulation, preserve user Pause, and immediately surface threats through management.
- [ ] Reuse audio, radar, ability/target controls, active weapon/support behaviors, finite carriers, asteroid/projectile collisions and visual effects.
- [ ] Key rewards/reserves/loot by encounter ID, not destination node. Preserve per-UID allowances across reloads/transfers and terminate sorties on source loss.
- [ ] Implement a real runtime save/restore codec, proposed `scripts/expedition_combat_codec.gd`, covering section 4. Rehydrate references in two passes and restore authoritative RNG/counters before advancing.
- [ ] Add combat outcome transaction detached from destination arrival; remove dead hosts/equipment/loads and settle credits/loot/score/receipts exactly once.
- [ ] Keep surviving ships in place, show a compact saved report, regroup by desired offsets and resume retained route at 1x. New destination orders issued during combat apply afterward.
- [ ] Handle final damaging shots, source loss, pending waves, stalemate/withdrawal, save failure and simultaneous flagship death without accidental reward/resume.
- [ ] Add proposed `tests/test_expedition_combat.gd`: uninterrupted versus mid-fight restored continuation, active carrier/ability/shot/asteroid state, repeated settlement, phase-boundary crash and live actor identity.

**Acceptance:** travel -> visible enemies -> autobattle -> report -> regroup -> travel uses the same root/world/player actor identities. Continue mid-fight yields the same authoritative outcome as uninterrupted simulation. Victory does not teleport to the destination or settle untraveled research.

#### E12 - Stream physical environments and tune encounter pacing

**Depends on:** E07, E10, E11. **Owner area:** environment/pacing.

- [ ] Integrate real asteroid-field streaming with travel and combat, including offscreen persistence, fracture state and swept high-speed boundary admission.
- [ ] Add ambient nebula transitions and seeded station/cell scenery using existing art; keep stars/scenery distinct from gameplay RNG.
- [ ] Add seeded hostile/random event scheduling with travel-distance cooldowns, region eligibility, safe dock zones and no spawn-on-stop/replan farming.
- [ ] Prevent overlapping incompatible major encounters; queue mandatory triggers and keep optional discoveries available rather than losing them.
- [ ] Tune fixture journey length, initial known destinations, fuel station spacing, POI offset/density and interrupt rate. No full campaign/story authoring.
- [ ] Add proposed `tests/test_expedition_pacing.gd`: many-seed bounded travel intervals, no unavoidable fuel dead ends, no repeated cleared spawns and stable 20x interruptions.

**Acceptance:** a representative 10-15 minute UI playthrough includes useful research, regeneration, trade/refit, at least one optional detour, asteroid/nebula traversal and two natural battles, without long empty travel or constant popup spam.

### Phase 4 - Integration, regression and owner review

#### E13 - Complete entry/exit, retire obsolete runtime paths and port tests

**Depends on:** E08, E09, E10, E11, E12. **Owner area:** integration.

- [ ] Ensure New Run and Continue always enter the expedition shell, including active encounters/decisions/tows. Remove runtime dispatch to `auto_battle.tscn`.
- [ ] Remove old instantaneous travel/research settlement and map flight Tween from active code; do not leave hidden duplicate rewards or a legacy playable mode.
- [ ] Preserve standalone combat/legacy DTO readers only where existing tests/shared dependencies still need them. No broad unrelated deletion.
- [ ] Port current node campaign/navigation/playthrough/UI expectations to the new contracts. Retain ownership, mounted art, research rules, equipment, carrier, score, hull, sprite collision and atomic failure coverage.
- [ ] Extend [tests/run_baseline.ps1](tests/run_baseline.ps1) with expedition suites and native UI/world/combat checks, using its isolated APPDATA. Do not mark required tests skipped to get a green baseline.
- [ ] Verify changed entry/exit and persistence behavior with focused cases/files, including focused native checks where needed. Run a complete baseline only on explicit user request; record actual coverage and unrelated pre-existing diagnostics separately.
- [ ] Update [docs/HANGAR.md](docs/HANGAR.md), [docs/UI_PLAYTEST_POLISH.md](docs/UI_PLAYTEST_POLISH.md), [docs/HANGAR_DRAG_DROP.md](docs/HANGAR_DRAG_DROP.md), [docs/INTERMEDIATE_EQUIPMENT.md](docs/INTERMEDIATE_EQUIPMENT.md) and [docs/LEGACY_BOUNDARIES.md](docs/LEGACY_BOUNDARIES.md) where behavior/entry boundaries changed. Update other active user-facing help/README only where applicable.

**Acceptance:** no active help/UI claims RP is paid on arrival, that beacon adjacency is required, or that midflight shipyard actions are available. All supported Continue states are demonstrably resumable.

#### E14 - Verify performance, persistence soak and final UX

**Depends on:** E13. **Owner area:** verification and tuning.

- [ ] Add proposed `tests/test_expedition_playthrough.gd` exercising the whole mechanical loop without injected credits/research or forced combat results.
- [ ] Run deterministic long-route and revisit soak tests across at least ten seeds. Include repeated save/load, mid-combat/tow resumes, destroyed enemies, claimed salvage and late-region fixture gates.
- [ ] Fault-inject before stage, after stage and during promotion using AtomicRunStore semantics; test command retries and terminal loss settlement.
- [ ] Native review at 640x360, 1280x720 and 1920x1080: live fleet visibility, no scene flashes, readable alerts, fitting geometry, map pan/zoom, station panel behavior and focus/input safety.
- [ ] Profile full legal fleet plus current encounter entity caps, dense asteroid fixture and 20x cruise. Preserve existing visual/light/entity limits; no unbounded star/enemy/event node accumulation.
- [ ] Capture timings using monotonic measurements: average achieved speed within 5% of requested 20x over 60 real seconds of clear cruise on the recorded reference machine; event interruption within one simulation tick; no more than one authoritative tick beyond trigger tolerance.
- [ ] Target 60 FPS native at 1280x720 (95th-percentile frame <= 16.7 ms, 99th <= 33.3 ms) and no >100 ms UI/save stalls on the reference machine. Report machine/configuration and actual percentiles; if unmet, optimize or explicitly block completion instead of claiming success.
- [ ] Run a 30-minute accelerated world-streaming soak after warm-up: active cell/entity counts stay within configured caps and memory shows no monotonic growth from cleared encounters/closed panels.
- [ ] Play the representative slice end-to-end through UI, including empty-tank rescue with debt, waiting docked for free repair, rerouting during combat and once-only report rewards.
- [ ] Obtain owner review of live management layout, travel readability, interruptions, regen/fuel tuning and overall continuity. Record remaining UX issues here; no new story/content backlog until this gate passes.

**Done means:** the relevant section 7 requirements have focused evidence; new saved state survives the required resumes; the owner can review the mechanical slice. Full baselines and long soaks require explicit user request, not routine execution. A scrolling background over the old node/battle scene loop is not completion.

## 6. Draft tuning and delegation guidance

These are implementation starting values, not owner-confirmed balance. Keep them explicit and centralized so later agents do not independently choose incompatible scales.

| Setting | Initial draft |
| --- | --- |
| Navigation layout | Existing normalized three-act positions scaled to 7200 x 1200 NU; fixture station placement may be adjusted for refuel reachability |
| Travel conversion | 100 NU per campaign day |
| Cruise speed | 4 NU per simulation second; 25 seconds at 1x per traveled day |
| Presentation conversion | 8 tactical world units per NU; independent of viewport/map zoom |
| Fuel | Capacity/start 100; consumption 0.1 per NU; refuel 2 credits per unit with total rounded up once per quote |
| Rescue | Refill price + 100 credits base + 0.2 credits per NU, total rounded up once; disclosed debt allowed |
| Typical early leg | 200-400 NU / 2-4 travel days / 50-100 seconds at 1x; 2.5-5 seconds at 20x if uninterrupted |
| Physical location arrival | 4 NU radius; clip to first entry, not node center; quote/pay/travel use the same arrival geometry |
| Spatial generation cell | 200 NU square, versioned seed/key |
| Optional POI offsets | 20-60 NU off likely routes; deterministic cell candidates, not per-click random generation |
| Major pacing | Aim for a meaningful contact/opportunity every 100-200 NU; at least 80 NU between admitted random major interruptions, unless scripted |
| Regeneration | Per-chassis numeric rates derived from section 3.7; never a uniform hidden fallback |
| Autosave | Five real seconds while dirty plus durable command/event boundaries |

Pacing bounds apply to the representative fixture, not a promise that every arbitrary free-space course contains a story event. Use seeded supplemental contacts/ambient changes to avoid empty corridors; do not manufacture mandatory combat every fixed interval.

Generation must verify an accessible sequence of refueling stations with legs comfortably inside full-tank range, including after region unlocks. Rescue remains a fallback, not required normal routing. Named narrative locations and branch restrictions can later replace these drafts through data.

### Safe implementation batches

1. E01 first. Agree on command/data contracts before parallel implementation.
2. E02 -> E03 -> E04 establish the authoritative runtime and identity/save boundary.
3. E05 -> E06 completes the first playable prototype.
4. E07 -> E08 -> E09 delivers physical destination navigation.
5. E10 -> E11 -> E12 delivers activities, seamless combat and pacing.
6. E13 -> E14 integrates and verifies the whole conversion.

This dependency order intentionally limits parallel work in shared core files. Parallelize fixture authoring, isolated tests and visual assets/layout prototypes only after their required contracts exist. Do not parallelize several incompatible GameState/BattleSimulation refactors.

Every implementation handoff must include: completed task IDs, exact files touched, contract/schema changes, focused test commands/results, failure-injection results where applicable, native evidence when UI changed, and remaining blockers. Keep unchecked work unchecked; a stub/event interface is not its later integration.

## 7. Final requirement checklist

| Requirement | Owning tasks | Required evidence |
| --- | --- | --- |
| Continuous upward fleet/world | E02, E03, E05, E11 | Root/world/actor identity tests and native travel-combat-dock capture |
| Automatic navigation and rerouting | E02, E07, E08 | Mid-leg reroute/stop/resume/cancel; free non-neighbor course; no teleport |
| Pause/1x/5x/20x and interrupts | E02, E06, E10, E11, E14 | Equal-sim-time state, swept boundaries, effective-speed measurement, no stale 20x continuation |
| Three-act strategic overlay | E01, E08 | Continuous position, gates, discovered locations, planned route/range and preserved pan/zoom |
| Detours/exploration | E06, E07, E12 | All five POI types, Investigate/Continue, return target, revisit consistency |
| Fuel/refueling/rescue | E09 | Same-distance fuel equivalence, zero crossing, atomic quotes and debt recovery |
| Background activities | E10 | Moving-only research, unpaused noncombat regeneration including docked/stopped, no construction |
| Seamless autobattle | E03, E11 | In-place enemy admission, unchanged player identities, live equipment, saved result and regroup/resume |
| Physical station interactions | E05, E09 | Docked service gating, visible approach, real trade arrivals and no midflight refit |
| Scripted/random event foundation | E06, E07, E12 | Validated triggers/effects, pending choices, deterministic admission and no duplicated effects |
| Persistent world | E04, E07, E09, E11, E14 | Midroute/midfight/midtow restore, cleared enemies/loot, once-only transactions and failure recovery |
| Pacing and UX | E05, E12, E14 | Natural representative playthrough, native resolutions, bounded streaming and measured performance |

No new storyline implementation is required to check any row. Story integration starts after these mechanics and UI are reviewed.
