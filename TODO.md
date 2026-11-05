# Current slice TODO

The current D4/D5 implementation is delivered. Open dependencies remain below; D4's random-encounter effect is deferred. Preserve the implemented travel/research/trade -> battle -> report/refit loop.

Current behavior: [docs/HANGAR.md](docs/HANGAR.md). Workflow: [AGENTS.md](AGENTS.md). Delivered work: [COMPLETED.md](COMPLETED.md).

## D4 - Research that you can feel

Research changes fleet behavior, not access to ordinary equipment. Keep the earned Prismatic Lasers, Siege I, Bastion I, Field Engineering and Civil Hospitality effects. Do not grant completed research/branches to make starting fits legal.

- [ ] Fewer random encounters: deferred until a random-encounter system exists; do not suppress authored/story encounters.

## Individual experience and loadout-only fitting

- [ ] Review [the five-level proposal](docs/SHIP_EXPERIENCE.md): cumulative XP 0/40/100/180/300, contribution weights, 36 candidate presets and rookie membership. Five chevron ranks, one/two starter options and at most four total presets per chassis are confirmed; later unlocks must offer meaningful strategy or clear power.
- [ ] After balance review, implement persistent individual XP and exactly-once battle/income awards, chevron badges, level checks for refits/purchases/groups and focused verification. XP follows ships on reassignment; never downgrade a veteran because a group average falls. Player fitting is already complete-loadout only.

## Battle feel decisions

- [ ] Discuss Ion Pulse after [the battle feel audit](docs/BATTLE_FEEL_AUDIT.md): it is the only offered active ability, has 300 cast range versus 900 emitter range, situational effects and a shared 24-second cooldown. Decide reach and intended role before changing it.
- [ ] Decide the desired first research-choice milestone and whether the Defensive starter should qualify for offensive research. Measured first victory leaves 7.57/20 RP; initial matching pool contains six utility/defensive cards. Preserve matching-equipment eligibility until a specific change is approved.

## Art dependency

- [ ] Recognizable derelict/distress/anomaly/gate and remaining equipment artwork is not supplied/approved yet. Preserve full names, effects and intentional pink missing-art markers; do not substitute unrelated ship/asteroid art or remove identifiers. Existing named map labels and fitted-equipment text fallbacks stay.

## Deferred reference, not active scope

The [older continuous-world expansion plan](docs/history/plans/CONTINUOUS_EXPEDITION_2026_11_04.md) preserves the former E01-E14 tasks, design contracts and unresolved work. It is archived, **not completed** and not a requirement for this slice. Procedural world cells/POIs, rescue/tow, seamless in-world combat, a new checkpoint format and broad performance/soak campaigns need an explicit scope decision before being resumed.

Keep [the story specification](docs/STORY_SPEC.md) as narrative reference; do not expand plot, branches, endings or Act II/III during D4/D5.
