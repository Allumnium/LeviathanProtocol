# Physical hangar

Current scope is a continuous-expedition vertical slice using the existing physical systems, equipment and UI. Follow E01-E14 in [TODO.md](../TODO.md). Further equipment tiers, bespoke boss phases and full-campaign depth are deferred for a later story-led pass. The implementation and test history below describes existing work, not a requirement to finish all that depth before reviewing the slice.

New Run and Continue use the existing hangar screen, with Fleet as the continuous travel page. New expedition checkpoints use `user://expedition_run.json`; the temporary payload still embeds expedition state in the physical-hangar-v2 envelope. The previous physical/material runs and blueprint libraries remain separate. There is no active ship-design screen or material wallet.

## Expedition station services

Every management tab shares a compact top-row panel with Pause, Play (1x) and Fast Forward (10x) icons beside the existing tabs, research and wallet. There is no Clear button, destination dropdown or travel-control overlay over the Fleet canvas. Fuel, refueling and save retry remain in the footer. Play/fast-forward clear only user pause, never mandatory interruption/save-error pause. Travel remains live when changing management tabs.

At the initial station, Depart opens a story-neutral destination-choice modal. Every arrival opens the same modal automatically, explaining exploration or station services for each onward option. A destination must be chosen before the modal closes; a saved pending-choice flag holds the core simulation, not just the screen. Choosing a destination commits the route before clearing the flag and closing; a failed save keeps the dialog open with error/retry controls. Existing user/event pause reasons remain intact. Continue restores unfinished initial, station and POI choices; a manually stopped route is not treated as an arrival. Continue also checkpoints user pause while retaining position and requested speed, so resuming the game never starts unacknowledged movement. Rich story-specific options are deferred. Map remains an informational visual scaffold, not a free-choice destination picker.

Buying chassis/equipment, fitting, transfers, unequipping, selling stock, salvaging chassis and paid repairs require docking at a station whose declared services include `shipyard`. Refueling requires the separate `refuel` service. The actual expedition state and station position determine access, never the old current-node value. A settlement can refuel without offering a shipyard; stopping or pausing in space, reaching a POI or passing a station does not grant docking privileges.

The backend validates service access before mutation or saving. Unavailable controls retain the existing layout with a short reason. Leaving a shipyard cancels equipment drags, pending inline sales, shopping and salvage confirmations; arriving restores applicable actions in place without rebuilding the Fleet view or resetting its pan/zoom. Equipment/ship inspection, research focus and formation edits remain available underway. User pause permits docked services; combat and save-error pause block them.

Run [the baseline](../tests/run_baseline.ps1), optionally with `-Native`, using its isolated APPDATA. [Station-service tests](../tests/test_expedition_services.gd) cover access, unchanged state on rejection, Continue, refueling-only stations and UI cancellation/restoration.
[Arrival tests](../tests/test_expedition_arrival.gd) cover required choices, Continue pause, station/POI reloads and failed-save/retry transactions in headless and native runs.

## First travel interruption

The story-neutral [event catalog](../data/expedition_events.json) currently has one derelict signal at 80 cumulative travel NU. It interrupts cruise on any management tab without switching scenes. Movement and fuel clip at the trigger regardless of speed; the simulation returns to 1x and holds an encounter-specific pause until the player chooses Investigate or Continue Course. This required decision has no dismiss button. Existing user and other mandatory pauses remain independent.

Continue Course retains the current destination. Investigate routes from the current position to the existing derelict POI and remembers the original destination. At POI arrival, the regular required destination modal labels that original option Resume; the player must select an onward route, and any explicit choice clears the saved return target. This is a navigation fixture, not salvage/story content: no reward or combat is generated.

The pending decision is committed before the modal appears; the choice and one-time receipt are committed before it closes. Admission or choice save failures roll back or retain the pending decision with explicit retry feedback. Continue restores unfinished decisions and detour return targets. Physical checkpoint validation rejects unknown pending events and unavailable return destinations before applying state.

[Signal tests](../tests/test_expedition_events.gd) cover speed/frame independence, exact distance/fuel clipping, independent pauses, duplicate submissions, fuel priority, combat deferral, failed saves, reloads, ship identity and real pointer choices. The baseline includes headless and optional native coverage at 640x360, 1280x720 and 1920x1080. Random encounters, competing-event priorities, radius/arrival triggers, combat integration and actual detour rewards remain deferred.

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

Shop, Fleet and Ships use the supplied `Progress_Cp` / `Progress_Cp_Bg` comparison bars for hull, maneuverability, mass and shields. Maneuverability consolidates speed, acceleration and turn rate using their chassis-wide means as weights; average base maneuverability scores 50. Thrust/mass feed those mechanics without double counting. Each displayed stat uses all base chassis as its reference range, linearly mapping minimum to 10% fill and maximum to 100%; real outfitted/damaged values are clamped to that display range without changing state. Ship-description numbers are rounded integers; calculations retain full precision. Equipment has no HP/condition UI. Engine/command-center descriptions are omitted. See [MOUNT_RULES.md](MOUNT_RULES.md).

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

Battle controls offer Pause, 2x and 5x speed. Speed toggles are mutually exclusive;
turning off either restores 1x. Pause clears fast speed, while choosing a speed
unpauses. The selected speed persists in settings (older 2x preferences still
load), and Settings pauses all speeds. Simulation continues to use fixed ticks;
finishing-shot slow motion multiplies the chosen speed. Retreat is no longer
offered in the battle UI; shared withdrawal/replay mechanics remain unchanged.

Victory uses the supplied Victory background, badge, rays, light line and title,
with compact integer-valued ship statistics in themed reward cards. Names have
the full details-column width; damage is no longer an unbounded segment flow.
Loot/rewards and surviving-hull repair quotes retain their settlement behavior.
The result overlays a dark backdrop, while the shared top-right Settings remains
available. Its auto-camera toggle uses Switch_Off/Switch_On with preserved aspect;
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

Research Lab I uses `assets/equipment/research_lab_1_d.png` with its supplied normal, height, specular and occlusion maps through the same renderer. Stock thumbnails, fitted art, drag previews, Fleet and battle preserve its aspect ratio and transparency. Lab II/III retain text fallback; research production, fitting rules and saved instances are unchanged.

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

Hovering installed equipment on the ship art shows a white silhouette glow aligned to its fitted sprite, including mount-anchor offsets. Empty mounts and display-only side labels do not show this glow. Equipment without artwork highlights its floating name instead. Sprite glows are hidden during equipment drags so compatible-target highlights remain clear.

Floating equipment names align toward the ship: right-aligned on the left rail
and left-aligned on the right rail, keeping each name next to its connector line.

Inline icons use the surrounding font height and derive their width from the source texture aspect ratio, rather than forcing square dimensions. Header/shop/report icons, inline sale coins and close-button artwork likewise preserve their source proportions.

Settings uses an embedded 304 x 186 modal (304 x 218 when Quit to menu is available), sharing the main viewport's bitmap-text pixel scale rather than a separate native window's smaller text. Audio rows and the centered Quit to menu button are compact. Every active scene has a top-right gear; battle settings pauses simulation, result-delay progression and camera updates until closed, while retaining the player's existing pause/speed mode.

## Combat, travel and trade

### Beacon routes and Swarm Intensity

New runs retain all three acts but use a bidirectional, noncrossing beacon network with irregular beacon positions. Only connected, unlocked destinations can be reached; backtracking does not relock sectors already opened by boss victories. Route connections are plain lines rather than directional arrows. Existing physical checkpoints without navigation data continue using their original forward-only graph, encounters and tuning; no save conversion is guessed.

Swarm Intensity starts at zero and rises by one point per travel day, including backtracking and repeat departures. Time spent in menus or battles does not add pressure. The map shows current intensity and the next journey's increase. Initial tuning adds 0.5% enemy hull, shields and weapon damage per intensity point, including the Warden's existing lance and the final Leviathan encounter; no new phases or enemies are introduced. Enemy composition, rewards, telegraphs and research rules remain unchanged. First departure to a hostile beacon freezes its strength; retries and Continue retain that snapshot while further travel still raises pressure for unentered encounters. Cleared beacons do not spawn the same encounter or pay its rewards again. Operational cargo/passenger travel remains available on revisits.

Each act has a small broken-relay encounter with inline choices in the existing map detail panel. Relay its data to the marked beacon for 60 credits and a four-point intensity reduction, or disrupt the signal immediately for a three-point reduction. Choices and quest rewards settle once through the same atomic transaction as ownership, credits and travel. Active destinations have a gold ring; completed quest feedback appears at its destination. Quest data is not a physical equipment load. The pressure rate, strength multiplier and quest rewards are drafts for route playtesting and V4 tuning.

`test_swarm_navigation.gd` verifies deterministic noncrossing geometry across 128 seeds, bidirectional travel, pressure, frozen retries/Continue, one-time encounters/quests, rollback, malformed-data rejection and native event layouts at the three supported resolutions. Natural playthrough policies explicitly choose forward progress now that backward routes exist. Science policies reserve the actual Lab III purchase price before buying optional hulls and take bounded research detours before the final approach when necessary, trading increased Swarm Intensity for Lab III completion and a real purchase/refit opportunity; checks require an operational Lab III alongside existing labs at a combined four RP/day or more.

Validation: all 16 baseline suites pass, including nine natural combat/trade/science campaigns reaching final victory (126 battles). Final native checks pass for swarm navigation, 2,106 hangar UI assertions and 157 polish assertions. At 640 x 360, the single encounter's Travel and both event choices fit inside the existing panel; scrolling is available only for longer accumulated quest content.

Chassis images appear in hangar, formation, map preview, battle and reports. Equipment weapon mounts use the authored image positions. Shields absorb damage first. Unshielded component hits split damage equally between component and chassis; bare hull hits damage the chassis. Chassis survives at exactly zero and dies below zero; losing its command center also destroys it. Flagship destruction ends the run even when escorts remain. Repairs restore surviving ships and their installed hardware, without resurrecting destroyed ships.

In Fleet and battle, non-flagship chassis render at one-quarter width and height; the flagship retains its existing scale. Fitted equipment, formation hit targets/selection glows, battle damage markers and weapon launch positions follow that presentation scale. Formation spacing, combat collision radii, ship statistics and saves are unchanged. Ships fitting continues to fit each chassis independently to the available editor area.

Operational Lab I / II / III produce 1 / 2 / 3 RP/day respectively; there is no fleet baseline. Travel normally takes 2-4 days. Departure freezes the research yield; successful arrival applies it once to the focused project, retaining fractional project progress. With no focus, or after a project completes, unused output is discarded; no RP balance is stored or shown. Battle duration yields no research. The single pannable tree uses inline details/focus. The production panel lists the lab mix, previews focused-project allocation, and equipment/research details show the rank rate. Existing pending checkpoints keep their previously frozen numeric yield.

Fleet, Ships and Map tabs align left in the header and use `Btn_CharacterMenu_n`/`_p`, with lighter hover and distinct pressed states. These three tabs are 80 x 30 viewport units, preserving the cropped artwork's natural aspect ratio. Research is a wider tab immediately before credits, combining its compact 12-pixel icon, 10-pixel technology name (without a prefix), and half-width supplied `Progress_CharacterAttribute` bar showing actual fractional progress against the project's requirement. Clicking anywhere in that tab, including its icon, text or bar, opens Research. With no focus, it reads `Choose Research`, hides the bar and gently fades toward white and back once per second; selecting focus stops the pulse immediately. Long project names wrap within the Research button at narrow widths rather than clipping or narrowing the other tabs. Credits align right immediately before the Settings gear, which uses circular `Btn_RandomName_n`/`_p` artwork and opens Settings without leaving the run. The flagship roster flag is one-third its original size. Tab switches use the accept sound; roster and Fleet-art ship selection use the former tab-switch sound.

All panels and shared modals inherit the supplied nine-sliced `Panel_StoreItem` surface. Fitting callouts are frameless floating white text at the shared 10-pixel font size, with white connector lines to installed equipment. The texture is imported at half size with eight-pixel slices, retaining small crisp chamfers that fit inside the close artwork rather than protruding behind it. Shared panel/modal close controls use `Btn_ClosePanel_n` with a lighter hover tint and `Btn_ClosePanel_p` when pressed. Atlas crops remove transparent artwork padding so the visible button sits one viewport pixel from the panel's top and right edges; source textures remain unchanged. Boolean settings and shop checkboxes inherit `Checkbox_Off`/`Checkbox_On` from the shared theme, imported at 16 pixels without changing source artwork. Fleet offers only Buy Chassis; Ships offers only Buy Equipment. Each roster button toggles its corresponding embedded center panel; changing tabs closes buying. No internal mode buttons remain. Equipment buying shows the current shared stock in the right panel; purchases and sales refresh it without closing the shop. Equipment buying defaults to Only show researched on the size-filter row; the toggle persists through purchases, filter changes and tab switches during the screen session. Shop prices use the credits icon, locked items use the science icon, and the green purchase plus is shown only when the row is purchasable.

Without a single Fleet ship selected, the detail panel retains Repair All and shows the surviving fleet's total mounted-weapon DPS, operational shields, current/max hull and operational lab RP/day. Cargo and passenger capacities appear only when positive; destroyed equipment and ships contribute no operational capacity or production.

Fitting equipment labels use the shared `MountCallout` panel variation with compact padding that fits their fixed 24-pixel height. They reuse the same panel artwork without inheriting modal-sized minimum margins; frames stay inside the card bounds and full names remain clear of the chamfers.

Starting a new run fades the main menu background image to transparent during the first second of the star-warp animation. A failed transition restores the background alongside the menu. Reduced motion has been deliberately removed from Settings, saved preferences and runtime behavior; do not reintroduce it.

Horizontal and vertical sliders inherit `Slider1_bg`, cropped `Slider1` foreground and a compact 8 x 16 handle derived from `Slider1_Btn` using nearest-neighbor sampling without its glow padding. Source artwork is unchanged. The foreground crop removes the transparent left inset. Settings audio sliders retain their native range, dragging and saved-volume behavior and align vertically with their labels. Active viewports snap canvas transforms and vertices to pixels; shared bitmap UI textures retain nearest filtering.

Research selection and focus changes preserve the tree's pan, zoom and selected node through UI refreshes. Returning to Research within the same hangar screen restores that view without fitting it again.

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

The hangar uses a visible stock list and native drag-and-drop fitting, with live ship stats. Stock and shipyard equipment purchases share multi-select category checkboxes and a two-handle inclusive S/M/L/XL size range, with no search or ordering controls. Handles can meet on a single size but never cross; S through L always includes M. Historical disjoint size preferences normalize to their inclusive span; an empty historical size selection becomes the full range. Stock and all purchases are always ordered by ascending catalog credit price. Chassis buying has no filters. Slot equipment dropdowns and the unused prototype canvas renderer are removed. See [HANGAR_DRAG_DROP.md](HANGAR_DRAG_DROP.md).
