# Current slice TODO

The current D4/D5 implementation is delivered. Open dependencies remain below; D4's random-encounter effect is deferred. Preserve the implemented travel/research/trade -> battle -> report/refit loop.

Current behavior: [docs/HANGAR.md](docs/HANGAR.md). Workflow: [AGENTS.md](AGENTS.md). Delivered work: [COMPLETED.md](COMPLETED.md). Next direction: [scenario architecture](docs/SCENARIO_ARCHITECTURE.md).

## Scenario architecture

Phases follow [the plan](docs/SCENARIO_ARCHITECTURE.md#20-implementation-phases). Each phase keeps the game playable, deletes what it replaces and ends with focused tests. Saves may break.

- [ ] P1 Content foundation:
  - [ ] Pack manifests/loader (`res://packs`, `user://packs`), dependency order and Problems.
  - [ ] Schema registry and validator (JSON Schema subset with `x-ref`/`x-expr`/`x-text`/`x-asset`/`x-editor`), `parent`/`abstract` inheritance and patch defs.
  - [ ] `DefDatabase` and static `Content` API; convert `data/*.json` into `packs/core` and `packs/leviathan`, repoint catalog readers, delete `data/`.
  - [ ] `tools/validate_packs.gd`, `tools/export_schemas.gd` and VS Code schema mapping.
- [ ] P2 One authority: move research filters, enemy costs/templates, trade fares, support/ability constants, starting fleet and equipment effect text into defs; explicit IDs instead of array order; stable seeds; delete unused legacy readers.
- [ ] P3 Run core: run document, transactions, hooks, effects, stats, pressures (Swarm), chronicle skeleton, `user://runs/<id>/` with frozen content and a run list; split `hangar_state.gd` into systems.
- [ ] P4 Story engine: quests, casting by bind/filter, scenes, templates, grammars, response lines, rules, journal/markers; Act I re-expressed as quests.
- [ ] P5 Editor v1: shell, schema forms, Quest/Story Lab/Text workspaces, Playtest overlay and main-menu entry.
- [ ] P6 Galaxy, scenarios and casting: generator stages, pins, spawn casting, knowledge/rumors, `GalaxyView` and scenario browser.
- [ ] P7 Director, factions, fronts and encounters: profiles, threat points, encounter composer, standing/territory, human enemy fleets, incidents, Adventure mode and Forecast.
- [ ] P8 Depth: Leviathan Act II skeleton, Homeward with captains/politics, Captain's Log, Battle Bench calibration and base-library targets.
- [ ] P9 Packaging and Workshop: local install/export, read-only sources, GodotSteam publishing and subscription.

## D4 - Research that you can feel

Research changes fleet behavior, not access to ordinary equipment. Keep the earned Prismatic Lasers, Siege I, Bastion I, Field Engineering and Civil Hospitality effects. Do not grant completed research/branches to make starting fits legal.

- [ ] Fewer random encounters: deferred until the director exists (P7); do not suppress authored/story encounters.

## Individual experience and loadout-only fitting

- [ ] Review [the five-level proposal](docs/SHIP_EXPERIENCE.md): cumulative XP 0/40/100/180/300, contribution weights, level assignments for the 36 implemented presets and rookie membership. Five chevron ranks, one/two starter options and at most four total presets per chassis are confirmed; later unlocks must offer meaningful strategy or clear power.
- [ ] After balance review, implement persistent individual XP and exactly-once battle/income awards, chevron badges, level checks for refits/purchases/groups and focused verification. XP follows ships on reassignment; never downgrade a veteran because a group average falls. Player fitting is already complete-loadout only.

## Battle feel decisions

- [ ] Discuss Ion Pulse after [the battle feel audit](docs/BATTLE_FEEL_AUDIT.md): it is the only offered active ability, has 300 cast range versus 900 emitter range, situational effects and a shared 24-second cooldown. Decide reach and intended role before changing it.
- [ ] Decide whether the Defensive starter should qualify for offensive research. Its matching pool contains five utility/defensive cards; preserve matching-equipment eligibility until a change is approved. The approved ordinary M-lab opening now reaches its first choice by the Protocol; the earlier 7.57-RP first-victory measurement predates the Act I expansion.

## Art dependency

- [ ] Recognizable derelict/distress/anomaly/gate and remaining equipment artwork is not supplied/approved yet. Preserve full names, effects and intentional pink missing-art markers; do not substitute unrelated ship/asteroid art or remove identifiers. Existing named map labels and fitted-equipment text fallbacks stay.

## Deferred reference, not active scope

The [older continuous-world expansion plan](docs/history/plans/CONTINUOUS_EXPEDITION_2026_11_04.md) preserves the former E01-E14 tasks, design contracts and unresolved work. It is archived, **not completed** and not a requirement. Procedural worlds, factions and the new run format now follow [the scenario architecture](docs/SCENARIO_ARCHITECTURE.md); do not resume the archived tasks.

Keep [the story specification](docs/STORY_SPEC.md) as narrative reference. The approved [Act I expansion](docs/ACT_I_EXPANSION_PLAN.md) is delivered in [COMPLETED.md](COMPLETED.md); Act II/III, infestation branches and endings remain outside implementation scope.
