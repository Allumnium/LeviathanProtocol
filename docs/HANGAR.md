# Physical hangar

Current scope is a continuous-expedition vertical slice using the existing physical systems, equipment and UI. Follow E01-E14 in [TODO.md](../TODO.md). Further equipment tiers, bespoke boss phases and full-campaign depth are deferred for a later story-led pass. The implementation and test history below describes existing work, not a requirement to finish all that depth before reviewing the slice.

New Run and Continue use the existing hangar screen, with the Map as the first, home tab. New expedition checkpoints use `user://expedition_run.json`; the temporary payload still embeds expedition state in the physical-hangar-v2 envelope. The previous physical/material runs and blueprint libraries remain separate. There is no active ship-design screen or material wallet.

## Ships and loadouts (fleet-command D1)

The player commands fleets, not parts. This section supersedes the stock, equipment-shop and drag-fitting descriptions further down (kept as history); see the Fleet-command direction in [TODO.md](../TODO.md).

- **No equipment stock.** Equipment exists only on ships. Instance IDs remain internal so cargo/passenger loads follow them. There is no equipment buying, selling or drag-and-drop.
- **Named loadouts** per ship class live in [ship_loadouts.json](../data/ship_loadouts.json) (the first is the default); keys are `equipment_id` or `equipment_id@rank`. [ship_loadouts.gd](../scripts/ship_loadouts.gd) holds lookup and pricing.
- **Refits are free** and happen only at a shipyard, including when credits are zero or in debt. In Ships, choose a loadout for an existing ship; clicking a mount lists every compatible part, plus Remove part. Choices have no refit price or credit requirement. Replaced parts are scrapped. Loaded holds/cabins must deliver before they can be removed; refits that keep a loaded hold keep its cargo. Changes remain atomic; buying new fitted ships still costs credits.
- **All obtainable equipment is selectable**; research no longer gates parts. Deferred items (Gravitic Snare, Disruption II) are never offered.
- **Buy Ships** sells fitted ships for chassis price + half their parts' price. Salvage and repairs are unchanged.
- **Battle rewards** are credits plus research points; battles no longer award equipment.
- Tabs are Map (home), Fleet (arrangement) and Ships (refits). Research stays behind the header button.

Tests: [test_ship_refit.gd](../tests/test_ship_refit.gd).

## Squadrons (fleet-command D3)

Squadrons group ships of the same chassis so one default named loadout is meaningful. Each owns a stance, its members' formation centroid, a default loadout and explicit per-ship override IDs. Actual equipment and positions remain on ships; grouping never duplicates parts or rearranges an existing fleet. New purchases and rescues join a compatible squadron; empty groups disappear after salvage or losses.

The optional `squadrons` checkpoint field is validated with the fleet in the existing atomic transaction. Older physical-v2 saves derive deterministic groups without changing health, loads, equipment or formation. Continue restores orders; malformed membership, defaults, stances and anchors are rejected rather than repaired.

Seek & Destroy retains normal automatic combat. Defend Flagship attacks visible threats within 260 units of the flagship and returns to its relative formation anchor otherwise. Evade avoids visible enemies within 360 units, falls back behind the flagship and does not automatically fire. Explicit attack orders override a passive stance until cleared or invalidated. Movement retains forward thrust, turn limits and hazard/boundary avoidance. Default stance is Seek for every existing squadron, preserving prior battle behavior.

Fleet's roster uses chassis artwork plus squadron number/count. Selecting any member or box-selecting part of a squadron selects its entire block; dragging translates all selected blocks with internal spacing intact and one atomic save. Empty-space deselection, multi-block selection, white silhouette glow and pan/zoom persist. Double-click a ship to inspect it in Ships.

The selected squadron panel preserves meaningful condition readouts (summed current/max hull, DPS, shields and actual passenger/cargo loads), then offers explicit stance orders, its default named loadout, exact aggregate repair quote and a quantity/total-price purchase into that squadron. Default-loadout changes refit non-overridden members only; **Reset overrides** deliberately applies the default to everyone. Buy N uses that default, charges the full fitted quote and checks the complete command cost before creating any ships. Repairs/refits/purchases require a docked shipyard, remain all-or-none and preserve occupied holds/cabins. In Ships, **New squadron** splits the inspected ship without moving/refitting it; **Join #** transfers it to another same-chassis group. Stance/assignment orders can be changed during travel, but not during a pending battle or after the run ends.

Defending carriers launch only against nearby threats, and their sorties obey the flagship guard radius. Evading carriers do not launch automatically or spend replacements; explicit attack orders override this too.

Regressions: [test_hangar_squadrons.gd](../tests/test_hangar_squadrons.gd) runs headless and native in the baseline. Its 179 focused checks cover malformed saves, Continue, unique ownership, group rollback, overrides, load retention, aggregate condition/transport readouts, combat targeting/movement/carriers, three-resolution layouts, real pointer group actions, block/box selection and preserved formation camera. Full D3 baseline acceptance is tracked in [TODO.md](../TODO.md).

## Behavioral combat research (fleet-command D4)

Research changes how existing equipment behaves, without new items, artwork or save fields. Earned research IDs, costs, prerequisites and exclusive branch choices remain intact; Continue derives the same battle effects from the saved research. The research tree, completion toast and installed-part inspection disclose the actual effects.

- **Prismatic Lasers** (`energy_manipulation`) replaces the old flat energy-efficiency bonus. Player Laser and Double Laser become continuous beams, ramping from base DPS to twice base DPS over four uninterrupted seconds on the same target. Range/contact loss, changing targets, obstruction or stopping fire resets the lock. Double Laser retains its emitter count; magazines and Tactical Computer synchronization still help. Flat hull armor scales with the fraction of a shot rather than being charged on every simulation tick. Other weapons and enemy lasers are unchanged.
- **Siege I** (`siege_i`) makes each Missile Rack projectile split into three interceptable half-damage fragments within 100 units of its target: 150% total parent damage if all land. Fragments distribute over up to three visible nearby hostile combatants within 140 units of the original target, or converge when fewer targets exist. The parent alone spends ammunition; fragments cannot split recursively or acquire hidden targets after guidance is lost.
- **Bastion II** (`bastion_ii`) gives living shielded player ships a pulse restoring up to 25% of shield capacity every eight combat seconds, even under fire. It supplements ordinary recharge, never exceeds capacity and cannot revive a destroyed ship. Suppression blocks a pulse rather than banking it. A cyan expanding ring marks actual restoration.

The beam's widening cyan/magenta bands, amber missile fragments and shield ring communicate effects in the battle world, without added combat labels. Fixed-step replay includes lock duration, pulse clocks, fragmentation flags and ammunition, but excludes visual-only rings. Pending battles already block research mutations, so effects stay tied to the committed deployment.

Regressions: [test_research_combat.gd](../tests/test_research_combat.gd) runs headless and native in the baseline, covering exact damage/intervals, armor, lock resets/occlusion, visibility, stances, interception, finite ammunition, Continue, exclusivity, save rollback, malformed metadata, deterministic replay, three-resolution details/toasts and native effect pixels. Economy/travel nodes, activated abilities and command-limit growth remain separate D4 work.

## Demo vertical slice

**Expedition rewards**

Event choices and frozen battle rewards support credits, research, fuel, missiles and a rescued escort chassis. Existing derelict salvage supplies a small fuel recovery, capped at tank capacity; feedback reports the amount actually recovered. Winning the distress encounter adds a healthy Transport with its default fitted loadout, fresh unique ship/equipment IDs and empty holds/cabins. It does not become a flagship or replace existing ships. If command capacity cannot accommodate it, the crew pays the exact fitted purchase value instead, as disclosed by the encounter. Reports identify the ship or compensation alongside RP/fuel/ammunition.

Rewards commit atomically with event receipts and battle settlement. Failed saves grant nothing; retries/Continue cannot duplicate ships, resources or equipment, and non-victory outcomes grant no rewards. [Reward regressions](../tests/test_expedition_rewards.gd) exercise capacity overflow, partial tank recovery, malformed rewards, rollback, duplicate submissions and Continue. No new encounters or story branches are added.

The current demo is a 10-15 minute Act I run: Haven Dock -> travel, events and battles -> trade/refuel/refit at stations -> Leviathan Protocol broadcast -> Bastion Warden at the Bastion Gate -> Demo Complete screen with score. [Demo tests](../tests/test_expedition_demo.gd) play the whole route headlessly without injected credits or forced outcomes.

- **Content** lives in [expedition_locations.json](../data/expedition_locations.json) and [expedition_events.json](../data/expedition_events.json). Events trigger by cumulative `distance`, entering a `zone` circle, `arrival` at a location, or `start` (the one-time charter briefing shown by New Run only). Each event has 1-4 options whose `effects` may grant/charge credits, fuel, research RP, fractional hull damage, a detour, a flag that unlocks gated locations (`required_flag`), discoveries, or start a `combat` (`template`, `row`, `strength`, `asteroids`, `credits`). `complete` marks the finale.
- **Navigation** happens on the Map: select a discovered location and press Engage in the header, GO TO beside it (RESUME for a remembered detour), or double-click it. Courses can change at any time, including mid-flight, from the fleet's current position. Engage without a destination opens the Map.
- **Arrival** does not open an informational dialog or switch tabs. The existing Fleet station art and docking feedback show arrival; contextual services appear in the Map/Fleet side panel. Map offers exact-price Repair All and Refuel plus Shipyard; Fleet offers Repair All and Refuel alongside its existing ship controls. Refuel is not repeated in the footer while a contextual panel is available. Face <event> keeps unresolved arrival encounters reachable on both Map and Fleet. Actions disappear on departure and return on docked Continue, independent of the transient arrival notice. Arrival never forces a destination choice or holds the simulation. Failed repair/refuel saves leave gameplay resources unchanged, pause on save error and expose the existing Retry Save control; unaffordable/unavailable services remain disabled.
- **Game speed** is retained across events, arrivals, battles, research completion and repairs; interruptions pause, they do not reset to 1x.
- **Combat** uses the existing battle scene Dragon Warrior-style: the choice is committed with its generated encounter, a shutter/flash transition opens `auto_battle.tscn`, the report returns to the expedition at the same position, and the retained route resumes. Encounters key on `expedition_event_id`, settle once, pay credits plus research points (2 + row) to the current research focus on victory, and leave unbeaten arrival encounters at their location for a later attempt. `strength` reuses the Swarm hull/shield/damage scaling; draft values are tuned so early fights scratch the fleet, mid fights need repairs, and the Warden needs a refit. A no-damage stalemate withdraws after 30 seconds, and any engagement disengages after 3 minutes, so fights never strand the UI or drag on; a withdrawn arrival encounter can be faced again from its contextual side-panel action.
- **Research** accrues continuously from distance travelled (lab RP/day x travel days, 40 NU per day draft), never while stopped, docked or fighting. Successful completion displays a wide nonmodal banner below the command header for five seconds, preserving speed. It uses the supplied `Popup_GameTips` frame with nine-patch borders (to keep a wide toast rather than the source's tall dialog shape), science icon, full technology name and the same effect summary as the research tree. Committed bank, event and battle rewards also enqueue completion; the UI-only queue survives return from battle and ordinary tab refreshes, but Continue clears historical notices. Banners queue rather than replace one another, fade in/out, use existing sound preferences and never intercept pointer input. Failed saves produce no completion banner.
- **Self-repair** heals living hulls by each chassis' `self_repair_hp_per_second` during unpaused, non-combat simulation time, including while docked. Paid repair stays the instant alternative.
- **Trade** loads holds/cabins when leaving a trading port and delivers at the next different trading port; loads returning to their origin stay aboard. The starter Transport carries a Cargo Hold and armor plates on every mount a plate fits.
- **Expedition instruments** show separate fleet-wide cargo and passenger carried/capacity totals on the Map's left panel, derived from installed equipment loads, not occupied bay counts. Boarding feedback reports goods/people separately. Delivery, course changes, Continue and failed-save retries refresh the totals; the panel placement remains provisional pending new UI art. Fuel appears once in the footer, and the default summary no longer lists traveled distance or visited count.
- **Text reduction** keeps destination names, costs, access restrictions and orders. Visited markers replace repeated "Visited" text, and the short Map tutorial disappears after setting a course (or with Tutorials disabled). Course/refuel/full-repair state changes no longer produce redundant prose announcements; boarding, delivery income, research completion and errors remain explicit. The research sidebar describes travel-distance accrual rather than the retired on-arrival preview. The charter describes fitted ships/loadouts, and event choices expose known hull penalties alongside rewards.
- **Instrument feedback** acknowledges committed deliveries with exact +credits and the shared coin icon below the wallet for 1.6 seconds, not a centered prose toast. Cargo/passenger source readouts pulse for 0.8 seconds while their quantities clear and capacities remain. Successful refuels pulse the exact fuel value; paid repairs and automatic fleet-repair completion pulse hull condition readouts. These cues use the shared theme, respect existing sound preferences, ignore pointer input and retain their lifetime across ordinary screen refreshes. They do not alter layout, pan/zoom or saves. Failed saves never emit these success cues; explicit errors/retries remain. Research completion still retains its named notification.
- **UI building blocks** (buttons, labels, dialogs, toasts) live in [ui_kit.gd](../scripts/ui_kit.gd); encounter, rescue and run-end dialogs all use it, and the run-end dialog sits above every other layer. Ordinary arrival uses existing panels, not a dialog.
- **Ship shop** (Buy Ships) shows each shipyard's own `chassis_stock` in a seeded order (with `featured` items first), limited to the cards that fit, so it never scrolls. Ships are sold fully fitted with their default loadout.
- **Ships roster** is a grid of ship sprites with hull bars in the Ships tab; the Fleet tab has no list, and double-clicking a ship sprite opens it in Ships.
- **Docked Fleet scenery** uses the supplied mapped `assets/environment/space_station_large_d.png` station, rotating once per 30 real-time seconds as a cosmetic animation. It emits a soft warm light onto nearby mapped ships and disappears, along with its light, when departing. Station position/scale follow Fleet pan/zoom; it does not intercept selection. Shared mapped-surface ambient lighting is reduced to keep space darker while preserving directional, cursor and combat lights; UI text and unmapped artwork are unaffected.
- Fleet view refreshes retain the station's cosmetic rotation alongside pan/zoom, so releasing a formation drag or changing selection does not reset its angle. This transient view state adds no checkpoint fields.
- **Map** shows discovered locations, live fleet position/heading, planned route and detour, and details (distance, fuel, ETA, services) for the selected location. Players estimate fuel range from fuel levels and trip costs; there is no fuel-range circle or calculated range readout. All act regions share the same space background, without region tinting, shading or boundary lines; destination access restrictions still apply.
- **Map service symbols** show each station's declared shipyard/refuel/trade capabilities above its art, in a consistent order. Shipyard reuses the repair-tools artwork, trade uses the credits coin, and refuel uses a conventional line-drawn pump because no supplied fuel icon exists. A compact named key at the lower left of the map uses the same rendering, so meaning never depends on a tooltip or color alone. Badges remain legible at the existing zoom levels, keep source texture proportions, and reserve space in destination-label placement. Displaced names have thin leader lines back to their location; these are label connectors, not route or reachability overlays. POIs do not gain station services. Visited checkmarks, destination names, selected-trip costs/ETA, locked restrictions and map input remain unchanged; no automatic reachability overlay is added.

### Placeholder assets

Missing art renders as a solid pink square and missing sounds play `assets/audio/sfx/dialogue_type.mp3`, both from [placeholders.gd](../scripts/placeholders.gd). Search for them to replace:

- Equipment without catalog `art` (lasers, shields, thrusters, missiles, etc.) shows pink in stock, shops, fitting, fleet and battle views.
- POIs and the Bastion Gate use pink on the map and as the stopped-location backdrop; encounters with an empty `art` path show a pink portrait.
- `AudioManager.PLACEHOLDER_SFX` lists cues without dedicated audio: dock, depart, refuel, research_complete, repair, loot, alarm, sell and demo_complete.

### Fleet ammunition

New runs begin with 30 missiles. Any docked station sells packs of 10 for 50 credits, through a quoted footer action available on every management tab. No ammunition can be bought in flight, at POIs, during combat or after the run ends. Existing derelict salvage choices recover 6 missiles directly or 12 after victory. Prices, initial supply and pack size are draft constants in [GameState](../scripts/hangar_state.gd); the weapon cost is explicit `missiles` metadata in [slot_equipment.json](../data/slot_equipment.json).

Every Missile Rack projectile costs one missile from the same fleet pool. If fewer than three remain, a rack fires only the missiles available. Empty racks stop firing; guns, beams, point defense, enemy weapons and finite carrier sortie allowances retain their existing rules. The footer and battle header show the exact remaining supply; fitted-part details show missiles per salvo. The supply is fleet-owned, not tied to equipment UIDs, so refitting or losing a launcher never replenishes it.

Purchases, salvage and battle settlement persist ammunition with credits, hull, loads and rewards in the same atomic checkpoint. Victory, defeat and withdrawal all commit expenditure; a later attempt starts with the reduced supply. Failed saves leave live saved-state ammunition unchanged and expose the existing retry flow. As with hull and encounter progress, Continue during a pending battle restarts the complete encounter from its last committed deployment and ammunition, rather than restoring an in-progress fight. Existing physical checkpoints without the optional `missiles` field remain readable and load zero, without fabricating supplies. [Ammunition tests](../tests/test_fleet_missiles.gd) cover partial salvos, shared consumption, empty launchers, other weapons, deterministic replay, purchase pointer input, three-resolution UI, failure rollback, overflow, Continue and all settlement outcomes.

## Expedition station services

The header's topmost center recess holds compact Pause/Play/Fast Forward controls; the lower center recess holds Engage/Change Course or the in-flight destination name and remaining NU. Map/Fleet/Ships are reduced to 72 x 27 logical units and raised alongside Research toward the top rail, ready for replacement button art. Selecting a map destination only inspects/prepares it. Engage commits the selected route and clears user pause atomically, retaining the last requested speed; without a selected/active destination it opens Map. An existing paused route resumes at its previous speed. Selecting a new destination while cruising offers Change Course; without a new selection, the lower recess is an arrival readout. The existing map GO TO/double-click shortcuts use the same Engage path. Mandatory encounter/save-error pauses are not bypassed. Fuel, station refueling and save retry remain in the footer.

Every management tab shares the supplied `top_bar.png` command header, replacing the earlier `element_1.png` trial: Map/Fleet/Ships on the left, Pause, Play (1x) and Fast Forward (10x) icons in the center recess, research and wallet/settings on the right. [The header](../scripts/command_header.gd) keeps the speed controls centered over the complete artwork. Matching `bottom_bar.png`, `left_panel.png` and `right_panel.png` frame the footer, roster/expedition summary and details respectively. Bars derive their heights from width; side panels derive their widths from the remaining body height. All four images scale uniformly without cropping or nine-slicing (pixel-rounded layout can leave a subpixel edge margin). Theme variations supply the frame textures and proportional content insets; dialogs and shops are unchanged. [Mapped frame rendering](../scripts/ui_art_frame.gd) uses cached diffuse/normal/height/specular/occlusion maps through `SurfaceArt` on separate background sprites, keeping text and controls unlit. Height is retained in the normal map alpha; the orthographic view does not displace the artwork. Longer side-panel content is wheel-scrollable without visible scrollbars, so refit options remain reachable at small sizes without stretching the frames or enlarging the screen. The Ships details area reserves the same 96-pixel height for ship and part selections. Source art is unchanged; `element_3.png` has no assigned placement yet. There is no Clear button, destination dropdown or travel-control overlay over the Fleet canvas. Fuel, refueling and save retry remain in the footer. Play/fast-forward clear only user pause, never mandatory interruption/save-error pause. Travel remains live when changing management tabs.

All four frames [slide](../scripts/panel_slide.gd) from their nearest screen edge (header above, footer below, side panels left/right) in 0.18 seconds. Frame artwork sits flush to that viewport edge, with no outer margins or vertical inter-frame gaps; reclaimed space makes side panels roughly 8% larger while retaining their aspect ratios. Pixel-rounding slack is placed away from the aligned edge. Visible text, equipment/resource icons or controls make a frame relevant; decorative frame art alone does not. Empty frames translate offscreen and become non-interactive, while their layout space remains reserved to preserve canvas geometry and pan/zoom. Navigation/time and fuel/save controls keep the header/footer present while needed. Restored content reverses an unfinished exit from its current position. Each entrance plays `assets/audio/sfx/panel-open.mp3` through the existing SFX bus and volume settings; routine content updates do not restart the slide or sound.

Courses use destinations selected on Map (see above). Engage commits the route, any departure cargo and clearing user pause atomically; a failed save leaves route, fleet and credits unchanged and offers retry in the footer. Mandatory event/save-error pauses remain intact. A manually stopped route is not treated as an arrival. Continue checkpoints user pause while retaining position and requested speed, so resuming the game never starts unacknowledged movement. Saves from before this change that still carry a pending destination-choice flag clear it on the next course.

Buying ships, refits, part swaps, salvaging ships and paid repairs require docking at a station whose declared services include `shipyard`. Refueling requires the separate `refuel` service. The actual expedition state and station position determine access, never the old current-node value. A settlement can refuel without offering a shipyard; stopping or pausing in space, reaching a POI or passing a station does not grant docking privileges.

The backend validates service access before mutation or saving. Unavailable controls retain the existing layout with a short reason. Leaving a shipyard closes the ship shop and salvage confirmations and disables refit buttons with a reason; arriving restores applicable actions in place without rebuilding the Fleet view or resetting its pan/zoom. Equipment/ship inspection, research focus and formation edits remain available underway. User pause permits docked services; combat and save-error pause block them.

Run [the baseline](../tests/run_baseline.ps1), optionally with `-Native`, using its isolated APPDATA. [Station-service tests](../tests/test_expedition_services.gd) cover access, unchanged state on rejection, Continue, refueling-only stations and UI cancellation/restoration.
[Arrival tests](../tests/test_expedition_arrival.gd) cover required choices, Continue pause, station/POI reloads and failed-save/retry transactions in headless and native runs.

## First travel interruption

The [event catalog](../data/expedition_events.json) begins with a derelict signal at 80 cumulative travel NU; the demo slice above adds zone, arrival and combat events through the same admission path. It interrupts cruise on any management tab. Movement and fuel clip at the trigger regardless of speed; the simulation returns to 1x and holds an encounter-specific pause until the player chooses. This required decision has no dismiss button. Existing user and other mandatory pauses remain independent.

Continue Course retains the current destination. Investigate routes from the current position to the derelict POI and remembers the original destination. At POI arrival, the field's own salvage event plays first, then returns to the existing nonmodal view; on the Map the original destination offers RESUME, and any explicit course clears the saved return target.

The pending decision is committed before the modal appears; the choice and one-time receipt are committed before it closes. Admission or choice save failures roll back or retain the pending decision with explicit retry feedback. Continue restores unfinished decisions and detour return targets. Physical checkpoint validation rejects unknown pending events and unavailable return destinations before applying state.

[Signal tests](../tests/test_expedition_events.gd) cover speed/frame independence, exact distance/fuel clipping, independent pauses, duplicate submissions, fuel priority, combat deferral, failed saves, reloads, ship identity and real pointer choices. The baseline includes headless and optional native coverage at 640x360, 1280x720 and 1920x1080.

The Swarm and environment regression suites retain historical campaign transaction/combat coverage without restoring graph-travel or Relay controls to the expedition Map. Map inspection must not mutate expedition routes or present old node conditions as current journey hazards. Combat still validates its frozen environment and physical asteroids. Battle Settings layout coverage includes the existing Tutorials switch and Quit to menu row.

## Ownership and transactions

New-run formation is a flat-topped triangle: flagship at `(0, 0)`, Fighters
at `(-1.25, -1.25)` and `(1.25, -1.25)`, Transport behind at `(0, 1.1)`.
This applies to all flagship choices before the initial atomic save.
Continue and player formation edits retain their saved positions.

- Each chassis has fixed mounts with exact S/M/L/XL size matching and the owner's explicit per-chassis category restrictions. General mounts accept any matching-size equipment. See [MOUNT_RULES.md](MOUNT_RULES.md).
- Equipment has a unique inventory ID, with no component integrity or condition. A mount references that instance; free transfers move it between ships or stock. Replacing an item returns the old item to stock. Only the ship's hull takes persistent damage.
- Buy ships/equipment at inhabited shipyards. Research unlocks equipment purchases/fitting. Winning a battle also awards one deterministic, usable equipment instance. Loot is committed with the battle outcome and cannot be claimed twice.
- Credits pay for purchases and whole-ship repairs. Stock equipment sells for half its catalog price; salvaging a non-flagship chassis requires confirmation and returns equipment to stock. The flagship cannot be salvaged or bought a second time. Fleet is the first tab; fitting is under Ships. See [the playtest UI changes](UI_PLAYTEST_POLISH.md) for group selection/movement, Repair All, space backgrounds, map flight and supplied module art.
- New Run chooses Defensive, Civic, Research or Combat flagship in a themed artwork/stats carousel. Draft command budgets are 16 / 20 / 12 / 16 respectively. Each run starts with 700 credits, exactly one selected flagship, an empty Transport and two Fighters. The flagship receives two Mini Turrets and Lab I; Fighters receive two turrets each. Standard chassis consume command points; all owned ships deploy. No reserves or deployment-capacity system.

Flagship bonuses are chassis-local: Civic earns +20% cargo/passenger delivery income; Research produces +25% installed-lab RP/day, frozen at departure; Combat cycles weapons +15% faster, additive with magazines, and subtracts one damage from every hull hit after shields (minimum zero). Defensive has 40 shields (two generator equivalents, including doubled mass/recharge) and the same one flat hull damage reduction as Combat. Other flagships have 20 shields. The existing `flagship_basic` ID and artwork are preserved for saves. Selection uses the existing saved chassis ID; Continue never creates starter copies. Failed New Run saves roll back the old run and surface an error inside the carousel.

The art-to-mount maps, prices, chassis hull/mass/thrust and command costs are draft tuning in `data/slot_chassis.json` and `data/slot_equipment.json`. Defensive, Research and Combat have eight mounts; Civic has ten. Defensive has two fixed level I shield equivalents; the others have one. Original artwork is unchanged. Engines are implicit; command-center mechanics are covered by hull. No built-in or fitted equipment has separate health or damage. All equipment stays active until hull drops strictly below zero; zero hull remains alive. Shields absorb damage first, then the entire remainder damages hull. Repairs restore surviving hull for the rounded-up missing hull amount in credits; destroyed ships cannot be repaired. The Fighter has +30% weapon damage and 20% per-weapon-hit dodge; direct/environmental/ability damage does not dodge. No slot bonuses or legacy adjacency buffs are applied; unsupported items are omitted from active purchases/research grants. Repair drones retain finite reserves but heal hull; Nanoforge/Renewal II are deferred because component rebuilding no longer applies.

Shop chassis/equipment and loose stock rows open read-only item details in the right panel. Click elsewhere to restore stock; the green plus is the sole shop purchase action. Chassis descriptions show stats and bonuses, not mounting-point lists or built-in shield-generator prose. Shield Generator I supplies 20 shields, reflected in the ship's shield stat; this applies to installed generators, with two equivalents supplying Defensive's 40 shields. The selector labels command as Command Points. Equipment inspection retains size/category and effects/rates. Stock filters persist while inspecting, and installed-equipment drags restore the full-panel unequip target. The starter removes incompatible old equipment; previous incompatible physical layouts are rejected, not converted or rewritten.

Purchase inspection uses the supplied `Progress_Cp` / `Progress_Cp_Bg` comparison bars for hull, maneuverability, mass and shields. Maneuverability consolidates speed, acceleration and turn rate using their chassis-wide means as weights; average base maneuverability scores 50. Thrust/mass feed those mechanics without double counting. Each comparison uses all base chassis as its reference range, linearly mapping minimum to 10% fill and maximum to 100%; real outfitted/damaged values are clamped to that display range without changing state. Default Fleet/Ships details instead use the hull bar as actual current/max condition, with no 10% minimum; zero/negative hull shows an empty bar while retaining the exact rounded value. Mass and normalized maneuverability stay in purchase inspection, not routine details. Shield values describe available capacity, not persisted combat charge. Cargo/passenger readouts show actual carried quantities against installed capacity; delivery clears quantities, not capacity. Selected-part names, size/type and effects appear once in their detail area, with no duplicate effects in the refit options. Ship-description numbers are rounded integers; calculations retain full precision. Equipment has no HP/condition UI. Engine/command-center descriptions are omitted. See [MOUNT_RULES.md](MOUNT_RULES.md).

## Tutorial preference

Settings includes an Enable Tutorials switch using the shared on/off artwork.
It defaults to enabled for new and existing settings files and persists as a
global preference, separate from run saves. Tutorial content is not yet added;
future tutorial flows can check `GameState.tutorials_enabled`.

## Node environments and asteroids

Physical combat collision uses cached alpha-derived sprite polygons rather than
bounding boxes or damage radii. Player ships use chassis artwork only, at their
actual flagship/escort scale and heading; installed equipment does not enlarge
the collision shape. Alien variants use the size and rotation of their displayed
artwork. Each asteroid uses its own 32 x 32 atlas-frame silhouette. Mini Turret
bullets use their rotating bullet sprite; other shots use the visible projectile
head, excluding cosmetic trails, glows and particles.

Projectile polygons are swept across each movement step to catch fast shots and
place impacts at first surface contact. Asteroid impact damage/separation and
manual battle targeting also use the same silhouettes. Existing movement
clearance, sensor/range and area-effect radii remain gameplay heuristics, not
physical hit shapes. This does not add friendly fire or ship-to-ship ram damage.
No collision geometry is written into saves or source artwork.

Each node's conditions are generated independently from campaign seed and node
ID: asteroid density (Clear/Sparse/Medium/Dense), solar intensity (50-150%,
where 100% is baseline) and nebula presence. Ports and opening encounters stay
clear. Map details show current and selected destination conditions; these
describe the destination, not an additional transit battle.

Combat densities create 0/3/6/9 deterministic asteroid roots. The physical
battle context now passes the frozen field into the existing AsteroidField
simulation: rocks drift, collide with either faction, intercept shots and
fracture when destroyed. Asteroids are neutral hazards, not required hostile
objectives. Supplied `assets/environment/asteroids_small_d.png` and its normal,
height, occlusion and specular maps render the atlas with nearest filtering.
No extraction, mineral rewards or mining equipment is enabled.

Solar and nebula conditions are ambient metadata only for now; they do not
change weapon output, sensors or lighting. Future equipment can read the
battle's shared `environment` dictionary. Conditions and starting rock records
freeze in the existing encounter snapshot at departure. Continue/retries reuse
that snapshot; visual activity and live asteroid damage never rewrite it.
Older physical saves without environment metadata remain valid and retain
their frozen asteroid fields. Unvisited nodes regenerate from seed without
adding separate starfield/background save data.

`test_node_environment.gd` covers deterministic generation, density counts,
JSON validation, departure/Continue, physical battle wiring, drift/collisions,
shot interception, no material payouts and native mapped rendering.

## Battle outcomes and run score

Shipyard inspection uses the framed side panel's existing wheel scrolling rather
than a nested zero-height scroll viewport. Clicking its contents keeps inspection
open. The fitted purchase price matches the shop quote, rather than displaying
the bare chassis price as the amount payable.

Battle music starts immediately when entering combat, alongside the opening flash/black-shutter transition, rather than waiting for the battle scene to load. Warden encounters start the boss track at the same point. Scene initialization retains the playing track without restarting it.

Battle controls offer Pause, 2x and 5x speed. Speed toggles are mutually exclusive;
turning off either restores 1x. Pause clears fast speed, while choosing a speed
unpauses. The selected speed persists in settings (older 2x preferences still
load), and Settings pauses all speeds. Simulation continues to use fixed ticks;
finishing-shot slow motion multiplies the chosen speed. Retreat is no longer
offered in the battle UI; shared withdrawal/replay mechanics remain unchanged.

The battle header shares management's mapped, uniformly scaled top-bar artwork
and quick entrance from the viewport edge. Compact pause/play/fast glyphs reuse
the management renderer; the speed buttons retain adjacent exact 2x/5x labels.
The lower recess holds the full encounter objective, including Warden exposure
and lance countdowns, with wrapping rather than truncation. Conditional repair,
rebuild and carrier readouts flow below the frame without fixed-position overlap.
Header clicks remain UI input, never battlefield targeting or camera gestures.
Special encounter orders read "Destroy Warden" or "Clear escort fleet"; Protected
appears while live pylons protect the visible body. Existing pylon links,
exposure ring and lance corridor carry the spatial cues. Exposure/lance seconds
and ordinary wave/target timing remain exact; victory rules are unchanged.

The left side of the battle header shows a box and person with exact `xN`
carried-goods/passenger counts. These use installed equipment-instance loads
on deployed living ships, not bay counts, capacity or the entire owned fleet.
Zero hull is alive; destroyed hosts contribute no loads. Once present, a counter
stays visible at zero after a loss. Battles without that transport equipment omit
its counter. These are transient instruments, never new save fields.

When existing abilities are available, the pressed full-name action identifies
the current targeting mode instead of persistent "Click..." instructions. Scan
uses broken circular arcs, Seismic Cut a cut diamond, Ion Pulse brackets and a
bolt, and the retained Gravity Well preview inward chevrons. Reticles stay a
fixed screen size while range/area circles follow world zoom. Invalid targets
add an X as well as changing color. Validity updates with source movement and
selection; source loss or an automatic cast's cooldown cancels stale targeting.
Exact cooldown seconds, source selection, Auto, Pause Aim and existing cancel
controls remain. Failed saves explicitly say "Save failed", retain targeting and
do not spend cooldowns. This UI pass does not make deferred abilities/equipment
available in physical runs.

Victory uses the supplied Victory background, badge, rays, light line and title,
with shared aligned Damage / Deflected / Repair HP columns. Fleet losses appear
first, followed by greatest hull repair need, before opposition summaries. Full
names/art and explicit DESTROYED status remain; zero values are shown and wrecks
have no repair amount. Repair HP is hull damage, not a credit price. Names use
the flexible first column; damage is no longer an unbounded segment flow.
Loot/rewards and surviving-hull repair quotes retain their settlement behavior.
The result overlays a dark backdrop, while the shared top-right Settings remains
available. Its independent auto-pan and auto-zoom toggles use Switch_Off/Switch_On with preserved aspect;
volume settings remain sliders.

Flagship destruction goes directly to an opaque-black, red warning Game Over
popup using GameOver_bg and Title_GAMEOVER. Accept Defeat (or the shared X)
returns to the main menu after the defeat checkpoint commits. A failed save
keeps the settlement error/retry path instead of displaying a settled result.

Only runs started after this update have a score. Existing physical version-2
saves remain loadable and display an explicit score-unavailable message; past
income/damage is not guessed. The optional validated `score` checkpoint object
stores cumulative Swarm damage and earned credits alongside the rest of the
atomic run state:

- 100 points per completed research project, excluding Foundation.
- 1 point per 10 player-fleet damage to Swarm enemies (including shields and
  carrier sorties, counted once; no neutral-target or neutral-source damage).
- 1 point per 10 gross credits earned from battles, cargo/passengers, quests,
  equipment sales and chassis salvage. Starting credits are excluded. Spending
  and casualty fees do not reduce earned credit totals.
- 20,000 bonus points for defeating the final Leviathan. Final victory also
  shows the score breakdown.

Fractional damage is retained; damage/credit point subtotals round down.
Settlement failures/retries, repeated calls, sales and arrivals cannot duplicate
score income. Continue preserves the totals. The Game Over breakdown shows both
the source totals/weights and their point contributions.

## Surface lighting

Shield absorption flashes a fading, form-fitting blue silhouette glow on player
chassis and alien ships, not a circular shield ring. Original artwork stays
visible above the glow; cached white alpha masks preserve transparent cutouts
and rotate/scale with the ship. Shared legacy hull rendering retains its existing
form-fitting hull outline.

Each visible projectile also has a tight 7-world-unit emissive-looking halo:
layered red/green light and a bright warm center, drawn beneath its original
bullet/tracer artwork. This covers Mini Turret sprites and all other projectile
weapons, follows interpolated positions and camera zoom, and uses the same
visibility culling as the bullet. Existing surface lights remain separate.

Shots shed five tiny fading sparks. Bullet halo opacity is softened by 25% while
retaining its small radius. Target and asteroid collisions create a
0.22-second orange/red/white burst with fifteen outward sparks and a short bright
core. Effects use simulation time, so battle speed and pause apply consistently.
Impact storage is capped at 96, hidden/offscreen contacts are not retained, and
expired effects are removed. Cosmetic variation never uses combat RNG and
does not change damage, collision, saves or replay state.

Surviving player chassis emit tapered blue/white exhaust streams from
chassis-specific engine anchors (12 tiny fading particles per nozzle). Origin,
spread, particle size and plume length all follow the displayed sprite scale,
including quarter-scale escorts. Battle exhaust responds to movement speed and
rotates with the interpolated ship heading; stationary ships and aliens emit
none in battle. Fleet and Ships views animate continuous preview thrust, including
pan/zoom and equipment fitting. Destroyed ships never emit exhaust. Exhaust
uses simulation time and visibility filtering, without combat RNG or saved state.

The supplied map sets under `assets/chassis/`, `assets/equipment/`, `assets/environment/` and `assets/aliens/` use `_d` diffuse, `_n` normal, `_o` occlusion, `_p` height/parallax and `_s` specular. `_v` is a baked preview and is not used for live rendering. The flagship now uses `assets/chassis/flagship_basic_d.png`, the mapped version of the supplied starting flagship; chassis IDs, saves, geometry and mount anchors are unchanged.

Single Plate (S) uses `assets/equipment/plate_small_d.png`; Armor Block (M) uses `assets/equipment/plate_medium_d.png`. Both use the supplied normal, height, specular and occlusion maps through the shared cached renderer in stock, fitting/drag previews, Fleet and battle. Mount fitting preserves their proportions; catalog IDs, stats, costs, health and saves are unchanged.

Research Lab I uses `assets/equipment/research_lab_1_d.png` with its supplied normal, height, specular and occlusion maps through the same renderer. Stock thumbnails, fitted art, drag previews, Fleet and battle preserve its aspect ratio and transparency. Lab II/III use the pink placeholder art; research production, fitting rules and saved instances are unchanged.

Lab I's mount-anchor metadata doubles its fitted artwork and snapped drag preview relative to the original fit, without enlarging stock thumbnails or editing source textures. The flagship's medium `spine` mount is centered on the lower central bay at source-art position (256, 324), not the narrow spine above it; mount identity, size and fitting rules are unchanged.

Alien Chrysalis, Scout, Sentinel and Support use their supplied maps in battle and report previews; the Warden shares mapped Sentinel art and the pylon keeps its original art. The base Fighter retains its original unmapped sprite; its incomplete/deleted map set is excluded. Existing higher-tier Fighters (tiers 1/2) use Large Wing, and higher-tier Chrysalis use Large Sporeback, drawn at 1.5 times the base visual extent. This is an appearance change only: roles, names, threat costs, collision radii, combat statistics and encounter/save schemas remain unchanged. Reloading a saved encounter selects the same variant from its existing role/tier.

`SurfaceArt` caches one `CanvasTexture` per diffuse path, packing height into normal alpha and occlusion into specular alpha without changing source files. A shared Compatibility-renderer shader shades only mapped artwork: fitting, formation, stock/drag previews, shipyard chassis previews, travel and combat use the same maps. Unmapped equipment, UI text, connector lines, selection glow and backgrounds retain their existing rendering. Normals follow sprite rotation against a screen-space key light; up to eight legitimately visible explosion flashes illuminate nearby surfaces in battle. The existing top-down orthographic view has zero parallax slope, retaining height data without shifting artwork, atlas frames or interactive mount bounds.

Lighting integration validation: all 15 baseline suites and native UI checks pass. The native surface-art suite passes 74 checks, including node and immediate battle draw-transform rotation, explosion illumination, mapped asteroid atlas frames and pixel-identical unmapped artwork. Native fitting passes 227 checks and fleet/travel polish passes 51. Existing Godot renderer-shutdown diagnostics remain; no script or shader compilation errors were emitted by these checks.

The alien-art follow-up passes 188 native surface checks, 193 campaign checks, 1,242 natural full-route checks, shared battle replay and 1,184 native UI checks. These cover all six alien map sets under rotation/explosion light, higher-tier art after saved-encounter reload, unchanged snapshot data and lit report previews.

Visible bullet/projectile shots also cast small local lights (36 world-unit radius): red for player shots and green for enemy shots, following the same interpolated positions as their sprites. At most 16 onscreen/near-screen projectile lights are active, independently of the eight explosion lights. Hidden projectiles never emit light, and removed shots leave no residual light. This is rendering-only; weapon behavior and saves are unchanged. The native surface suite passes 199 checks including projectile visibility, interpolation, zoom-scaled radius, faction colors, light caps, expiry and moving/localized illumination.

The cursor casts a soft neutral light over mapped artwork across all screens, with a 48-viewport-unit radius independent of battle zoom. `UiNavigation` updates one shared shader global using normalized viewport coordinates, preserving alignment under window stretch/resizing. The light turns off outside the viewport, when the window loses focus, or while the cursor is hidden/captured. It does not brighten text, backgrounds or unmapped artwork and consumes no projectile/explosion light slots. Native surface checks cover localized cursor illumination, movement, disabling and unchanged unmapped artwork (203 checks total).

The mapped-art ambient contribution is now 25% dimmer. Directional, specular, cursor, projectile and explosion light strengths are unchanged, letting those sources stand out without dimming UI or modifying source artwork.

### Research and resource text

Single-click research cards to inspect them; double-click to Set Focus using the same prerequisite, completed/current-focus and run-state checks as the button. Focus saves remain atomic, failures use the existing notification, and either interaction preserves research pan/zoom.

The Research tab's progress bar is left aligned with current fleet production (`+X/day`) on its right. Its visual minimum is -1 so a zero-progress project shows a thin strip; actual progress, costs and saved research remain unchanged.

Visible RP/CR unit abbreviations render as inline science/credits icons at the surrounding font size, with nearest-neighbor filtering. This covers research production/details, fleet totals, selected lab effects, map arrival/reward previews, repair costs and passenger casualty fees/balances. Resource-bearing text uses the shared theme and literal text rendering, so technology names are never interpreted as markup. Repair buttons retain hover, pressed and disabled styling.

Repair and shield (including plural shields) words also use the supplied text-sized icons throughout stats, research effects, equipment/shop names, mount callouts, drag previews and battle support/report text. Stored catalog names and save data remain literal and unchanged.

The Shield Generator equipment is the exception: its complete name remains text in stock, fitting, shop, research grants and previews. Shield stat/effect labels still use the icon. Its equipment ID is unchanged.

Equipment shop rows are compact display-only cards. Only the 32 x 32 green plus on their right purchases equipment; unavailable items have no plus. Purchases refresh the open shop without changing its scroll position. Chassis purchase behavior is unchanged.

Hovering installed equipment on the ship art shows a white silhouette glow aligned to its fitted sprite, including mount-anchor offsets. Empty mounts and display-only side labels do not show this glow. Equipment without artwork uses the pink placeholder sprite and glows like any other fitted art. Sprite glows are hidden during equipment drags so compatible-target highlights remain clear.

Floating equipment names align toward the ship: right-aligned on the left rail
and left-aligned on the right rail, keeping each name next to its connector line.

Inline icons use the surrounding font height and derive their width from the source texture aspect ratio, rather than forcing square dimensions. Header/shop/report icons, inline sale coins and close-button artwork likewise preserve their source proportions.

Settings uses an embedded 304 x 246 modal (304 x 278 when Quit to menu is available), sharing the main viewport's bitmap-text pixel scale rather than a separate native window's smaller text. Audio rows and the centered Quit to menu button are compact. Every active scene has a top-right gear; battle settings pauses simulation, result-delay progression and camera updates until closed, while retaining the player's existing pause/speed mode.

Battle auto-pan and auto-zoom follow independently. Mouse dragging or WASD/arrow panning suspends only auto-pan; wheel zoom suspends only auto-zoom and retains cursor-anchored zoom. Each resumes smoothly five real-time seconds after its last manual input, regardless of battle speed. Space restores both immediately when their Settings preferences are enabled. Settings, ability aiming and finishing-shot cinematics retain their existing camera interruption behavior. Old `auto_camera` preferences initialize both switches; subsequent settings saves store independent `auto_pan` and `auto_zoom` values.

## Combat, travel and trade

### Beacon routes and Swarm Intensity

New runs retain all three acts but use a bidirectional, noncrossing beacon network with irregular beacon positions. Only connected, unlocked destinations can be reached; backtracking does not relock sectors already opened by boss victories. Route connections are plain lines rather than directional arrows. Existing physical checkpoints without navigation data continue using their original forward-only graph, encounters and tuning; no save conversion is guessed.

Swarm Intensity starts at zero and rises by one point per travel day, including backtracking and repeat departures. Time spent in menus or battles does not add pressure. The map shows current intensity and the next journey's increase. Initial tuning adds 0.5% enemy hull, shields and weapon damage per intensity point, including the Warden's existing lance and the final Leviathan encounter; no new phases or enemies are introduced. Enemy composition, rewards, telegraphs and research rules remain unchanged. First departure to a hostile beacon freezes its strength; retries and Continue retain that snapshot while further travel still raises pressure for unentered encounters. Cleared beacons do not spawn the same encounter or pay its rewards again. Operational cargo/passenger travel remains available on revisits.

Each act has a small broken-relay encounter with inline choices in the existing map detail panel. Relay its data to the marked beacon for 60 credits and a four-point intensity reduction, or disrupt the signal immediately for a three-point reduction. Choices and quest rewards settle once through the same atomic transaction as ownership, credits and travel. Active destinations have a gold ring; completed quest feedback appears at its destination. Quest data is not a physical equipment load. The pressure rate, strength multiplier and quest rewards are drafts for route playtesting and V4 tuning.

`test_swarm_navigation.gd` verifies deterministic noncrossing geometry across 128 seeds, bidirectional travel, pressure, frozen retries/Continue, one-time encounters/quests, rollback, malformed-data rejection and native event layouts at the three supported resolutions. Natural playthrough policies explicitly choose forward progress now that backward routes exist. Science policies reserve the actual Lab III purchase price before buying optional hulls and take bounded research detours before the final approach when necessary, trading increased Swarm Intensity for Lab III completion and a real purchase/refit opportunity; checks require an operational Lab III alongside existing labs at a combined four RP/day or more.

Validation: all 16 baseline suites pass, including nine natural combat/trade/science campaigns reaching final victory (126 battles). Final native checks pass for swarm navigation, 2,106 hangar UI assertions and 157 polish assertions. At 640 x 360, the single encounter's Travel and both event choices fit inside the existing panel; scrolling is available only for longer accumulated quest content.

Chassis images appear in hangar, formation, map preview, battle and reports. Equipment weapon mounts use the authored image positions. Shields absorb damage first. Unshielded component hits split damage equally between component and chassis; bare hull hits damage the chassis. Chassis survives at exactly zero and dies below zero; losing its command center also destroys it. Flagship destruction ends the run even when escorts remain. Repairs restore surviving ships and their installed hardware, without resurrecting destroyed ships.

In Fleet and battle, non-flagship chassis render at one-quarter width and height; the flagship retains its existing scale. Fitted equipment, formation hit targets/selection glows, battle damage markers and weapon launch positions follow that presentation scale. Formation spacing, combat collision radii, ship statistics and saves are unchanged. Ships fitting continues to fit each chassis independently to the available editor area.

Operational Lab I / II / III produce 1 / 2 / 3 RP/day respectively; there is no fleet baseline. Expedition travel earns RP from distance traveled. Historical graph journeys retain their frozen departure yield and settle it once on arrival. Unfocused output and project-completion overflow accumulate as fractional `research_points` in the same atomic checkpoint as project progress. Choosing a focus automatically applies only whole stored RP to that project, rounded down; fractions stay banked until they combine into another spendable point. Science balances, project progress and reward quantities display whole RP; time and production-rate calculations retain their precision. Historical fractional project progress moves its remainder to the bank on allocation, preserving total earned science. Old checkpoints without a balance load as zero; existing balances are preserved. Travel, event and battle rewards use the same allocation path; battle duration itself yields no RP. With no focus, the Research button shows the spendable integer balance (or Choose Research for an empty bank), refreshed without rebuilding the canvas. The single pannable tree uses inline details/focus, and the production panel lists lab mix and rates.

Fleet, Ships and Map tabs align left near the top rail and use `Btn_CharacterMenu_n`/`_p`, with lighter hover and distinct pressed states. These three tabs are 72 x 27 viewport units, preserving the cropped artwork's natural aspect ratio. Research is a wider tab immediately before credits, combining its compact 12-pixel icon, 10-pixel technology name (without a prefix), and half-width supplied `Progress_CharacterAttribute` bar showing whole-number progress against the project's requirement. Clicking anywhere in that tab, including its icon, text or bar, opens Research. With no focus, it shows stored RP (`Choose Research` at zero), hides the bar and gently fades toward white and back once per second; selecting focus stops the pulse immediately. Long project names wrap within the Research button at narrow widths rather than clipping or narrowing the other tabs. Credits align right immediately before the Settings gear, which uses circular `Btn_RandomName_n`/`_p` artwork and opens Settings without leaving the run. The flagship roster flag is one-third its original size. Tab switches use the accept sound; roster and Fleet-art ship selection use the former tab-switch sound.

All panels and shared modals inherit the supplied nine-sliced `Panel_StoreItem` surface. Fitting callouts are frameless floating white text at the shared 10-pixel font size, with white connector lines to installed equipment. The texture is imported at half size with eight-pixel slices, retaining small crisp chamfers that fit inside the close artwork rather than protruding behind it. Shared panel/modal close controls use `Btn_ClosePanel_n` with a lighter hover tint and `Btn_ClosePanel_p` when pressed. Atlas crops remove transparent artwork padding so the visible button sits one viewport pixel from the panel's top and right edges; source textures remain unchanged. Boolean settings and shop checkboxes inherit `Checkbox_Off`/`Checkbox_On` from the shared theme, imported at 16 pixels without changing source artwork. Fleet offers only Buy Chassis; Ships offers only Buy Equipment. Each roster button toggles its corresponding embedded center panel; changing tabs closes buying. No internal mode buttons remain. Equipment buying shows the current shared stock in the right panel; purchases and sales refresh it without closing the shop. Equipment buying defaults to Only show researched on the size-filter row; the toggle persists through purchases, filter changes and tab switches during the screen session. Shop prices use the credits icon, locked items use the science icon, and the green purchase plus is shown only when the row is purchasable.

Without a single Fleet ship selected, the detail panel retains Repair All and shows the surviving fleet's total mounted-weapon DPS, operational shields, current/max hull and operational lab RP/day. Cargo and passenger capacities appear only when positive; destroyed equipment and ships contribute no operational capacity or production.

Fitting equipment labels use the shared `MountCallout` panel variation with compact padding that fits their fixed 24-pixel height. They reuse the same panel artwork without inheriting modal-sized minimum margins; frames stay inside the card bounds and full names remain clear of the chamfers.

Starting a new run fades the main menu background image to transparent during the first second of the star-warp animation. A failed transition restores the background alongside the menu. Reduced motion has been deliberately removed from Settings, saved preferences and runtime behavior; do not reintroduce it.

Horizontal and vertical sliders inherit `Slider1_bg`, cropped `Slider1` foreground and a compact 8 x 16 handle derived from `Slider1_Btn` using nearest-neighbor sampling without its glow padding. Source artwork is unchanged. The foreground crop removes the transparent left inset. Settings audio sliders retain their native range, dragging and saved-volume behavior and align vertically with their labels. Active viewports snap canvas transforms and vertices to pixels; shared bitmap UI textures retain nearest filtering.

Research selection and focus changes preserve the tree's pan, zoom and selected node through UI refreshes. Returning to Research within the same hangar screen restores that view without fitting it again. A closed diamond identifies the focused node independently of its tint; completed nodes retain their green checks and partial nodes their exact progress/cost. Set Focus remains visible for other projects; the redundant disabled FOCUSED button is omitted. The sidebar keeps lab mix, rate and distance-only accrual guidance, but does not repeat the bank already shown in the header. Effects, prerequisites, exclusive-path consequences and save errors remain explicit.

Passenger and cargo contents belong to equipment inventory IDs. A cabin boards four passengers for an inhabited destination; a hold loads ten goods when leaving an inhabited port. Inhabited arrival automatically pays passenger fares and cargo sales. Occupied hardware must deliver before being unequipped. Destroyed hardware/hosts lose their contents; passenger casualty fees settle once and can create credit debt. Repairs do not refill lost loads. No additional Port/Story or management windows are introduced.

## Runtime and persistence

- Autoload: `scripts/hangar_state.gd`, independent of the removed material runtime.
- Physical ships: `HangarShip`; combat retains the shared simulation engine while using image mounts and chassis HP.
- Campaign UI: `scenes/game_map.tscn` / `hangar_screen.gd`; actual shared inventory choices are in `hangar_canvas.gd`.
- Active research: `HangarResearch`, using a filtered catalog without extraction or undefined adjacency bonuses.
- Trade: `HangarTrade`, keyed by equipment ID rather than unstable component/slot indices.
- Checkpoint: `user://hangar_run.json`, `physical_hangar` version 2, validated and written with `AtomicRunStore` checksums, staged generations and backup recovery. Previous physical versions are intentionally rejected at the owner's direction; no conversion is attempted. Equipment instances contain no `hp`, and ship entries contain no `builtins`.

Purchases/refits/sales propose a complete state and commit before exposing it. Failed persistence leaves credits/ownership unchanged. Battle settlement commits health, lost equipment/loads, credit rewards, loot, research and location together. Pending Continue restarts the deterministic encounter from its saved departure snapshot. Support expenditure persists across withdrawn attempts. Older `run_checkpoint.json`, square/hex libraries and slot blueprint libraries are never overwritten or guessed into physical ships.

The square builder, material shop/fleet panel, blueprint-library dialog, main-menu Designer and free slot Designer screens have been removed. The disconnected material runtime is removed. Read-only checkpoint/library schemas live under `scripts/legacy/`; shared DTOs remain for archive decoding and combat regression tests. Current code uses `SaveValidation` for generic wire checks. Historical tests are preserved as text outside Godot imports. See [LEGACY_BOUNDARIES.md](LEGACY_BOUNDARIES.md).

## Validation

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_baseline.ps1 -Native`. It uses isolated APPDATA and the installed Godot console. The current baseline covers the physical game plus shared combat/research/archive readers. The earlier grid-era runner is preserved under `docs/history/run_baseline_PRE_HANGAR.ps1.txt`; its retired UI expectations are not current hangar requirements.

Hangar-specific checks cover exact fitting, physical ownership, credit charging, transfers, command limits, hull/component/built-in health, zero-HP destruction boundaries, flagship defeat with a surviving escort, repair, loaded trade/losses, malformed data, backup recovery, failed-save rollback, duplicate settlement, deterministic loot, departure research and refit timing. Native UI checks cover real OptionButton callbacks, shared X windows, no overlapping mounts, theme/focus/tooltip preferences, actual battle/report integration and 640x360 / 1280x720 / 1920x1080 layouts. Captures are in `.local/hangar/ui-*.png`.

Nine natural full-route playthroughs now pass: combat, trade and science policies across three seeds, totaling 126 battles with normal purchases, repair costs and research. See [HANGAR_PLAYTEST.md](HANGAR_PLAYTEST.md). The earlier forced-outcome traversal remains a persistence/connectivity test. Neither test establishes unfinished Brood Architect/Leviathan mechanics; those and broader balance remain in TODO.md.

Verification: the latest mount-policy pass has thirteen current baseline suites passing; the native UI suite passed 298 checks, including all six chassis at three resolutions, main-menu Continue and ranked-lab production/details. Physical-state, persistence and traversal suites passed 47, 89 and 193 checks respectively. A 13-ship refit fixture completed each transaction in under 40 ms in the recorded runs. After the mount-policy pass, static runtime resource validation found 116 references with none missing. Existing Windows certificate-store and renderer shutdown diagnostics are still emitted by this Godot environment.

Gravitic Snare / Disruption II are deferred because their old ability path is not wired into physical-ship/credit transactions. They are hidden from new purchases, research focus and loot. Previously earned research and item instances remain loadable; inactive fitted items must be unequipped before departure and can be sold. This avoids silently invalidating older physical saves.

Six core intermediates now operate in the physical model: ship-wide stacking magazines/computers, railguns, finite interceptor/bomber bays and automatic command marks. See [INTERMEDIATE_EQUIPMENT.md](INTERMEDIATE_EQUIPMENT.md) for conservation rules, exact mounts and test limits. ECM/Phase remain unfinished. The current runner has thirteen suites.

Historical (superseded by D1 loadouts): the hangar used a visible stock list and native drag-and-drop fitting, with live ship stats. Stock and shipyard equipment purchases share multi-select category checkboxes and a two-handle inclusive S/M/L/XL size range, with no search or ordering controls. Handles can meet on a single size but never cross; S through L always includes M. Historical disjoint size preferences normalize to their inclusive span; an empty historical size selection becomes the full range. Stock and all purchases are always ordered by ascending catalog credit price. Chassis buying has no filters. Slot equipment dropdowns and the unused prototype canvas renderer are removed. See [HANGAR_DRAG_DROP.md](HANGAR_DRAG_DROP.md).
