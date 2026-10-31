# Physical hangar

Current scope is a medium vertical slice focused on UI/UX, using the existing systems and equipment. Follow V1-V6 in TODO.md. Further equipment tiers, bespoke boss phases and full-campaign depth are deferred for a later story-led pass. The implementation and test history below describes existing work, not a requirement to finish all that depth before reviewing the slice.

The actual campaign now uses the hangar. Start a new run from the main menu; Continue resumes a physical hangar checkpoint. The previous material run and blueprint libraries remain separate. There is no active ship-design screen or material wallet.

## Ownership and transactions

- Each chassis has fixed mounts with exact S/M/L/XL size matching. Most accept any same-size equipment; restrict only clearly forward weapon or rear engine/defense mounts. See [MOUNT_RULES.md](MOUNT_RULES.md).
- Equipment has a unique inventory ID and persistent HP. A mount references that instance; free transfers move it between ships or stock. Replacing an item returns the old item to stock.
- Buy ships/equipment at inhabited shipyards. Research unlocks equipment purchases/fitting. Winning a battle also awards one deterministic, usable equipment instance. Loot is committed with the battle outcome and cannot be claimed twice.
- Credits pay for purchases and repairs. Stock equipment and non-flagship chassis can be sold/salvaged immediately. Salvaging returns damaged equipment to stock. The flagship cannot be salvaged or bought a second time.
- The supplied `flagship_basic.png` is the required starting flagship. Draft command budget: 12. Standard chassis consume command points; all owned ships deploy. No reserves or deployment-capacity system.

The initial art-to-mount maps, prices, chassis health/mass/thrust, equipment HP and command costs are draft tuning in `data/slot_chassis.json` and `data/slot_equipment.json`. The flagship currently has nine mounts. Original artwork is unchanged. Built-in command centers/engines have separate health. No slot bonuses or legacy adjacency buffs are applied; unsupported items are omitted from active purchases/research grants.

## Combat, travel and trade

Chassis images appear in hangar, formation, map preview, battle and reports. Equipment weapon mounts use the authored image positions. Shields absorb damage first. Unshielded component hits split damage equally between component and chassis; bare hull hits damage the chassis. Chassis survives at exactly zero and dies below zero; losing its command center also destroys it. Flagship destruction ends the run even when escorts remain. Repairs restore surviving ships and their installed hardware, without resurrecting destroyed ships.

Operational Lab I / II / III produce 1 / 2 / 3 RP/day respectively, plus 0.5 RP/day for the fleet. Travel normally takes 2-4 days. Departure freezes the research yield; successful arrival settles it once. Battle duration yields no research. The single pannable tree uses inline details/focus and fractional progress. The production panel lists the lab mix, and equipment/research details show the rank rate. Existing pending checkpoints keep their previously frozen numeric yield. Research is progression, not shop currency.

Passenger and cargo contents belong to equipment inventory IDs. A cabin boards four passengers for an inhabited destination; a hold loads ten goods when leaving an inhabited port. Inhabited arrival automatically pays passenger fares and cargo sales. Occupied hardware must deliver before being unequipped. Destroyed hardware/hosts lose their contents; passenger casualty fees settle once and can create credit debt. Repairs do not refill lost loads. No additional Port/Story or management windows are introduced.

## Runtime and persistence

- Autoload: `scripts/hangar_state.gd`, independent of the removed material runtime.
- Physical ships: `HangarShip`; combat retains the shared simulation engine while using image mounts and chassis HP.
- Campaign UI: `scenes/game_map.tscn` / `hangar_screen.gd`; actual shared inventory choices are in `hangar_canvas.gd`.
- Active research: `HangarResearch`, using a filtered catalog without extraction or undefined adjacency bonuses.
- Trade: `HangarTrade`, keyed by equipment ID rather than unstable component/slot indices.
- Checkpoint: `user://hangar_run.json`, `physical_hangar` version 1, validated and written with `AtomicRunStore` checksums, staged generations and backup recovery.

Purchases/refits/sales propose a complete state and commit before exposing it. Failed persistence leaves credits/ownership unchanged. Battle settlement commits health, lost equipment/loads, credit rewards, loot, research and location together. Pending Continue restarts the deterministic encounter from its saved departure snapshot. Support expenditure persists across withdrawn attempts. Older `run_checkpoint.json`, square/hex libraries and slot blueprint libraries are never overwritten or guessed into physical ships.

The square builder, material shop/fleet panel, blueprint-library dialog, main-menu Designer and free slot Designer screens have been removed. The disconnected material runtime is removed. Read-only checkpoint/library schemas live under `scripts/legacy/`; shared DTOs remain for archive decoding and combat regression tests. Current code uses `SaveValidation` for generic wire checks. Historical tests are preserved as text outside Godot imports. See [LEGACY_BOUNDARIES.md](LEGACY_BOUNDARIES.md).

## Validation

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_baseline.ps1 -Native`. It uses isolated APPDATA and the installed Godot console. The current baseline covers the physical game plus shared combat/research/archive readers. The earlier grid-era runner is preserved under `docs/history/run_baseline_PRE_HANGAR.ps1.txt`; its retired UI expectations are not current hangar requirements.

Hangar-specific checks cover exact fitting, physical ownership, credit charging, transfers, command limits, hull/component/built-in health, zero-HP destruction boundaries, flagship defeat with a surviving escort, repair, loaded trade/losses, malformed data, backup recovery, failed-save rollback, duplicate settlement, deterministic loot, departure research and refit timing. Native UI checks cover real OptionButton callbacks, shared X windows, no overlapping mounts, theme/focus/tooltip preferences, actual battle/report integration and 640x360 / 1280x720 / 1920x1080 layouts. Captures are in `.local/hangar/ui-*.png`.

Nine natural full-route playthroughs now pass: combat, trade and science policies across three seeds, totaling 126 battles with normal purchases, repair costs and research. See [HANGAR_PLAYTEST.md](HANGAR_PLAYTEST.md). The earlier forced-outcome traversal remains a persistence/connectivity test. Neither test establishes unfinished Brood Architect/Leviathan mechanics; those and broader balance remain in TODO.md.

Verification: the latest mount-policy pass has twelve current baseline suites passing; the native UI suite passed 313 checks, including all six chassis at three resolutions, main-menu Continue and ranked-lab production/details. Physical-state, persistence and traversal suites passed 47, 89 and 193 checks respectively. A 13-ship refit fixture completed each transaction in under 40 ms in the recorded runs. After the mount-policy pass, static runtime resource validation found 109 references with none missing. Existing Windows certificate-store and renderer shutdown diagnostics are still emitted by this Godot environment.

Gravitic Snare / Disruption II are deferred because their old ability path is not wired into physical-ship/credit transactions. They are hidden from new purchases, research focus and loot. Previously earned research and item instances remain loadable; inactive fitted items must be unequipped before departure and can be sold. This avoids silently invalidating older physical saves.

Six core intermediates now operate in the physical model: ship-wide stacking magazines/computers, railguns, finite interceptor/bomber bays and automatic command marks. See [INTERMEDIATE_EQUIPMENT.md](INTERMEDIATE_EQUIPMENT.md) for conservation rules, exact mounts and test limits. ECM/Phase remain unfinished. The current runner has twelve suites.
