# Leviathan TODO

Current target: a medium-sized vertical slice, with UI/UX finalized before deeper content expansion. Keep the physical hangar, existing equipment and enough progression to exercise the whole play loop. Let the story drive later depth. The full-campaign backlog below is deferred, not a prerequisite for this slice.

Current model: owned chassis and individual equipment instances; credits are the only spendable resource. No square/hex building, materials, equipment recipes or construction regions. Preserve implemented content and saves; this scope change does not require deleting working systems. Optional extras remain deferred.

## Confirmed design

- Battle outcomes use supplied Victory artwork with compact report rows. Flagship loss goes directly to the black-backed red Game Over popup and Accept Defeat returns to menu. New runs score completed research (100 each, excluding Foundation), Swarm damage (1/10), gross earned credits (1/10, excluding starting credits) and final Leviathan victory (+20,000). Existing runs remain valid but unscored. Score totals settle/save atomically; see docs/HANGAR.md.

- Nine supplied chassis: selectable Original, Civic, Research and Combat flagships, plus Corsair, Fighter, Transport, Frigate and Drone. Owner-confirmed mounts and draft hull/thrust tuning are documented in docs/MOUNT_RULES.md.
- Slots require exact S/M/L/XL size matches. General mounts accept any matching-size category. Apply the explicit owner-reviewed per-chassis Offense/Defense and Civic/Tech/Defense restrictions, including Transport L utility sides. Original/Research/Combat have eight mounts; Civic has ten. All flagships have a built-in Shield Generator I; Fighter has +30% weapon damage and 20% seeded weapon-hit dodge. New flagship mounts are owner-editable catalog drafts.
- Equip by dragging owned equipment from a visible stock list onto ship mounts, between mounts, or back to stock. Stock/equipment buying use multi-select category checkboxes and an inclusive two-handle size range, no search or ordering controls, and fixed ascending catalog credit prices. Chassis buying has no filters and also uses ascending credit prices. No slot equipment dropdowns. Keep cargo/passenger space, DPS, integrity and shields visible and live. Transfers are free. Buy researched equipment/chassis at shipyards; battles also grant equipment loot. No design drafts, named blueprints or free copies.
- No functional equipment orientation. Weapons aim automatically; thrusters provide ship-wide thrust.
- Exactly one flagship, mandatory every battle. Its command budget limits the other ships; no reserves, design-family limits or old act-based deployment capacity. Flagship loss ends the run.
- Hull is the only ship health pool, alive at zero and destroyed strictly below zero. Engines are implicit and command is covered by hull; neither is described or independently damaged. Shields absorb first; all remaining damage goes to hull without splitting. All fitted/built-in equipment stays active until ship destruction, with no component condition/HP. Repairs restore the whole surviving hull. Physical saves use version 2, rejecting older versions without conversion.
- Use credits for purchases and repairs; equipment transfers are free. No material inventory, wildcard exchanges, ore/mineral payouts or refinery systems in the replacement model. Cargo goods and passengers remain distinct systems.
- Research stays one pannable tree with major branches and inline details/Set Focus. No Foundation node or grant modal. Completed nodes have a green check; partial nodes show X / Y. Research output is allocated directly to the focused project at arrival; no RP balance is stored or shown in the header.
- Travel research: (Lab I + 2 x Lab II + 3 x Lab III) RP/day times travel days, typically 2-4. Freeze departure inputs, retain project fractions/focus, settle once at arrival; discard output with no focus or beyond project completion. Battle time never generates RP.
- Node conditions are deterministic from campaign seed/node ID: Clear/Sparse/Medium/Dense asteroids (0/3/6/9 roots in battles), solar intensity 50-150% and nebula presence. Map details display conditions; solar/nebula equipment effects remain deferred. Physical battles use the supplied mapped asteroid sprites and existing drift/collision/interception/fracture simulation, without mining or material payouts. Freeze encounter conditions at departure and retain them through Continue/retries. Ports/opening encounters stay clear. See docs/HANGAR.md.
- Starhull/shared theme, minimal prose, no hover tooltips and no Tab/arrow focus navigation or focus boxes. No Port/Story buttons or duplicate fleet stats in the top bar.
- Chassis previews and owned-ship Fleet/Ships details use supplied Progress_Cp/Progress_Cp_Bg bars for hull, maneuverability, mass and shields, with integer descriptions. Maneuverability weights speed/acceleration/turning by their chassis-wide means and normalizes average base score to 50; backend physics stay unchanged. Compare all six base chassis per displayed stat, linearly mapping minimum to 10% and maximum to 100%. Equal stat bounds require balancing review, not a silent fallback. No component HP/condition UI or implicit engine/command-center descriptions.

## Hangar migration

- [x] S1/C1: Preserve the supplied art and typed mount catalog; retire hex/square editors and prototypes. The prior standalone slot Designer is now retired too.
- [x] S2: Replace the actual campaign with a physical hangar, shared instance inventory, free transfers, shipyard purchases, equipment loot, credits-only repairs/sales and salvage (now confirmed in the UI). Start with the supplied flagship; enforce command and no-reserve rules.
- [x] S3: Render actual chassis in hangar/formation/map/battle. Current owner simplification: persist whole-ship hull only, shield-first full hull damage, zero-HP boundary and mandatory flagship defeat. No component/built-in integrity; defer Nanoforge/Renewal II rather than inventing component-rebuild replacements. Defer undefined slot/adjacency bonuses rather than selling inactive effects.
- [x] S4: New atomic physical-run checkpoints, unique ownership, backup recovery, save-failure rollback, exactly-once battle settlement, travel research and equipment-instance trade loads. Preserve old save namespaces. The active runtime no longer inherits the material GameState; removed embedded builder/library/free-Designer UI.
- [x] S5a: Native dropdown/window checks at 640x360, 1280x720 and 1920x1080; all-act travel/settlement traversal; six natural opening fights; load/repair/loss/refit checks and interaction timing. See docs/HANGAR.md for evidence and limits.
- [x] S5b: Initial catalog/mount opportunity-cost review and nine natural full-route runs (combat, trade, science; three seeds; 126 fights). No free credits/research or forced outcomes. Rank II/III labs now produce 2/3 RP/day, with matching UI and preserved pending yields. Defer the inactive Gravitic Snare ability purchase/focus/loot while keeping older research/items readable and removable. Current content is traversable; broader balance and unfinished bosses remain milestones 60/65/67/70. See docs/HANGAR_PLAYTEST.md.
- [x] C2: Remove the disconnected material GameState and unused builder/formation/upgrade/window code. Preserve 46 retired test/capture scripts as text outside Godot imports. Isolate historical checkpoint/economy/library schemas under scripts/legacy, remove archive writers and retain read-only square/hex/prototype recovery. Extract shared SaveValidation and skip square catalog/animation initialization for physical previews/battles. Nine baseline suites, 66 archive checks and 289 native UI checks pass. Shared DTOs remain for decoding/combat regressions; see docs/LEGACY_BOUNDARIES.md.

The playable entry is NEW RUN -> Fleet; equipment fitting is under Ships. CONTINUE resumes physical hangar checkpoints; old material runs remain separate. Shipyards sell physical ships, not bulk blueprint construction orders. Passenger/cargo trade remains core. RP remains travel-generated progression. Slot bonuses and adjacency equipment stay deferred.

## Completed intermediate batch

Original milestone IDs are retained for historical cross-reference; all implementations must use slots and credits.

- [x] 56a: Magazine/Railgun, Flight Deck/Bomber and Uplink/Computer are physical, research-gated equipment. Magazines/computers support all host weapons and stack as requested. Finite UID-based carrier reserves persist across retries/transfers; craft have payload/lifetime/entity limits, point-defense counters and source-loss handling. Command marks respect visibility. 143 carrier checks, 155 intermediate checks, six natural Act II combat fixtures and the eleven-suite baseline pass. See docs/INTERMEDIATE_EQUIPMENT.md; broad tuning remains 61/67/70.

## Active priority: medium vertical slice and UI/UX

Do these next, in order. Use existing content; add only what is necessary to make the slice understandable and complete. Do not continue filling the equipment tree or all three acts first.

- [x] V1: Current UX audit concluded with the owner (2026-11-01). Native reviews covered the core screens and supported resolutions. Further findings can be raised periodically; do not reopen a broad redesign as a prerequisite for V3.
- [x] V2: Current owner-directed UX corrections completed: shared pixel-crisp theme/art, fitting callouts and direct-art interactions, shops/stock, sliders/range filters, research camera preservation and combined Research/status tab. Preserve these interactions and handle future UX fixes incrementally.
- [ ] V3: Shape a coherent representative route using current content: shipyard purchase/refit -> travel/research -> combat -> report/loot/repair -> another meaningful fleet choice -> a clear slice endpoint. Include passenger/cargo usefulness and a small range of encounter roles. Choose route length from playtesting; no new boss phases, full Act II/III expansion or finished story required. Keep existing full-route content/saves intact while the slice route is defined.
- [ ] V4: Tune only the slice's credits, command/mount choices, travel days and research costs so players can experience a few distinct viable loadouts without excessive grind. Use current labs, weapons, support equipment and trade. Defer exhaustive balance and new research tiers.
- [ ] V5: Verify the slice's saves/Continue, failed transaction rollback, ownership, travel/reward settlement, flagship defeat and finite resources. Profile purchases, transfers, repairs and battles; eliminate noticeable interaction stalls. Reuse existing coverage and add regressions for discovered issues.
- [ ] V6: Play the whole slice through the actual UI at supported resolutions, including readable combat/status effects and reduced flashes. Deliver a reviewable build with remaining UX issues recorded. Finalize UI/UX with the owner, then revisit content depth around the story.

- [x] V3a: Adapt new runs to a noncrossing bidirectional beacon network while retaining the full three-act campaign. Travel days raise persisted Swarm Intensity and strengthen future hostile encounters, including Leviathan; event choices can reduce pressure. Cleared encounters/rewards are one-time, first-departure enemy strength survives retries/Continue, and small relay quests use inline map choices and destination markers. Existing physical runs retain their original graph/rules. Initial pressure and quest tuning remain drafts for V4; representative-route playtesting remains V3.

Implemented playtest adjustment: applied the owner's explicit artwork-based six-chassis mount specification, draft hull/thrust tuning, fixed flagship shield and Fighter bonuses. Shop/stock clicks inspect item details in the right panel; only the green plus purchases. Catalog, fitting, saves and loot share mount rules; see docs/MOUNT_RULES.md. V1-V6 remain the active work queue.

Implemented flagship choice: New Run carousel previews four supplied flagships with stats, Command Points and bonuses, without mount listings or built-in shield prose. Shield Generator I supplies 20 shields. Budgets: Original 14, Civic 20, Research 12, Combat 16. Civic grants +20% own delivery income; Research grants +25% own lab output; Combat grants +15% additive cycling and one flat hull damage reduction after shields. Start with 700 credits, chosen flagship, empty Transport and two armed Fighters (seven unique starter equipment instances). Continue preserves saved fleets without creating starter copies; failed starts roll back and keep the modal actionable. Slots remain draft catalog rectangles for owner adjustment. V1-V6 stay the priority.

- [x] V2a (owner playtest request): Replace slot equipment dropdowns with visible stock search, type/size filters and Name/Size/Condition/DPS sorting. Native drag fitting, replacement, slot transfers and dragging back to stock use atomic physical transactions. Keep live cargo/passenger space, mounted-weapon DPS, current/max integrity and shields visible. Preserve Manage sell/repair access, theme and focus preferences. Focused native drag checks and the thirteen-suite baseline pass; broader V1/V2 remain open. See docs/HANGAR_DRAG_DROP.md.

- [x] V2b (supplied cargo art): Integrate cargo_xl.png as the XL Cargo Hold thumbnail, centered sprite drag preview and snapped fitted-slot art. Keep the entire installed part draggable; preserve aspect ratio/transparency and source PNG. Share mounted sprites across fleet/battle views, cache textures and keep text fallbacks for equipment without art. Native drag/snap/removal/reload checks pass. See docs/HANGAR_DRAG_DROP.md.

- [x] V2c (owner playtest UI batch): Fleet first/default, Hangar renamed Ships; preserve formation camera, native box selection/group movement and empty-space deselection; white silhouette selection glow; confirmed salvage and atomic Repair All for an empty selection. Dark stationary interactive stars reuse menu art/animations. Restore visible linear map flights (2-3 seconds by distance) and block duplicate departures. Use science.png for header RP and align miniTurret.png by its circular base. See docs/UI_PLAYTEST_POLISH.md. V1/V2 remain open for the wider audit.

- [x] V2d (node identity): Seed stationary space backgrounds by campaign seed + map-node ID. Use a normalized, viewport-independent star pool rather than copying transient arrays, preserving layouts across actions, tabs, resize history, Continue and future return visits. Keep twinkle/click animations and expose the same area-seed helper for node-specific scenery. No new save data or gameplay RNG consumption.

- [x] V2e (mount callouts): Organize full mount/equipment labels in aligned columns beside the ship, connected to their actual mounts. No text or opaque controls over chassis/module art; no equipment initials or truncation. Research Lab 1/2/3 use full names. Both side cards and transparent mount targets support fitting and installed-equipment dragging. Native all-chassis layout and drag checks pass.

- [x] V2f (unequip target): During installed-equipment drags, replace the entire right panel with a centered Drop here to unequip instruction; hide normal content until release/cancel. Include frame/padding in the target, preserve filters and backend restrictions, and keep loose-stock drags unchanged. Native drag checks pass.

- [x] V2g (combined UI correction): One-line mount cards show only a full equipment name when fitted, otherwise slot type. Stable per-chassis rails preserve scale; drag sprites preview actual hovered-slot size/anchor before release. Align RP icon/value as a single line. Buy toggles an embedded center panel with equipment/chassis modes, accessible roster/stock and purchases that keep the shop open; shared X closes it. Add joint layout, shop transaction/toggle and native pre-drop geometry checks.

- [x] V2h (inline stock selling): Replace Manage/Stock modal access with a right-aligned coin icon on each stock card. First click swaps row two to Sell? plus cancel/checkmark, retaining the exact coin position for confirm. Preserve UID ownership, half-catalog proceeds (equipment condition removed), failed-save rollback, filters and drag fitting. Native confirm/cancel/retry/no-double-payment checks pass.

- [x] V2i (art-only equipment interaction/contextual details): Make side labels passive panels and reject drops/drag starts there. Fit/select/transfer and start unequipping directly on ship art. Replace all bottom ship stats with selected-part name/HP/type/effect; blank space, empty mounts or removal restore ship stats. Reserve bottom height to avoid moving art/drop targets. Native direct-art and rejected-label gestures, details switching and carrier/mount regressions pass.

## Deferred: story-led depth after UI/UX


These retain the earlier full-campaign milestone IDs. They are not required for the current slice and must not automatically resume just because an earlier item is implemented. Revisit scope, progression and priorities when the story needs are clearer. The broader versions of 66-70 below extend the slice checks; they do not defer essential slice readability, reliability or performance.

- [ ] 56b: Finish ECM Suite / Phase Drive using physical ships and credits: bounded lock breaks, target coordination, valid-space/range checks, source loss, research gates and persistent cooldowns. No optional abilities or adjacency bonuses.
- [ ] 58: Intermediate passenger/science content: Luxury Suites, Analysis Array and bounded support effects. No material refinery requirements.
- [ ] 59: Act II enemy combinations with readable roles and counters, independent of player fleet strength. Optional cloak/environment variants remain deferred.
- [ ] 60: Brood Architect: finite hangars, repair without resurrection, clear telegraphs, persistent organ loss and one-time progression rewards. No old capacity unlock.
- [ ] 61: Research pacing through Act II using planned travel days and ranked lab production. Compare science/tourism/trade routes at equal credit investment; review old costs and rank rewards.
- [ ] 62: Combat endpoints: Stellar Lance, Singularity, Aegis, Ark Restoration, Siege Mass Driver, Hive Carrier, Admiralty Nexus and Ghost Network, with finite effects, source loss and story/research gates.
- [ ] 63: Support endpoints: Grand Promenade/Sanctuary, Industrial Foundry/Field Patch and Quantum Observatory/Forecast, adapted to slots/credits. No material/mining endpoint requirement or automatic replacement Planetcracker mechanic.
- [ ] 64: Act III encounters that teach and combine readable sweeps, charging organs and finite hangars. Optional hazards are not required.
- [ ] 65: Leviathan phases and ending: persistent organs, bounded interrupts, readable pulse/sweep warnings and exactly-once ending/reward saves.
- [ ] 66: Essential art/accessibility: supplied chassis, readable equipment/status/targeting effects, reduced flashes and no hidden-information leaks. No grid/recipe art commissioning.
- [ ] 67: Balance credit economy, command budgets, typed-slot opportunity costs, research/travel and multiple viable fleet doctrines.
- [ ] 68: Persistence, malformed/legacy data, interruption/retry/duplicate-settlement, resource conservation and exploit regressions for the slot model.
- [ ] 69: Profile full battles and repeated construction/refits/equipment changes; review all core UI at supported resolutions. No multi-second interaction stalls.
- [ ] 70: Clean full-campaign playthroughs with several doctrines, recorded core checks and explicit remaining tuning issues. No purchasable stubs. Optional backlog is not required for MVP.

## Optional / extra: do not activate during core work

- 34: Cargo-goods freight capacity upgrades, after slot/credit migration. Material pickups/refinery preferences are retired.
- 37: Additional Sensor Array/Radar Relay range upgrades.
- 40: Extra attack/defense abilities beyond core requirements. Gravitic Snare / Disruption II stay unavailable until their ability path is adapted to physical ships and credits; preserve old saves without offering an inactive purchase.
- 47-49: Environment scheduler, storms/currents/nebulae and hazardous travel. Any future scope must use the material-free model; no old ore/mining prerequisites.
- 57: Additional cloak/decoy content.
- 51a: Exhaustive objective/arena combinations beyond core campaign variety.
- 66a: Complete bespoke art/audio replacement pass.
- 67a: Exhaustive doctrine comparison matrix.

Retired rather than optional: grid recipes/assembly, hex regions/bonuses, material/ore collection and trading, refinery/spectroscopy/Planetcracker-as-mining requirements, reserve ships and act-based fleet capacity. Do not add replacements without the owner's direction.

## Reference

- Active implementation and validation: docs/HANGAR.md. Earlier SLOT_DESIGNER.md / SLOT_CLEANUP.md are historical snapshots.
- Chassis art/maps: data/slot_chassis.json. Equipment identity/type/size/stats: data/slot_equipment.json. Original owner artwork stays unchanged.
- Pre-cleanup milestone history: docs/history/TODO_PRE_SLOT_CLEANUP_2026_10_31.md. Prior checkmarks describe the old game and do not validate slot migration.
- Older design/hex/recipe documents are historical; they do not override this plan or AGENTS.md.
