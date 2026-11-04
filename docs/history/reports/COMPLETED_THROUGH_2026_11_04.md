> Archived reference (2026-11-04), not current instructions or an active backlog. See [current gameplay](../../HANGAR.md).

# Completed work

Archived from [TODO.md](../plans/CONTINUOUS_EXPEDITION_2026_11_04.md) on 2026-11-04. This is implementation and verification history, not a new task list or a requirement to rerun broad tests.
Later owner decisions supersede older entries. Current behavior is documented in [docs/HANGAR.md](HANGAR_2026_11_04.md); unfinished work and design contracts remain in TODO.md.
Completion dates are retained where recorded; the archive date does not imply these tasks were all implemented that day.

## Workflow alignment (2026-11-04)

- [x] Apply the owner's Godot preferences to existing work: moved 87 completed entries and their recorded acceptance history here; preserved all 81 unfinished tasks (one full-baseline task revised to focused verification), partial-phase blockers and design contracts. Updated AGENTS.md, TODO.md and docs/HANGAR.md to require concise visual-first UI, focused-only tests and TODO-to-COMPLETED tracking. Marked docs/MINING.md as historical. Reviewed the existing research detail and completion-description path; no runtime change was necessary. Verified exact completed-item preservation, open-task preservation, new local links and whitespace. Documentation-only; no game suites run.

## Meaningful text and diegetic UI (owner review 2026-11-02)

Do this UI pass next, before D2-D5 or additional content depth. The world shows what is happening; instruments show how much; text identifies things, explains gameplay effects, gives orders or states decision costs. Remove narration of visible state, not decision-critical information. These tasks supersede older UI descriptions where they conflict, including the routine informational arrival dialog. Preserve the current fleet/loadout flow, gameplay, artwork and atomic saves; no new resource or command systems.

### U1 - Command header and navigation instruments

- [x] Display and allocate science in whole RP rounded down. Retain fractional earnings in the saved bank until they combine into a whole spendable point; preserve historical fractional project progress by returning its remainder to the bank on allocation.

- [x] Fit compact time controls into the topmost center recess; use the lower recess for Engage/Change Course or destination/remaining-distance readout. Raise and shrink Map/Fleet/Ships/Research buttons toward the rail. Engage uses a selected valid destination and the last speed, atomically clearing only user pause; without a destination it opens Map. Preserve mandatory pauses, map shortcuts and save rollback.

- [x] Try supplied `element_1.png` as the management-screen top bar: Map/Fleet/Ships on the left, Pause/Play/Fast Forward in its central recess, research/wallet/settings on the right. Preserve source art, use shared theme surfaces and crisp filtering, and keep controls accessible across screen sizes. `element_3.png` is available for later panel experiments; no placement chosen yet.
- [x] Replace the header trial with new `top_bar.png`; add matching `bottom_bar.png`, `left_panel.png` and `right_panel.png` to all management tabs via dedicated shared-theme surfaces. Preserve controls, source artwork, centered speed controls and crisp rendering; dialogs/shop frames remain separate.
- [x] Preserve the full frames' original aspect ratios: resize bars/panels around uniformly scaled art instead of stretching/nine-slicing. Use supplied normal, height, specular and occlusion maps through cached surface lighting, without lighting UI text or controls. Longer side content remains reachable by wheel scrolling without visible scrollbars.
- [x] Slide all four management frames in/out from their nearest screen edge in 0.18 seconds. Visible meaningful information or controls keep a frame present; empty frames leave and stop intercepting input. Keep navigation/time, fuel and save controls available while needed. Play `panel-open.mp3` on entrance through the effects bus, never on routine content refresh; reverse interrupted slides without resetting layout or gameplay state.
- [x] Align frame artwork flush to its viewport edge, removing outer margins and vertical inter-frame gaps. Use reclaimed space to enlarge both side panels by roughly 8%, preserving uniform scale, edge-aligned entrance/exit and usable Ships/shop layouts.
- [x] Bring the battle header into the shared mapped, aspect-preserving top-bar artwork and edge entrance. Reuse the management pause/play/fast glyphs, retaining exact 2x/5x labels and mutually exclusive toggle behavior (off restores 1x; Pause resets speed; choosing speed resumes). Keep complete objective/Warden timing text in the lower recess and conditional repair/rebuild/carrier counts below the frame. Native review at 640x360, 1280x720 and 1920x1080; header clicks cannot target or pan the battlefield. Warden prose reduction remains a separate U3 pass.
- [x] Remove the Map fuel-range circle and calculated range readout; players estimate range from fuel and trip costs. Render all regions with the same space background, without act tinting, locked-region shading or boundary lines. Preserve destination access rules, fuel levels and selected-trip costs.
- [x] Reduce Map duplication: one fuel instrument with exact values; existing fleet position, heading and route communicate navigation. Remove VOYAGE heading, routine traveled-distance/visited counts and duplicate fuel readouts from the default view; retain any needed score statistics in the report. Do not restore fuel-range overlays or act-region shading.
- [x] Distinguish visited locations with existing checkmarks, not color alone. Show declared shipyard/refuel/trade symbols above station art: supplied repair tools and credits artwork plus a conventional drawn fuel pump (no supplied fuel icon exists). Share the exact symbols with a compact named map key; no tooltip dependency. Reserve badge/key bounds in destination-label placement, retaining all initial destination names at 640x360, 1280x720 and 1920x1080. Keep selected-trip fuel/ETA, access restrictions and manual pan/zoom; no route-reachability overlays.
- [x] Replace persistent map instruction paragraphs with introductory guidance that can disappear after use. Preserve single-click inspection, GO TO/double-click course setting and live rerouting. The short hint honors Tutorials and is hidden after a successful course or travel, without new save fields.
- [x] Use visited checkmarks for stations as well as POIs; remove redundant selected-location "Visited" text. Station service symbols are now supplied by the map service pass above.

### U2 - Docking and routine feedback

- [x] Docked Fleet backdrop uses supplied mapped `space_station_large` art, rotates once per 30 real-time seconds and emits warm light onto nearby ships. It follows pan/zoom and disappears on departure without blocking ship interactions. Reduce shared mapped-surface ambient light while preserving UI/unmapped-art readability.

- [x] Replace ordinary informational arrival dialogs with existing docked Fleet station art, docking feedback and contextual side-panel services. Map offers exact-price Repair All/Refuel and Shipyard; Fleet offers Repair All/Refuel alongside its existing Buy Ships and selected-ship controls. Context disappears on departure and returns on Continue without a new save field or forced tab switch. Keep encounter/retry, rescue, debt and run-end dialogs; preserve courses, selection, pan/zoom and speed. Failed service saves pause with explicit error/retry and never mutate credits, fuel, loads or hull.
- [x] Confirm course changes through existing route/heading updates; pulse the exact fuel instrument for 0.8 seconds after successful refuel and hull readouts after successful paid repair or automatic fleet-repair completion. No routine success toasts; failed transactions retain explicit errors/retries and never pulse as successful. Transient cues survive routine rerenders without changing layout, pan/zoom or saves.
- [x] First feedback reduction: remove routine course-set/departure, tanks-refilled and fully-repaired prose. Keep boarding quantities, delivery income, research completion and errors. Additional instrument animations remain pending.
- [x] Show delivery income briefly at the wallet and cargo delivery at its source indicator. Research completion uses a wide nonmodal toast below the command header with supplied `Popup_GameTips` framing, science icon, complete upgrade name and current tree effect summary. Fade in/out around a five-second display; queue consecutive completions across screen refreshes and battle return. Only committed travel/bank/event/battle completions enqueue; Continue never replays old completions. Respect audio settings; do not rely on sound alone.
- [x] Delivery feedback tranche: replace the centered "Delivery paid" prose toast with exact +credits and the shared coin icon beside the wallet for 1.6 seconds, plus a brief cargo/passenger readout pulse. Only committed delivery triggers it; preserve capacity, mute preferences and input-through behavior.
- [x] Replace "Loaded N cargo/passenger bays" feedback (counts occupied equipment, not goods/people) with separate actual cargo-unit and passenger counts. Keep fleet-wide carried / available-capacity totals visible in the expedition summary; final left/voyage or right-panel placement is deferred to the upcoming UI layout review. Derive quantities from installed equipment-instance loads, not bay count or capacity. Refresh after boarding/loading, delivery, losses and Continue, including partial/empty loads and failed-save rollback; do not add load-management controls.
- [x] Preserve explicit save failures/retries, debt/casualty notices, irreversible-action confirmations and mandatory pauses throughout the UI pass. Failed station services never pulse successful instruments; failed research and ability saves keep errors and rollback; passenger fees/balance remain in reports. Covered by persistence, services, arrival, events, clarity, battle UI and outcome checks.

### U3 - Battle, ships, research and reports

- [x] Show compact box/person symbols with exact carried-unit multipliers in the battle header, derived from installed equipment-instance loads on deployed living ships. Keep zero counts after losses; omit instruments when no such equipment deploys. Replace ability click-instruction prose with a pressed full-name action and distinct scan arcs, seismic-cut diamond, ion brackets/bolt and inward gravity chevrons. Retain source-range/area previews, add an invalid-target X (not color alone), refresh validity as sources move/change, and cancel stale targeting after source loss or cooldown. Preserve exact cooldown seconds, cancellation/pause behavior and explicit save failures; do not unlock deferred equipment or add ability availability. Cooldown rings remain optional/deferred. Native pixel/geometry and headless behavior checks cover this pass.
- [x] Replace "WARDEN: Destroy body" / "PYLON ESCORT: Clear fleet" with direct "Destroy Warden" / "Clear escort fleet" orders. Existing pylon links and exposure/lance telegraphs carry the spatial explanation; a brief Protected state preserves protection clarity. Keep exact exposure/lance seconds, ordinary encounter target counts, wave progress and next-wave timing. Special victory rules and all boss mechanics remain unchanged.
- [x] Operational Ships/Fleet details share current/max hull, numeric shield capacity, mounted DPS and carried/capacity transport instruments. Mass/normalized maneuverability stay in purchase comparison only. Battle transport uses exact living deployed loads; reports use shared exact-value columns. Preserve full equipment/loadout names, selected-part effects/rates and the fixed detail reservation; do not fabricate persisted shield charge or alter mechanics.
- [x] First Ships/Fleet instrument tranche: default hull bars measure current/max condition (including empty bars at zero/negative hull), not chassis-relative strength. Keep exact hull, shield capacity and DPS; show carried cargo/passengers against capacity. Retain mass/maneuverability comparison in purchase inspection only. Remove duplicated selected-part effects, the mount instruction, empty self-repair readouts and the redundant Fleet heading; preserve the fixed Ships detail reservation.
- [x] Research uses the existing tree/connections/completion checks plus a shape-distinct focus diamond. Remove duplicate sidebar bank and disabled FOCUSED button; retain production by lab rank, exact RP/day and distance-only Travel only explanation. Header owns the whole-RP bank; project details retain effects, exact progress/cost, Set Focus, missing requirements and exclusive-path warnings. Preserve pan/zoom, stopped/combat accrual rules, stored fractions and failed-focus rollback.
- [x] Correct the expedition research sidebar to distance-only accrual, actual NU/day and stored unfocused RP; remove PRODUCTION and legacy on-arrival preview instructions. Tree/focus instrumentation remains pending.
- [x] First research-tree instrument tranche: mark the focused node with a distinct closed diamond as well as its existing tint; remove the redundant disabled FOCUSED button and sidebar bank duplicate. Keep Set Focus for other eligible projects, exact progress/cost, effects, prerequisites, exclusive-path warnings and explicit save failures. Preserve pan/zoom through refreshes and resizing.
- [x] Bank unfocused RP and completion overflow in game state and atomic checkpoints. Automatically apply the bank when selecting focus, retain fractions, preserve existing balances and load absent balances as zero. Show stored RP in the Research button when unfocused; travel updates it without rebuilding the canvas.
- [x] Reports put fleet losses first, then ships needing the most hull repair, ahead of opposition summaries. Share aligned Damage / Deflected / Repair HP headings across each section instead of repeating labels per ship. Keep full ship names/art, explicit DESTROYED status, integer values including zero, reward amounts and passenger losses/fees/balance. Wrecks/opposition show no repair amount; Repair HP is damage, not a fictional credit quote. Preserve scroll access and Back to Fleet at all three resolutions; no squadron system.

### U4 - Copy correctness and acceptance

- [x] Fix invisible research descriptions: remove the zero-height nested scroll area and use the existing side-panel viewport. Native regression checks require actual readable description height and intersection with the visible viewport for every node at all three resolutions, not merely text existing in the scene tree.

- [x] Selected research details show one short gameplay sentence (owner trim 2026-11-03), without duplicate numerical effects, prerequisite/story-gate/path prose, "this research leads to" explanations or refitting boilerplate. Completion toasts reuse the same sentence. Keep the 11-pixel description, title, project progress/cost, Set Focus and explicit save failures; tree connections/status and backend eligibility preserve research rules. Reviewed all 17 visible descriptions; Prismatic Lasers reads "Lasers become sustained beams that grow stronger over time." Validation: 187 headless research, 154 clarity and 521 native combat/research checks, including actual visible descriptions at three resolutions. Isolated logs: `.local/checks/research-trim`.

- [x] Correct the charter briefing's retired equipment buying/drag-fitting/DEPART instructions to the current fitted Transport/loadout/Map course flow.
- [x] Expose current demo event costs as clearly as rewards: explicit fuel/credit exchange, max-hull penalties alongside research rewards, and confirmation that unfocused RP is stored. Preserve existing rescue/debt notices and intentional uncertainty; do not hide known penalties behind action verbs.
- [x] Keep names, meaningful story/victory orders and short action verbs. Navigation, station services, research focus and report return actions retain discoverable labels; service symbols have a named key; targeting retains full ability names/cooldown seconds. Reuse shared resource icons/theme, no tooltip dependency, cryptic icon-only decisions or fictional-console busywork.
- [x] Verify 640x360, 1280x720 and 1920x1080: no overlap/clipping, readable exact values, distinguishable cues without color/audio alone, discoverable actions and unchanged geometry/pan/zoom where required. Test the complete course -> event -> station/trade/refuel/refit -> battle -> report loop and failed-save/retry behavior using isolated APPDATA; run `tests/run_baseline.ps1 -Native` before accepting the pass.
- Final U1-U4 acceptance: `tests/run_baseline.ps1 -Native` passed all 31 headless suites and all 12 native suites, including the complete demo, save rollback/retry, nine natural campaign variants, three-resolution clarity, battle UI/reports, chassis inspection, mapped lighting, UI capture and polish. Native surface art passed 383 checks, battle outcomes 153, battle UI 61, chassis inspection 138, hangar UI 2093 and polish 272. Tests used isolated APPDATA; real saves were untouched. Corrected stale free-refit/shop/ambient fixtures and the collapsed inspection scroll area; native unchanged-image comparisons tolerate measured two-level color quantization while still requiring visible exhaust/shield effects above that noise. Existing shutdown resource warnings remain. All actionable UI work is complete; the approved-art dependency above remains open.

Historical tranche validation below is superseded by final acceptance above:

- First tranche regression coverage: [tests/test_expedition_ui_clarity.gd](../../../tests/test_expedition_ui_clarity.gd) covers actual/partial/empty loads, destroyed hosts, boarding/delivery/Continue/failed-save totals, tutorial visibility, research copy and event-cost geometry at all three resolutions; included in the headless/native baseline.
- First tranche validation: all 30 headless suites passed across the baseline run and focused completion after updating the old shared-parent header assertion. Focused native UI/clarity/event/arrival/service checks passed. Full native acceptance remains open: `test_surface_art.gd` reported three thrust-particle/shield-flash rendering assertions outside this text pass; do not treat the complete native baseline as green.
- Ships/research tranche validation: focused headless UI/research and native clarity/UI/polish suites pass with three-resolution coverage. The required `run_baseline.ps1 -Native` attempt stops at the existing retired 10-credit swap-fee expectation in `test_hangar.gd`, before native acceptance. The broader chassis review also has stale seeded-shop/pointer assumptions; its comparison assertions were updated for the intentional operational-view change, but full-pass acceptance remains open.
- Contextual-arrival regression coverage: arrival/world/events/services/clarity/demo suites verify nonmodal arrivals, exact service quotes, failure rollback/retry, docked Continue, departure cleanup and three-resolution geometry. Native arrival/world/polish checks pass. Full baseline acceptance remains blocked by the retired refit-fee expectation, not accepted as green.
- Instrument-feedback validation: focused headless clarity/arrival/services and UI/world/events/demo checks pass; native clarity/arrival/polish checks pass. Coverage includes exact income, real horizontal text/icon width at all three resolutions, pulse expiration, refresh persistence, unchanged saves/pan/zoom and no success cues on failed repair/refuel. The native baseline attempt still stops at the retired refit-fee assertion.


## Fleet-command delivery history

### D1 - Foundation: loadouts instead of stock

- [x] Remove the player's equipment stock, equipment buying, inline selling and drag-fitting. Equipment exists only on ships; per-instance IDs remain internal (cargo/passenger loads still follow them).
- [x] Every ship class has named loadouts in data (e.g. Fighter: Interceptor / Striker / Escort). Ships are bought fully fitted with their default loadout.
- [x] At a shipyard, choose loadouts or swap one mount's part for existing ships for free, including at zero credits or in debt. No refit prices or affordability gates; loaded holds/cabins must deliver first and changes remain atomic.
- [x] Most equipment is initially available independently of completed research (owner clarification 2026-11-03). Only Beam Lance, Bomber Bay, Tactical Computer and Lab III require research. Hide ship/squadron fits containing those locked advanced parts, and gate fitted purchases and all fitting backends atomically. Lasers, missiles, railguns, Lab II and existing fleet support are starting options. Keep deferred items unavailable.
- [x] Every predefined fit fills every chassis mount, including New Run defaults. Fill missing Civic/science/Transport mounts with existing exact-size equipment; Transport Survey trades cargo for Lab III so it remains distinct from Freighter. New Run starts with Foundation only: equipment access must not grant research, upgrades, score or exclusive branch choices. Continue preserves existing earned research/branches without adding or removing anything. Earlier default mount layouts remain validation-only history for squadron saves.
- [x] "Buy Chassis" becomes "Buy Ships".
- [x] Map is the first, default tab and the home screen; Fleet is for arrangement.
- [x] Battle rewards stop granting items: credits and research points for now (D2 adds the rest).
- [x] Pricing: loadout changes, part swaps and removals are free at shipyards; buying a fitted ship still costs its chassis plus half its parts. Data: `data/ship_loadouts.json`, logic: `scripts/ship_loadouts.gd`, tests: `tests/test_ship_refit.gd`.
- Research-gate/full-fit acceptance: all 35 headless suites passed in `tests/run_baseline.ps1 -Native`, including 253 refit checks, 520 demo checks and nine natural campaign variants. The command stopped at two native surface-art snapshot comparisons; an unchanged focused rerun passed all 383 checks. The five remaining native suites then passed (UI 2096, polish 272, missiles 126, squadrons 182, combat research 470), completing coverage of all 15 native baseline suites across the run and follow-ups, not a single uninterrupted green baseline. Focused native refit coverage also passed 253 checks. Initial logs: `.local/checks/ae2a2a3dff134abc8c92aa88d4dc850f`; focused rerun/follow-up logs: `.local/checks/gated-refits`. APPDATA remained isolated; real saves were not used. Surface-art assertions and rendering code were not weakened or changed.
- Starting-access clarification acceptance (supersedes the equipment-gating policy above): `tests/run_baseline.ps1 -Native` passed all 35 headless and all 15 native suites uninterrupted, including surface art, nine natural campaigns, persistence, UI and retained behavioral research. Focused native refit checks pass 269 assertions covering majority starting access, all four advanced gates, Foundation-only fully fitted starts across every flagship, no branch/completion grants, hidden/revealed Lab III fits, atomic rejection, old installed advanced items and correct inspection labels. Initial-access rules do not mutate saved research or automatically refit ships. Full logs/saves: `.local/checks/0835361ab3b94a6bbccee54c9bc03a1e`; focused logs: `.local/checks/starting-tech`. APPDATA remained isolated; real saves were not used.

### D2 - Rewards and resources

- [x] Battle/event rewards: credits, research points, occasional rescued ships that join the fleet, rarely fuel. Existing derelict salvage recovers capacity-capped fuel; the distress victory rescues a fully fitted Transport with unique equipment IDs and no fabricated loads. Rescues respect command capacity; a full fleet receives the fitted ship's credit value instead, disclosed before combat. All rewards, ownership, receipts and IDs commit together; defeat/withdrawal and duplicate settlement grant nothing. Focused reward (48 checks), refit (189), event (81), demo (520), clarity (154) and report (153) regressions pass.
- [x] Missiles as a consumable fleet resource (FTL-style): new runs start with 30; docked stations sell 10 for 50 credits, and existing derelict salvage recovers 6/12. Each Missile Rack projectile spends one from the shared pool; partial final salvos are allowed, empty racks stop, other weapons/enemies/carrier allowances are unchanged. Exact supply stays visible in management and battle; fitting identifies the salvo cost. Ammunition settles atomically on victory, defeat and withdrawal, so subsequent encounter attempts retain expenditure. Continue during a pending battle still restarts the entire encounter from its last committed deployment/ammunition, not a mid-battle snapshot. Older checkpoints load a missing supply as zero. Focused native ammunition coverage passes 126 checks, including actual pointer purchases, three-resolution layouts, rollback, duplicate outcomes, replay determinism, overflow and malformed-save rejection.
- D2 acceptance: `tests/run_baseline.ps1 -Native` passed all 33 headless suites and all 13 native suites, including the complete demo loop, nine natural campaign variants, rewards (48 checks), ammunition (126 checks in both render modes), persistence, battle/report, three-resolution clarity, UI capture, surface lighting and polish. All saves/logs are isolated under `.local/checks`; real user saves were not used. Existing renderer/resource shutdown warnings remain; expected invalid-input/save-failure injections are not assertion failures. Implementation is committed incrementally; D3 is next.

### D3 - Squadrons and stances

- Older physical-v2 saves derive same-chassis squadrons without rearrangement or equipment changes. New groups default to Seek to preserve existing battle behavior; changes to orders, membership, defaults and formation anchors persist with the fleet.
- [x] Ships belong to squadrons, the main unit of command. A squadron owns its stance, formation slot and default loadout, with per-ship overrides. Same-chassis groups preserve actual fits/positions; Ships can split a member or join another compatible group.
- [x] Stances: Seek & Destroy, Defend Flagship, Evade. Combat AI targeting and movement follow them (Evade keeps transports out of fights). Explicit attacks override passive orders; carriers respect stance and retain their finite allowance.
- [x] Group actions: refit, repair, buy N ships into a squadron. The Fleet tab arranges squadrons as blocks. Refits preserve overrides unless explicitly reset; group purchases/repairs/moves use one quoted atomic transaction. Artwork/count roster cards avoid long repeated names.
- D3 acceptance: `tests/run_baseline.ps1 -Native` passed all 34 headless suites and all 14 native suites. The 179-check squadron suite passes in both modes, covering actual pointer orders, refits, buy-N, split/join, box selection, whole-block drags, failed-move feedback and aggregate condition/transport readouts; three-resolution geometry and pan/zoom are covered. Legacy fixture setup records its intentional custom-loadout override; polish/chassis assertions exercise squadron selection rather than retired single-ship Fleet details. The full demo, nine natural campaign variants, save/replay, ammunition and native rendering checks remain green. Isolated saves/logs: `.local/checks/99f8240a9abd427a831e832164e2d1c4`; no real user saves were used. Existing renderer/resource shutdown warnings remain. D3 is complete; D4 is next.


### Fleet-command direction (owner review 2026-11-02) / D4 - Research that you can feel

- [x] Replace flat percentages with noticeable combat effects. Prismatic Lasers replaces the old flat energy bonus with Laser/Double Laser channels ramping from 1x to 2x base DPS over four uninterrupted seconds, resetting on target/contact/fire loss and respecting armor, magazines and synchronization. Siege I splits each Missile Rack parent into three interceptable half-damage fragments near its target (one parent ammunition cost; visible nearby hostiles only). Bastion II restores up to 25% shields every eight combat seconds under fire; suppression skips pulses. Existing research IDs, prices and exclusive branches persist; effects derive from earned research on Continue. Widening prismatic beams, amber fragments and cyan shield rings provide in-world feedback; research details/toasts and fitted inspection disclose mechanics. Focused headless/native coverage is registered in the baseline; see `docs/HANGAR.md`.

- Combat-research acceptance: `tests/run_baseline.ps1 -Native` passed all 35 headless suites and all 15 native suites. The new research suite passes 227 headless / 233 native checks, including exact damage and pulse intervals, real asteroid occlusion, contact/fire/source loss, hostile splinter spread, point-defense interception, ammunition, save rollback/Continue, exclusive branches and deterministic laser/missile replay. Three-resolution research inspection and completion feedback fit; native pixel comparisons verify beams, fragments and shield rings with viewport stretch and the existing 2/255 capture noise allowance. Full demo, nine natural campaign variants, squadrons, persistence, lighting and UI checks remain green. Isolated saves/logs: `.local/checks/512a9cf777764745b5b18dd27c08a1f6`; real user saves were not used. Existing renderer/resource shutdown warnings remain; intentional malformed-input errors are exercised without assertion failures. First D4 milestone complete; the remaining D4 items below are still open.

- [x] Economy/travel first tranche: Field Engineering reduces cruise fuel use by 25%; Civil Hospitality earns four credits per travel day, from quarter-day distance crossings only. Retain starting equipment access, research IDs/costs/prerequisites and earned progress; derive effects on Continue without new save fields. Map fuel quotes/range indicators use the real discounted rate. Preserve exact fuel/event/arrival boundaries and ordinary trade. Wallet, score, fuel, research, repairs and deliveries save/roll back together; no docked/stopped/paused/stranded/event/combat income or retroactive payouts. Credit changes during cruise update the wallet without rebuilding Map/Research or changing selection/pan/zoom. Keep one short gameplay sentence per research and toast, without new UI labels. Final travel coverage passes 186 checks in headless and native modes, including awaited three-resolution quotes, live-view preservation, unchanged lab production and damaged-hull rollback.

- Economy/travel acceptance: `tests/run_baseline.ps1 -Native` passed all 36 headless and all 16 native suites, including nine natural campaign variants, the complete demo, persistence, combat/research, lighting and three-resolution UI. Updated the older Lab III detail assertion to enforce the owner's concise research copy rather than its removed numerical summary. No rendering assertions were weakened. Full logs/saves: `.local/checks/a1e624e8d9cc4cdbadec0b80a1bf2878`; focused final logs: `.local/checks/research-travel`. APPDATA stayed isolated; real saves were not used. Existing renderer/resource shutdown warnings remain; intentional invalid-input/save-failure injections are not assertion failures.

### 5. Work packages and dependencies / Phase 1 - Continuous flight prototype / E01 - Establish data/command contracts and mechanical fixture

- [x] Define typed travel/pause/boundary enums and a small `scripts/expedition_state.gd` DTO with validated save-state fields. Event data/runtime remains with E06.

- [x] Add `data/expedition_tuning.json` and `data/expedition_locations.json` as a minimal story-neutral mechanical fixture. Validate IDs, services, positions, gates and tuning bounds on load. Event templates remain with E06.

- [x] Specify stable location IDs and the versioned expedition-state snapshot before consumers start. Tick-boundary command ordering/commit semantics remain open for runtime integration.

- [x] Add malformed-data and fixture-shape tests in `tests/test_expedition_state.gd`. Reachability/rescue connectivity remains for E09.

### 5. Work packages and dependencies / Phase 1 - Continuous flight prototype / E02 - Add one fixed-step expedition clock and state machine

- [x] Implement the isolated `scripts/expedition_simulation.gd` prototype as a fixed-step navigation coordinator. GameState ownership/wiring remains E04.

- [x] Implement supported speeds, independent pause reasons, stop/resume/cancel, rerouting from current NU position and exact fuel/station arrival clipping.

- [x] Add `tests/test_expedition_navigation.gd`: equal simulated time at all speeds, rerouting, pause separation, fuel and arrival boundaries.

### 5. Work packages and dependencies / Phase 1 - Continuous flight prototype / E03 - Mount continuous travel in the existing game UI

- [x] Keep `scenes/game_map.tscn` and `scripts/hangar_screen.gd` as the game shell. Continue and New Run retain the original screen flow; do not create a replacement expedition interface.

- [x] Use the existing Fleet formation page as the primary travel view, preserving the original roster, side panels, formation controls, header and tab navigation. Add only a compact travel overlay.

- [x] Render the live `HangarShip` fleet with its chassis artwork and fitted equipment while traveling; scroll the existing star background with distance. Battle actors remain unchanged.

- [x] Add `tests/test_expedition_world.gd` for continuous movement, stop/pause distinction, rerouting, active fleet, existing-screen continuity and basic viewport coverage. Actor/root identity and projection/rebase checks remain.

### 5. Work packages and dependencies / Phase 1 - Continuous flight prototype / E04 - Establish fresh expedition saves and stable live commits

- [x] Make new runs use `user://expedition_run.json`; the main-menu summary and Continue use that namespace. Preserve starter choices and transactional new-run failure handling.

- [x] Save/restore prototype cruise/stopped/docked state, route, clocks and fuel. Focus and pending interruptions remain with later E07/E09/E11 work.

- [x] Add five-real-second periodic saves plus immediate route, stop, speed, pause, docking and fuel transaction checkpoints; roll back and pause on a failed save, with an explicit retry action.

- [x] Persist a validated pending-departure-choice flag for initial Depart and every arrival. The core simulation holds while it is pending; committed destination selection clears it. Continue reopens the actual pending choice rather than inferring arrival from visited-location counts.

- [x] Continue checkpoints user pause before opening the run, preserving exact position and requested speed. A failed Continue save rolls back and reports failure.

- [x] Add `tests/test_expedition_arrival.gd` to headless/native baseline coverage: unfinished initial choice, station/POI choice reload, paused Continue, failed arrival/choice/Continue commits, retry, and manual Stop not masquerading as arrival.

### 5. Work packages and dependencies / Phase 1 - Continuous flight prototype / E05 - Add travel controls to existing management pages

- [x] Preserve the existing Hangar/Fleet/Ships/Research/Map UI as the primary interface. The persistent compact header panel contains Pause, Play (1x) and Fast Forward (10x) icons. Fuel/refueling/retry remain in the footer, not over the Fleet canvas.

- [x] Remove destination dropdown, Clear, Stop and old speed buttons from the visible UI. Keep existing backend navigation commands and old speed snapshots usable.

- [x] Add a required arrival-choice modal describing story-neutral destinations/services, with no dismiss action. Initial Depart opens the same chooser. Freeze simulation while choosing; retain user/event pauses; only close after a committed route, with in-modal save-error/retry handling. Full strategic visualization remains E08.

- [x] Validate native UI polish after header/arrival changes. Advance its coordinator explicitly so periodic saves cannot race deliberately invalid save paths. Runtime arrival boundaries use a monotonic sequence, not capped history length, so later journeys still clip/save/show their choice after 64 interruptions.

- [x] Port the baseline's legacy Swarm map UI fixture: assert that informational Map inspection cannot offer retired Relay/graph-travel actions or change expedition course. Retain historical quest transaction/receipt coverage directly without restoring that UI; guard fixture prerequisites so failures cannot hang on an empty target index. Headless and native checks pass.

- [x] Update the carrier regression's compact battle Settings expectation for the existing Tutorials row (304x250 with Quit to menu), including content containment; headless and native checks pass.

- [x] Port the environment view regression: informational expedition Map must not mutate the run or claim legacy graph-node conditions are active journey hazards; actual combat still receives and renders its exact frozen environment/asteroids. Headless and native checks pass.

- [x] Exercise all 27 headless baseline suites after the navigation/UI conversion. The full run passed through flagship selection before the last stale environment assertion; the corrected environment suite and all six remaining suites then passed in a focused continuation. No production behavior was changed to satisfy retired UI expectations. Existing Godot shutdown resource warnings remain.

- [x] Add basic docked refueling with a single atomic credits-and-fuel checkpoint. Amount quotes, partial refueling and rescue remain E09.

- [x] Apply backend service capability checks immediately. Buying, fitting/transfers/unequipping, stock selling, salvage and paid repairs require the expedition's actual docked shipyard, not the legacy map node. Refueling checks its separate declared service. Stop, pause, POI arrival and stale dock IDs grant no service access. User pause permits docked management; combat/save failure blocks services.

- [x] Refresh service actions in place on departure/arrival without rebuilding Fleet or resetting its camera. Cancel active fitting drags, pending inline sales, the embedded shop and salvage confirmations when access is lost; keep equipment inspection, research focus and formation editing available underway.

- [x] Add `tests/test_expedition_services.gd` to the baseline: backend rejection/atomicity, station service differences, Continue access, live UI cancellation/restoration and native drag cancellation. Keep fitting snapshot regressions paused so their comparisons exclude unrelated clock advancement.

### 5. Work packages and dependencies / Phase 1 - Continuous flight prototype / E06 - Add event admission and interruption plumbing

- [x] Add `scripts/expedition_events.gd` and a validated, ordered distance-trigger catalog with stable IDs. First fixture: a story-neutral derelict signal at 80 cumulative travel NU.

- [x] Save the pending signal before presenting a required Investigate / Continue Course decision above the existing UI. Return to 1x, freeze on its own pause reason, preserve other pauses and reject bypasses through route/time controls.

- [x] Commit choices and receipts atomically without rebuilding ships. Failed saves retain the decision; Continue restores it. Investigate preserves the original destination as an explicit Resume option at detour arrival, without teleporting, auto-departing or granting placeholder salvage.

- [x] Clip movement/fuel exactly at the distance trigger, discard stale fast-forward budget, prioritize coincident fuel exhaustion and defer travel signals during combat.

- [x] Add `tests/test_expedition_events.gd` to headless/native baseline: all supported speeds, variable frame sizes, fuel coincidence, duplicate choices, failed admission/resolution saves, pending-decision and detour reloads, real pointer choice, ship identity and modal/error layout at supported resolutions.

### 5. Work packages and dependencies / Phase 2 - Physical destinations and persistent exploration / E09 - Fuel, docking, service access and rescue

- [x] Gate every buy/refit/unequip/transfer/sale/salvage/repair command at a docked shipyard and preserve atomic drag rollback. Shared station-service checks and E05 service tests cover the prototype.
