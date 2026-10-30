# Economy review — step 35

The core economy is usable without optional freight upgrades. Four controlled seven-journey routes use the same three-Drone baseline, starting knowledge and 124 credits of discretionary capital, with starting material stock removed for comparable full-price orders. Hospitality is prepared before the comparison; natural research pacing is covered separately by the opening-loop playtest. All battles are actual Auto simulations, and arrivals, losses, repairs, refits and reloads use production accounting.

| Alternative | Full-price hull | Final credits | Tickets | Cargo sales | Casualty fees |
| --- | ---: | ---: | ---: | ---: | ---: |
| Escort | 110 | 326 | 0 | 0 | 0 |
| Hauler | 97 | 402 | 0 | 60 | 0 |
| Scout with cabin | 104 | 248 | 32 | 0 | 80 |
| Same cabin, forced zero cash before casualty | 104 | 34 | 32 | 0 | 80 |

The first three alternatives complete a paid family revision after safe unloading; prior physical copies remain inactive. The stress case intentionally sets cash to zero just before four real passenger deaths, commits the resulting -80 balance, then recovers through ordinary victory income and paid repair. It does not receive a debt grant/refund, and does not require an immediate unaffordable replacement hull.

Goods have per-origin identities. The Hauler's incoming goods sell at arrival; its different destination load is then safely offloaded before refitting, accounting for two 30-credit sales. Each physical load sells once. Offloading sacrifices that load's future delivery value, and constructing a new hold at the same settled port never refills it. Redispatching either inhabited arrival changes no balance, loads or ledger. Repaired cabins remain empty until another legitimate arrival; losing the four occupants costs 80 and forfeits that damaged cabin's next boarding income.

The existing encounter generator already freezes a material pool equal to twice the base bundle and a 50% starting recovery rate. Campaign victory always uses the authoritative base bundle; fake caller drops, summon kills and repeated withdrawals cannot enlarge it. Summons, decoys and hazards are excluded from enemy drop creation, and player wrecks cannot enlarge frozen victory salvage. New snapshot validation rejects a descriptive pool/rate inconsistent with its base bundle while accepting older snapshots that omitted this optional metadata. No refinery/tractor/freight upgrade was activated.

`tests/test_economy_loop.gd` covers the comparisons, two inhabited stops, losses, repair/refit, per-row reload, debt and finite-pool abuse. Initial verification: `.local/step35/economy.log`, zero failures. The table records the latest role-aware run in `.local/enemy-roles/economy_loop.log`; modest repair-cost changes do not invalidate the budget or debt recovery. Existing transaction, cargo-arrival, passenger-loss and retry suites cover write failures, duplicate attempts and frozen values. Gate D is reviewed for the current basic economy; broader full-campaign doctrine tuning remains step 67.
