# Opening fleet review — October 29, 2026

Step 18 retains the three starting Drones in one general design family and activates the planned 300-credit start for new runs. Starting materials remain 18 Offense, 12 Defense, 6 Tech and 3 Civic; saved campaigns retain their existing funds. Three Drones cost 15 of the initial 30 deployment capacity. Players can add or design mixed-purpose ships normally; no support hull is mandatory and no bonus slot exists.

`tests/test_opening_loop.gd` runs seven actual journeys across seeds 42, 1357 and 12345 for three choices: baseline Drones, Drones plus Surveyor, and Drones plus Surveyor and Hauler. It drives production travel, frozen battle setup, Auto simulation to victory, settlement, paid repair, focused travel-days research, checkpoint reload and paid revision construction. It does not force victories or grant extra resources. The test initially exercised an explicit 300-credit budget before the production constant was changed; the permanent test now asserts the actual new-run budget instead.

All nine routes passed. Each sampled opening covers 16 travel days. The no-lab fleet earns 8 RP, remains viable in combat and can choose how to spend its starting resources. Lab fleets earn 1.5 RP/day while the lab survives, complete the 20-RP Applied Energy focus by row 6 or 7, and reach a shipyard before the first boss. Adding a laser to the Surveyor is a registered family revision and a normal paid replacement; the older physical hull keeps its identity/damage as an inactive revision and costs no deployment capacity. The actual equipped ship has higher DPS.

| Seed | Baseline credits at row 7 | Lab route after repair/refit | Lab/cargo route after repair/refit | Held cargo on trade route |
| --- | ---: | ---: | ---: | ---: |
| 42 | 630 | 583 | 479 | 30 |
| 1357 | 630 | 565 | 513 | 30 |
| 12345 | 630 | 589 | 524 | 30 |

Research and cargo components can be destroyed in ordinary battles. Repairs consume actual materials/credits, restore empty cargo capacity and never refill it outside a later arrival. The trade paths consequently do not guarantee goods at every intermediate stop; the initial sampled routes all had a genuine loaded hold by the pre-boss staging port. Later visibility/Scan checks also allow the legitimate outcome of a hold being destroyed before arrival and paid for afterward: reconstruction must remain empty. There is no promised profit or invulnerability for an economic hull.

Evidence: `.local/step18/opening.log` and the baseline runner's `opening-loop.log`. Existing capacity, revision, repair and daily-research suites cover failures and additional boundaries. This is a repeatable simulation playtest of the opening, not a full-campaign balance claim. Passenger economics, debt recovery and equal-investment short-route comparisons are now reviewed in [ECONOMY_LOOP.md](ECONOMY_LOOP.md); later acts, broad doctrine balance and bosses retain their TODO milestones.
