# Frozen proximity encounters

Step 6 replaces campaign encounter normalization with a finite allocation of priced enemy definitions. For global row r=1–24, proximity is `(r-1)/23` and base threat is `100 * 5^proximity`. Standard/elite/boss multipliers are 1/1.4/1.8; Easy/Normal/Hard are 0.8/1/1.25. Normal boss budgets at rows 8, 16 and 24 are about 293, 514 and 900. Threat is an allocation currency; no player fleet statistics enter generation.

Five existing roles have explicit costs: Scout 16, Fighter 22, Sentinel 30, Support 26 and Chrysalis 32. Each has three fixed definitions. Tier cost multipliers are 1/2.25/3.75, with declared durability, weapon and mobility changes in AlienShip; tiers become available in the three acts. Templates require roles and purchase affordable definitions, preferring the highest unlocked tier. Remaining threat below the cheapest eligible definition is allowed and recorded as the template's absolute tolerance. Late budgets buy stronger variants rather than unbounded Scout counts. These are initial content-allocation values, not final combat balance.

The allocator supports finite multi-wave, craft-reserve and organ allocations charged against one total budget. It limits regular ships across all waves to 24 and total enemy entries to 40, leaving headroom for the shared 64-entity limit. The wave/organ/craft templates are allocation frameworks tested here; only patrols are activated on the current map. Boss organs, live spawning, objective behavior and capacity enforcement remain their numbered milestones. No partial boss or defense objective is exposed to players.

## Frozen state and rewards

Every current map node receives its encounter at run creation. The snapshot stores global row, seed, multipliers, budget/spending/tolerance, required/allowed roles, finite wave membership, stable entity identities and each entity's actual HP/shields/mobility/weapons. Deployment instantiates these stored values. Inspecting, changing ships/research/difficulty, withdrawing and reloading never regenerate them. Saved values survive later definition tuning.

Rewards are stored too: `90 + 10 * combat_index` credits, multiplied by 1.4 for elites or 1.5 for bosses. Initial material bundles are 12/18/24 by act, deterministically distributed as Offense 30%, Defense 35%, Tech 20%, Civic 15%. A finite enemy pool is frozen at twice that bundle; initial recovery is 50%. Campaign victory and its report use the frozen baseline bundle, with route advancement and payout in the existing atomic transaction. Logistics recovery modifiers and per-source salvage handling remain step 34; labs and RP snapshots remain step 24. Ad-hoc simulation fixtures retain their legacy randomized drops and balance helper.

The legacy map still has 14 combat columns. An explicit bridge maps them to `[1,3,5,8,9,10,12,13,16,17,18,20,21,24]`; screen coordinates and fleet composition do not affect proximity. Step 10 replaces this bridge with actual 24-row node data and noncombat stops. Existing convergence markers do not claim implemented boss encounters.

Checkpoint version 2 stores all generated encounters. Version-1 checkpoints migrate previously unfrozen nodes once; an already deployed legacy roster keeps its exact saved stats and 200-credit reward contract, marked as legacy. Component/material/ship IDs and archived blueprints remain unchanged. Current-node rosters are not reconstructed from a seed on load.

Migration results are durably committed in version 2 before being exposed, and existing ledger entries remain intact. Historical frozen stat/reward values are accepted as saved content, rather than recomputed against today's tier definitions.

## Validation

`tests/test_frozen_encounters.gd` covers formula examples, every row/difficulty/template over three seeds (864 allocations), finite combined spending, wave/entity limits, stronger late variants, material conservation, defensive copies, withdrawal/refit/reload stability, historical stats/rewards surviving current generators, legacy checkpoint migration and a real Auto opening battle with the current starter fleet. The existing independence test still compares fleets of 1/4/10 across four seeds and three difficulties. Full campaign pacing and balance are later gates.

Actual step 6 validation (October 26, 2026): isolated import, definitions, run-state, transactions, encounter-independence, frozen-encounter and battle suites all exited 0 with zero failures. Full logs: `.local/checks/f57231dbdf4d47feaf3d57c4d19b2408/`. Follow-up durable migration/ledger preservation and opening-battle checks passed in `.local/frozen-focused5.log`. `git diff --check` passed. The baseline certificate-store diagnostic remains. The 600 legacy balance fixtures are regression coverage, not a claim that the new full campaign is balanced.
