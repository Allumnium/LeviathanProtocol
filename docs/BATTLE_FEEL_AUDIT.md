# Battle feel audit

2026-11-05. Scope: the current Defensive opening, deployment consequences, readable ship health, early purchases/research and the available active ability. No campaign sweep or balance changes beyond the user-approved missile cluster. Source: [battle simulation](../scripts/battle_simulation.gd), [abilities](../scripts/battle_abilities.gd), [active research](../scripts/hangar_research.gd), [production battle scene](../scripts/auto_battle.gd).

## Deployment has consequences

Reached the natural first encounter on seed 8302 through normal travel and authored event choices. Compared the same fleet/equipment/enemies/seed twice, restoring the saved prebattle snapshot. The second placement rotates the complete initial formation 180 degrees around its centroid, then saves it through Begin Combat. Neither case receives equipment, RP or research grants.

| Measurement | Default | Reversed wing |
| --- | ---: | ---: |
| Friendly/enemy ships | 13 / 15 | 13 / 15 |
| Outcome | Victory | Victory |
| Combat seconds | 21.23 | 20.90 |
| Friendly survivors | 13 | 13 |
| Hull damage taken | 124.75 | 71.25 |
| Damage dealt | 292.5 | 292.5 |
| First weapon activation | 8.23 s | 8.07 s |
| First living friendly/enemy pair within 300 units | 10.23 s | 11.23 s |

Placement changes repair burden: the alternative takes 53.5 less hull damage (43%). It does not change victory or losses in this example. These two layouts cannot establish a universal best formation or overall campaign difficulty. Position samples are retained in the diagnostic JSON; this audit does not prove that every initial shape remains intact throughout a fight. Existing cohesion/alignment steers squadrons while targeting and collision avoidance alter their shapes.

Recommendation: keep deployment meaningful through protection of vulnerable ships and mission geometry. Do not raise enemy counts or force rigid formations from this single comparison.

## Ship health and missile readability

Implemented small orange hull and blue shield bars below living ships on both sides. One-pixel fills and bounded widths keep the meters thin across zoom levels; dark tracks show full capacity even when empty. Owned hull uses the actual persistent hull pool. No-capacity shields omit their track; destroyed actors lose their bars and hidden opponents are not revealed. Replaced the separate boss-only hull meter to avoid duplicate bars.

The approved Missile Rack cluster is five physical missiles, 12 damage each, every eight seconds. Compared with three every five seconds, burst rises 36 to 60, nominal DPS rises 7.2 to 7.5, and sustained ammo use rises 0.6 to 0.625 per second per rack. Thirty starting missiles permit six full clusters in total across all racks drawing from the shared fleet pool. Distinct launch positions, warm missile heads and particle exhaust identify individual rounds; particles remain cosmetic.

Verified full burst hits, cooldown, two-ammo partial final cluster, no firing when empty, interception without ammo refunds and five parents producing fifteen researched fragments without extra ammo. Splitting still creates three half-damage fragments per parent; Siege II multiplies fragment damage by 1.2. Thus full-hit researched clusters can deliver 90/108 damage, with existing interception and collision rules.

Native review covered the production opening frame plus partial hull/empty shields on an owned ship, partial enemy hull/shields and a visible five-round cluster at three zoom levels/resolutions. The initial overview bars were too prominent and were reduced before final close-up review. Dense groups can still overlap; no large-fleet readability or performance claim is made.

## Active abilities currently mean Ion Pulse

Ion Pulse is the only ability granted by active, offered research. Scan, Gravity Well and Seismic Cut have underlying definitions/handlers but are filtered out of the current playable research grants; their existence in the backend does not mean players can earn them. Healing hangars, relays, command marks and Tactical Computers are automatic equipment effects.

Ion Pulse requires Disruption I and a living installed Ion Emitter. It interrupts a target's charge and suppresses shield recovery for four seconds, with no direct damage or resource cost. Cooldown is 24 simulation seconds shared fleet-wide: more emitters provide more possible origins, not more simultaneous charges. It defaults to manual in production; Auto, source selection and Pause Aim already exist. Deployment freezes casting/cooldowns, and Continue restarts the encounter rather than restoring a mid-fight cooldown.

Two concerns:

- The emitter now reaches 900 units, but Ion Pulse still reaches 300. The non-fog ability targeting path also requires an allied combatant within 260 units of the target. A visible rendered opponent is therefore not necessarily an eligible pulse target. The controlled range/effect probe confirms the shorter cast reach; it does not measure an actual earned pulse in the natural opening.
- A roughly 21-second opening permits at most one cast once targets are close. Interrupting charges or denying delayed shield recovery can be valuable, but this is situational control, not a general damage button. Auto chooses the first eligible target rather than explicitly prioritizing an active charge or useful shield suppression.

Recommendation for a user decision: make cast reach follow the installed emitter's range, and decide whether this situational control is the intended first active ability. Keep fleet-wide versus per-ship cooldown scope an explicit decision. No additional abilities or ability balance changes were implemented in this audit.

## Early progression

The normal starting budget is 700 credits. Fully fitted defaults cost 253 for a Gun Drone, 310 for an Interceptor Fighter and 675 for a Freighter Transport. Two actual Drone purchases succeed at the starting shipyard, leave 194 credits and increase nominal fleet DPS from 35.6 to 41.6 (17%). These are aggregate weapon stats, not a measured 17% improvement in encounter outcomes. Transport buys utility rather than direct weapon damage.

For this Defensive starter, the initial eligible pool is Bastion II, Civil Hospitality, Field Engineering, Fleet Logistics I, Laboratory II (Research Methods I) and Renewal I. Its mini-turret fit lacks the laser/missile/ion capabilities needed to offer those offensive lines. Matching-equipment eligibility is working as requested; its consequence is a utility/defensive first pool unless the player refits before earning a choice. Different flagship fits can produce different pools.

Normal travel reaches the first encounter with 3.568 RP. Time spent fighting adds none; settlement adds the fixed four RP, leaving 7.568/20 and no choice. This confirms the current M-lab starter's slower pacing after lab simplification. It does not measure when the first choice eventually arrives.

Recommendation for a user decision: establish the desired first-choice milestone before changing RP costs/output/rewards. If an early combat upgrade should be possible with the existing starter, decide whether to add a meaningful mini-turret research line or broaden an existing card's capability applicability. Do not remove equipment matching or grant research silently.

## Focused verification

[test_battle_feel.gd](../tests/test_battle_feel.gd): 33 headless missile/ability checks, three normal-purchase/progression checks, 22 native opening/comparison checks, and seven final native meter/cluster checks, all zero failures. Captures and diagnostic JSON are under `.local/checks/battle-feel/` with isolated APPDATA. Final visual-only refinement did not rerun the unchanged passing combat comparisons. Related battlefield/equipment fixtures were updated for five-shot ammo expectations and compile-checked, without rerunning their unrelated suites.

The known certificate-store and native shutdown texture diagnostics remain. No full baseline, all-flagship campaign, broad performance profile or soak was run.
