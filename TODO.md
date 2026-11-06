# Current slice TODO

The current D4/D5 implementation is delivered. Open dependencies remain below; D4's random-encounter effect is deferred. Preserve the implemented travel/research/trade -> battle -> report/refit loop.

Current behavior: [docs/HANGAR.md](docs/HANGAR.md). Workflow: [AGENTS.md](AGENTS.md). Delivered work: [COMPLETED.md](COMPLETED.md).

## Proposed equipment, events and Act I expansion

The requested review and plan are in [ACT_I_EXPANSION_PLAN.md](docs/ACT_I_EXPANSION_PLAN.md). This authorizes planning; the proposed hardware, tuning and story changes below are not implemented or approved balance. It supersedes the old D4/D5 restriction on *planning* Act I content, not the restrictions on Act II/III or retired systems.

- [ ] Settle the plan's concrete design choices: use the first refueling stop as Port Meridian, retain the Warden as the demo's closing gate battle, select the four proposed equipment candidates, and reconcile their complete presets with the existing four-per-chassis progression proposal. Resolve the first research-choice milestone before assigning final event RP.
- [ ] A1 — Add only the authored-story support needed for departure events, causal/exclusive conditions, battle-outcome flags and Meridian service availability. Preserve atomic saves, pending encounters, route state and exactly-once outcomes; verify the focused cases in the plan.
- [ ] A2 — Author the seven Act I main beats, including optional Meridian defense and outcome-specific aftermath. Gate every direct alien encounter behind the station incident; make both helping and leaving reach the Protocol and existing Warden finale.
- [ ] A3 — Add the eight specified side-event briefs using existing locations/rewards where possible. Keep foreshadowing incomplete, noncombat exits available, concise choice consequences and one-use receipts. No random-encounter scheduler.
- [ ] A4 — Implement the selected combat equipment and complete presets, then the selected civic equipment with metadata-driven load capacities. Validate actual effects, mount legality, research matching, free-refit tradeoffs, UID loads and atomic group operations. Do not add every candidate preset on top of the 36-preset proposal.
- [ ] A5 — Run bounded pacing checks for the changed Meridian branches and equipment comparisons, plus focused native event/loadout checks with isolated APPDATA. Record actual credits/fuel/missiles/RP and first-choice timing; review missing-art dependencies and current-doc discrepancies. Move only verified deliveries to COMPLETED.md.

## D4 - Research that you can feel

Research changes fleet behavior, not access to ordinary equipment. Keep the earned Prismatic Lasers, Siege I, Bastion I, Field Engineering and Civil Hospitality effects. Do not grant completed research/branches to make starting fits legal.

- [ ] Fewer random encounters: deferred until a random-encounter system exists; do not suppress authored/story encounters.

## Individual experience and loadout-only fitting

- [ ] Review [the five-level proposal](docs/SHIP_EXPERIENCE.md): cumulative XP 0/40/100/180/300, contribution weights, 36 candidate presets and rookie membership. Five chevron ranks, one/two starter options and at most four total presets per chassis are confirmed; later unlocks must offer meaningful strategy or clear power.
- [ ] After balance review, implement persistent individual XP and exactly-once battle/income awards, chevron badges, level checks for refits/purchases/groups and focused verification. XP follows ships on reassignment; never downgrade a veteran because a group average falls. Player fitting is already complete-loadout only.

## Battle feel decisions

- [ ] Discuss Ion Pulse after [the battle feel audit](docs/BATTLE_FEEL_AUDIT.md): it is the only offered active ability, has 300 cast range versus 900 emitter range, situational effects and a shared 24-second cooldown. Decide reach and intended role before changing it.
- [ ] Decide the desired first research-choice milestone and whether the Defensive starter should qualify for offensive research. Measured first victory leaves 7.57/20 RP; after removing Logistics, its matching pool contains five utility/defensive cards. Preserve matching-equipment eligibility until a specific change is approved.

## Art dependency

- [ ] Recognizable derelict/distress/anomaly/gate and remaining equipment artwork is not supplied/approved yet. Preserve full names, effects and intentional pink missing-art markers; do not substitute unrelated ship/asteroid art or remove identifiers. Existing named map labels and fitted-equipment text fallbacks stay.

## Deferred reference, not active scope

The [older continuous-world expansion plan](docs/history/plans/CONTINUOUS_EXPEDITION_2026_11_04.md) preserves the former E01-E14 tasks, design contracts and unresolved work. It is archived, **not completed** and not a requirement for this slice. Procedural world cells/POIs, rescue/tow, seamless in-world combat, a new checkpoint format and broad performance/soak campaigns need an explicit scope decision before being resumed.

Keep [the story specification](docs/STORY_SPEC.md) as narrative reference. The Act I proposal above is the explicitly requested planning scope; Act II/III, infestation branches and endings remain outside implementation scope.
