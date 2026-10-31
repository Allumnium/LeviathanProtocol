# Leviathan TODO

Current model: a physical hangar with owned chassis and individual equipment instances. Credits are the only spendable resource. No square/hex building, materials, equipment recipes or construction regions. Optional extras remain deferred.

## Confirmed design

- Six supplied chassis: the required flagship_basic.png flagship, plus Corsair, Fighter, Transport, Frigate and Drone. Slot positions/types/sizes remain draft content for review.
- Slots use Offense, Defense, Tech or Civic and S/M/L/XL. Require exact type AND size matches. Smaller equipment does not fill larger slots.
- Mount dropdowns equip owned equipment instances from a shared inventory. Transfers are free. Buy researched equipment/chassis at shipyards; battles also grant equipment loot. No design drafts, named blueprints or free copies.
- No functional equipment orientation. Weapons aim automatically; thrusters provide ship-wide thrust.
- Exactly one flagship, mandatory every battle. Its command budget limits the other ships; no reserves, design-family limits or old act-based deployment capacity. Flagship loss ends the run.
- Every chassis includes a fixed command center. Built-in equipment is destructible/repairable. Chassis HP is one pool, alive at zero and destroyed strictly below zero. Unshielded equipment hits split half to component/half to chassis; bare structure takes full damage. Command-center loss kills the ship.
- Use credits for purchases and repairs; equipment transfers are free. No material inventory, wildcard exchanges, ore/mineral payouts or refinery systems in the replacement model. Cargo goods and passengers remain distinct systems.
- Research stays one pannable tree with major branches and inline details/Set Focus. No Foundation node or grant modal. Completed nodes have a green check; partial nodes show X / Y. RP belongs only in the header.
- Travel research: (Lab I + 2 x Lab II + 3 x Lab III + 0.5) RP/day times travel days, typically 2-4. Freeze departure inputs, retain fractions/focus, settle once at arrival. Battle time never generates RP.
- Starhull/shared theme, minimal prose, no hover tooltips and no Tab/arrow focus navigation or focus boxes. No Port/Story buttons or duplicate fleet stats in the top bar.

## Hangar migration

- [x] S1/C1: Preserve the supplied art and typed mount catalog; retire hex/square editors and prototypes. The prior standalone slot Designer is now retired too.
- [x] S2: Replace the actual campaign with a physical hangar, shared instance inventory, free transfers, shipyard purchases, equipment loot, credits-only repairs/sales and immediate salvage. Start with the supplied flagship; enforce command and no-reserve rules.
- [x] S3: Render actual chassis in hangar/formation/map/battle. Persist component, built-in and chassis health; implement shield-first hits, half damage split, bare-hull hits, zero-HP boundary and mandatory flagship defeat. Defer undefined slot/adjacency bonuses rather than selling inactive effects.
- [x] S4: New atomic physical-run checkpoints, unique ownership, backup recovery, save-failure rollback, exactly-once battle settlement, travel research and equipment-instance trade loads. Preserve old save namespaces. The active runtime no longer inherits the material GameState; removed embedded builder/library/free-Designer UI.
- [x] S5a: Native dropdown/window checks at 640x360, 1280x720 and 1920x1080; all-act travel/settlement traversal; six natural opening fights; load/repair/loss/refit checks and interaction timing. See docs/HANGAR.md for evidence and limits.
- [x] S5b: Initial catalog/mount opportunity-cost review and nine natural full-route runs (combat, trade, science; three seeds; 126 fights). No free credits/research or forced outcomes. Rank II/III labs now produce 2/3 RP/day, with matching UI and preserved pending yields. Defer the inactive Gravitic Snare ability purchase/focus/loot while keeping older research/items readable and removable. Current content is traversable; broader balance and unfinished bosses remain milestones 60/65/67/70. See docs/HANGAR_PLAYTEST.md.
- [x] C2: Remove the disconnected material GameState and unused builder/formation/upgrade/window code. Preserve 46 retired test/capture scripts as text outside Godot imports. Isolate historical checkpoint/economy/library schemas under scripts/legacy, remove archive writers and retain read-only square/hex/prototype recovery. Extract shared SaveValidation and skip square catalog/animation initialization for physical previews/battles. Nine baseline suites, 66 archive checks and 289 native UI checks pass. Shared DTOs remain for decoding/combat regressions; see docs/LEGACY_BOUNDARIES.md.

The playable entry is NEW RUN -> Hangar. CONTINUE resumes physical hangar checkpoints; old material runs remain separate. Shipyards sell physical ships, not bulk blueprint construction orders. Passenger/cargo trade remains core. RP remains travel-generated progression. Slot bonuses and adjacency equipment stay deferred.

## Remaining core content

Original milestone IDs are retained for historical cross-reference; all implementations must use slots and credits.

- [x] 56a: Magazine/Railgun, Flight Deck/Bomber and Uplink/Computer are physical, research-gated equipment. Magazines/computers support all host weapons and stack as requested. Finite UID-based carrier reserves persist across retries/transfers; craft have payload/lifetime/entity limits, point-defense counters and source-loss handling. Command marks respect visibility. 143 carrier checks, 155 intermediate checks, six natural Act II combat fixtures and the eleven-suite baseline pass. See docs/INTERMEDIATE_EQUIPMENT.md; broad tuning remains 61/67/70.
- [ ] 56b: Finish ECM Suite / Phase Drive using physical ships and credits: bounded lock breaks, target coordination, valid-space/range checks, source loss, research gates and persistent cooldowns. No optional abilities or adjacency bonuses.
- [ ] 58: Intermediate passenger/science content: Luxury Suites, Analysis Array and bounded support effects. No material refinery requirements.
- [ ] 59: Act II enemy combinations with readable roles and counters, independent of player fleet strength. Optional cloak/environment variants remain deferred.
- [ ] 60: Brood Architect: finite hangars, repair without resurrection, clear telegraphs, persistent organ loss and one-time progression rewards. No old capacity unlock.
- [ ] 61: Research pacing through Act II using planned travel days and ranked lab production + 0.5 RP/day. Compare science/tourism/trade routes at equal credit investment; review old costs and rank rewards.
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
