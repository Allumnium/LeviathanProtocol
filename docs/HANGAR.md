# Current game

The active target is the existing Act I vertical slice plus remaining D4/D5 in [TODO.md](../TODO.md), not the archived full continuous-world expansion. Preserve implemented systems, saves and source artwork; no materials, construction/designer, equipment stock or component health.

## Runtime and persistence

- Entry: [main_menu.tscn](../scenes/main_menu.tscn). GameState: [hangar_state.gd](../scripts/hangar_state.gd). Management: [game_map.tscn](../scenes/game_map.tscn) / [hangar_screen.gd](../scripts/hangar_screen.gd).
- New Run/Continue use `user://expedition_run.json`; expedition state is embedded in the physical-hangar-v2 envelope. AtomicRunStore validates and persists credits, ownership, loadouts, hull, loads, research and expedition state together.
- Failed transactions must not change live state or emit success feedback. Surface an explicit retryable save error; preserve backup/recovery behavior.
- Continue preserves earned research, branch choices, loadouts, ownership and formation. Do not invent save conversions, refit old ships automatically or rewrite old material/blueprint files. Read-only compatibility boundaries are in [LEGACY_BOUNDARIES.md](LEGACY_BOUNDARIES.md).

## Demo vertical slice

- Haven Dock -> travel/events/battles -> station trade/refuel/refit -> Leviathan Protocol broadcast -> Bastion Warden at Bastion Gate -> Demo Complete with score. Locations/events: [expedition_locations.json](../data/expedition_locations.json), [expedition_events.json](../data/expedition_events.json).
- Map is home; Fleet arranges squadrons; Ships inspects/refits. Research opens from the header. Management stays accessible during cruise.
- Map courses start from the current fleet position, including mid-flight. Select a discovered destination, then Engage/GO TO or double-click; remembered detours offer RESUME. Preserve pan/zoom across state updates.
- Compact management controls are Pause, Play and Fast Forward. Requested speed survives interruptions. Arrival does not force an informational or destination-choice modal or switch tabs.
- Map shows position, heading, route/detour, destination distance/fuel/ETA, access restrictions and known station services. No large fuel-range circle, region tint/shaded bar or automatic reachability overlay.
- Docked services live in existing Map/Fleet side panels. Actual declared shipyard/refuel/trade capabilities determine access; Stop, pause, proximity or a stale legacy node never grant services. Unbeaten arrival encounters remain available through their contextual action.
- Combat transitions into the existing battle scene, settles once, then returns to the same expedition position/route. Continue during a pending battle restarts the saved encounter; this is not a mid-fight world-state restore.
- Combat retains existing targeting, abilities, visibility, finite carriers, asteroids and Warden behavior. The current slice does not require seamless in-world battles or new boss phases.

## Ships and loadouts (fleet-command D1)

- Equipment exists only on ships, with unique instance IDs. No equipment buying, selling, shared stock or drag-fitting.
- Buy Ships sells fully fitted ships. Named fits live in [ship_loadouts.json](../data/ship_loadouts.json); availability, lookup and fitted pricing are shared through [ship_loadouts.gd](../scripts/ship_loadouts.gd).
- Every predefined fit fills every mount, including New Run defaults. Most equipment is initially available: lasers, missiles, railguns, Lab II, cabins, support equipment and interceptor decks. Only Beam Lance, Bomber Bay, Tactical Computer and Lab III require research. Hide locked fits and reject unavailable fits/parts before mutation.
- New Run has Foundation only, with no forced research or exclusive branch. Previously installed locked advanced equipment remains inspectable/removable; Continue never grants copies or free research.
- Shipyard loadout changes and compatible per-mount changes/removals are free, even at zero credits or in debt. Replaced parts are scrapped. Occupied holds/cabins must deliver before removal; compatible retained loads stay attached to their UID.
- Fitted purchase price is chassis plus half its parts' prices. Group purchases use the squadron default. Command capacity, loaded-equipment guards and all-or-none persistence still apply.
- Exactly one flagship deploys; its destruction ends the run. Standard ships consume command points. Original chassis artwork and catalog tuning remain in [slot_chassis.json](../data/slot_chassis.json) and [slot_equipment.json](../data/slot_equipment.json).

## Chassis mounts and health

Require an **exact** S/M/L/XL size match. Current artwork-based category restrictions:

| Chassis | Mounts |
| --- | --- |
| Defensive Flagship | Three front S Offense/Defense; central M any; four rear S Civic/Tech/Defense. |
| Civic Flagship | Central XL Civic/Tech; two outer L and four M Civic/Tech/Defense; two upper S Offense/Defense; forward S any. |
| Research Flagship | Central XL Civic/Tech; two outer L and two lower M Civic/Tech/Defense; forward-center M any; two center-side S Offense/Defense. |
| Combat Flagship | Forward L and two outer M Offense/Defense; two shoulder S Offense/Defense; two rear S any; lower-center M any. |
| Corsair | Front L Offense/Defense; two side M Offense/Defense; rear S any. |
| Fighter | Front S any; two side S Offense only. |
| Transport | Central XL Civic/Tech; two side L Civic/Tech/Defense; front and rear S any. |
| Frigate | Four front S any; two side S Offense/Defense; central M any; rear S Civic/Tech/Defense. |
| Drone | Three S any; central M any. |

- [SlotCatalog](../scripts/slot_catalog.gd) owns shared compatibility; equipment category alone is not a universal mount restriction. Do not reintroduce the superseded general-purpose-side draft.
- Hull is the only persistent health pool. Shields absorb first; all remaining damage reaches hull. Zero hull is alive; destruction occurs strictly below zero. Equipment, engines and command centers have no independent health.
- Repairs restore surviving hull; destroyed hosts cannot be repaired. Lost cargo/passengers never reappear after repair. Salvage requires confirmation, cannot target the flagship and remains an atomic shipyard action.
- Existing chassis bonuses remain; exact values belong in catalogs/runtime, not duplicated prose.

## Squadrons (fleet-command D3)

- Same-chassis groups own a stance, formation centroid, default fit and per-ship overrides. Grouping never duplicates equipment or rearranges ships.
- Seek & Destroy preserves normal automatic combat. Defend Flagship guards the flagship; Evade avoids threats and does not automatically fire. Explicit attack orders override passive stance behavior. Carriers obey the same orders.
- Fleet selection/movement operates on whole squadron blocks. Preserve internal spacing, empty-space deselection, box/multi-selection, white silhouette glow and pan/zoom. A group move saves once.
- Squadron actions include default refit, Reset overrides, quoted Repair and Buy N. Default refits preserve overrides unless deliberately reset. Group changes/purchases/repairs commit atomically.
- Ships can split a member into a new group or join a compatible one without moving/refitting it. Membership/orders may change during travel, not during pending battle or after run end.
- Older physical-v2 saves derive groups without changing equipment, health, loads or formation. Invalid membership/defaults/anchors are rejected, not silently repaired.

## Trade, rewards and fleet ammunition

- Cargo/passengers follow equipment UIDs, not mount indices. Holds carry 10 goods; cabins carry four passengers. Trading-port departure loads eligible equipment; delivery requires a different trading port. Returning to origin does not cash out.
- Destroyed hosts lose their loads; passenger casualty fees apply once and may create debt. Deliver before removing occupied equipment.
- Event/battle rewards use committed receipts: credits, RP, fuel, missiles and occasional rescued ships. No equipment loot. Non-victory and duplicate settlement grant no rewards.
- The distress rescue grants a fully fitted Transport with fresh IDs and empty loads; insufficient command capacity gives the disclosed fitted-ship credit value instead. Fuel recovery is tank-capped.
- Fleet missiles persist across encounters/withdrawals. Each Missile Rack projectile spends one; partial final salvos are allowed and empty racks stop. Enemy weapons and finite carrier payloads do not draw from this pool. Magazines/computers never create missiles.

## Research and repair

- Research earns from traveled distance: installed living Lab I/II/III produce 1/2/3 RP per travel day, with existing chassis bonuses and fractional progress retained. No fleet baseline; stopped/docked/event/battle time does not generate travel RP.
- Focus changes, completions, score and resources remain atomic. Keep one pannable tree, hidden Foundation, completed checks and partial progress. Unspent RP appears only in the header.
- Selected research and completion toasts use **one short gameplay sentence**, shared 11px description styling and no duplicate numerical effects, prerequisite/path paragraphs or refitting boilerplate. Keep costs/progress, Set Focus eligibility and save failures meaningful.
- Prismatic Lasers turns Laser/Double Laser into sustained beams that ramp on uninterrupted contact; range/contact loss, target changes or obstruction reset the lock.
- Siege I splits player missile projectiles into finite interceptable fragments; only the parent spends ammunition. Bastion II periodically restores shields with a visible pulse; it cannot exceed capacity or revive a host.
- Field Engineering reduces cruise fuel use by 25%, including Map quotes. Civil Hospitality pays four credits/travel day at cumulative quarter-day milestones crossed while owned, never retroactively.
- Travel income uses actual distance, not idle time. Wallet updates during cruise must not rebuild views or reset selection/pan/zoom. Save failure rolls back credits, score, fuel, distance, research, repair and deliveries together.
- Living hull self-repairs during unpaused noncombat simulation time, including docked time. Paid repair remains the instant alternative.
- Active support remains ship-wide: magazines add +20% cycling per copy; Tactical Computers add synchronization rate per copy, across all host weapons without adjacency/target-count limits. Railguns, Command Uplink and finite Flight Deck/Bomber Bay remain active.
- Carrier replacement allowances follow UIDs across retries/transfers; source loss ends sorties. Repair drones heal surviving hull with finite reserves, never reconstruct lost loads/hosts.
- Extraction, slot bonuses, Gravitic Snare/Disruption II, ECM/Phase and component-rebuilding effects remain deferred; preserve old earned/installed data without offering unsupported new grants or inventing replacements.

## UI and artwork

- [unused_resources/](../unused_resources/) holds confirmed-unused tracked resources and their import sidecars in the original relative layout (one long preview filename is shortened for Windows). Its `.gdignore` excludes the archive from Godot imports/exports; local `.gitattributes` prevents checkout line-ending changes from invalidating archived hashes. [manifest.json](../unused_resources/manifest.json) records original paths and SHA-256 hashes for restoration; restore source plus sidecar together. Do not reference archived files from active code or remove the ignore marker.

- Keep Starhull/crisp bitmap sizing and shared [ui_theme.tres](../themes/ui_theme.tres) styles. Use supplied mapped bars/panels without distorting source artwork; cache textures outside draw loops.
- Concise, necessary text only; prefer recognizable instruments/icons and in-world cues. Preserve names, exact costs, important consequences and errors. No hover tooltips, Tab/arrow UI cycling or focus outlines; caret/gameplay/canvas controls remain allowed.
- Use the shared X for windows. Preserve actual supported-resolution layout and accessible native input. Formation refreshes retain pan/zoom; do not auto-fit.
- Ship-art mounts select/refit equipment. Beside-ship callouts are display-only: full fitted name, or empty size/type; no wrapping/truncation or duplicate headings over artwork. Reserve name widths so changing fits does not rescale ships.
- Idle/selected art has no equipment-outline boxes. Selected-part details replace ship summary in reserved space; blank/empty selection restores it without shifting geometry.
- Deterministic area starfields derive from campaign seed plus area identity, not saved transient star arrays. Keep dark space, stationary twinkles/click effects and original art.
- Station/service symbols, destination names, costs/ETA and access restrictions remain legible. No explanatory replacement panel merely to justify omitted text.
- Missing art intentionally uses a pink square; missing audio uses `dialogue_type.mp3` via [placeholders.gd](../scripts/placeholders.gd). Do not substitute unrelated art to hide missing assets.

## Validation

Use the smallest relevant cases/files; [tests/README.md](../tests/README.md) provides isolated invocation examples. Full baselines/all-campaign/native acceptance require explicit user request. Historical counts/logs and superseded implementation details are archived under [history/](history/); they are not current behavior or retest mandates.
