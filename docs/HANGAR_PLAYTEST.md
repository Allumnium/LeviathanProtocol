# Hangar playtest: initial progression pass

Nine runs completed the currently implemented campaign route: three seeds with combat, trade and science purchasing policies. Each run used the actual hangar APIs, normal starting credits, earned credit rewards/loot, purchased equipment, paid repairs, researched technologies and saved/reloaded arrivals. Every battle outcome came from BattleSimulation; no forced wins, stat boosts or free unlocks were used.

All nine runs won 14 battles each (126 total), reaching all 24 arrivals. The suite passed 1,252 checks. Science policies purchased and operated upgraded labs; daily production finished at 4.5 RP/day versus 1.5 for the other policies.

| Seed | Policy | Ships | Ending credits | RP/day | Technologies completed | Combat seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 42 | Combat | 4 | 908 | 1.5 | 3 | 201.0 |
| 42 | Trade | 4 | 1457 | 1.5 | 3 | 205.5 |
| 42 | Science | 3 | 779 | 4.5 | 5 | 175.7 |
| 1357 | Combat | 4 | 966 | 1.5 | 3 | 216.6 |
| 1357 | Trade | 4 | 1274 | 1.5 | 3 | 216.7 |
| 1357 | Science | 3 | 722 | 4.5 | 5 | 176.8 |
| 12345 | Combat | 4 | 688 | 1.5 | 4 | 246.2 |
| 12345 | Trade | 4 | 1554 | 1.5 | 4 | 266.2 |
| 12345 | Science | 3 | 780 | 4.5 | 6 | 186.9 |

Ending credits reflect different fleet/equipment spending as well as trade income; they are not a controlled comparison of trading profit. Policies favor safe routes and longer travel for research. Combat times describe simulation time, not wall time or total play duration.

## Changes from the review

- Lab I / II / III produce 1 / 2 / 3 RP per day, plus the fleet baseline of 0.5. Lab II fits Frigate civic L; Lab III fits flagship/Transport civic XL. All retained equipment has at least one matching authored mount. Source artwork and draft mount maps were preserved.
- Production labels show the lab mix; research and hangar details match rank rates. Stock, destroyed labs and destroyed hosts produce nothing.
- Pending journey yields are already frozen numbers and remain unchanged across this rule update. Later journeys use the new rates. Tests cover midbattle lab destruction, Continue and duplicate settlement.
- Gravitic Snare was a purchasable inactive ability. New purchases, focus and loot are deferred until the ability path is adapted. Existing research and owned instances remain readable/removable/sellable; fitted inactive equipment cannot deploy. No replacement slot bonus was invented.

## Scope and remaining work

This verifies playability of the current route and existing encounters, including the implemented Bastion Warden. Brood Architect and Leviathan still use the existing guardian encounters; the distinct bosses in TODO 60/65 are not finished. These wins do not establish final difficulty, an optimal strategy, all possible fleet compositions or a finished MVP. General balance remains TODO 67; full acceptance runs after the remaining content remain TODO 70.

Run `tests/run_baseline.ps1 -Native`. The baseline includes the natural campaign and ranked-research suites; raw run records/logs are under `.local/hangar/` and the runner's isolated `.local/checks/` directory. Saves used isolated APPDATA.
