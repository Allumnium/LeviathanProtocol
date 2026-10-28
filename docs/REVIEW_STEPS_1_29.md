# Review of development steps 1–29

Reviewed October 27, 2026, at commit b695d98 ("up to 29"). This was a source review and independent headless validation, not a complete visual/UI playtest. No gameplay fixes were applied.

## Assessment

The implementation is broadly on track. Separating research grants, adjacency, passenger rules, frozen encounters and checkpoint accounting into focused helpers is useful. Research gating and frozen encounter generation have substantial tests. Future passenger components are deliberately disabled until casualty handling exists, which is appropriate.

However, passing the current suite does not mean the completed milestones are free of integration problems. Correct the support-ship progression lock before adding more content. Resolve the revision/deployment policy before relying on the three-type limitation for mining. Preparation saves also need an explicit completion task.

Step 18 is honestly left unchecked: the live start still uses three Drones and the old credit amount, rather than two Drones plus Science and Civic ships with 300 credits. Gate C is therefore provisional. Steps 28–29 currently provide backend passenger policy and settlement, not a live playable passenger feature; the equipment is intentionally still gated.

## 1. High priority: losing a support module can permanently block a surviving run

**Locations:** scripts/fleet_rules.gd:87–99; scripts/game_state.gd:1320–1322, 1428–1449, 1600–1603. Repair and dismantling have the same port restriction at 1124–1132 and 1179–1181.

A dedicated Science ship whose lab is destroyed fails operational_error(). deployment_error() consequently prevents the entire fleet from departing. At a non-port node, the player also cannot reserve, repair or dismantle that ship. There is no legal way to reach the next port, even when combat ships are healthy.

**Independent reproduction:** start seed 42; buy a legal dedicated Science hull; deploy to the first battle; set its lab HP to zero while its Command Center survives; settle victory. The next destination was a salvage node. Travel, reserve, repair and dismantle all returned false. Reload succeeded and retained the blockage.

The same validation pattern applies to future Civic ships losing their last accommodation/hold. Deployed-force loss with surviving reserves also deserves a regression because reserve activation is port-only.

**Recommended correction:** distinguish fitting eligibility from damage incurred during a run. A legally fitted dedicated hull should be allowed to limp to the next port with its support benefit disabled. Keep construction/assignment restrictions intact. Alternatively provide a deliberate emergency reserve/abandonment action outside ports, with explicit passenger/cargo loss rules; do not simply grant free repairs.

**Acceptance:** win and withdraw from a non-port fight after losing the Science lab; survive with healthy escorts; continue through a noncombat node to a port; repair normally. Repeat after save/load and, when available, with Civic accommodation/hold loss.

## 2. Design loophole: arbitrary simultaneous revisions bypass three active ship types

**Locations:** scripts/game_state.gd:1290–1298 and 1383–1393; scripts/fleet_panel.gd:451–458.

REGISTER REVISION appends any authorized new blueprint to a family. Deployment checks only whether the family is active; it does not select one active blueprint revision. Consequently all historical variants of a family may deploy together.

**Independent reproduction:** register and buy several modified Drone blueprints under family/1; reserve two initial copies to remain within capacity. Four distinct deployed blueprint fingerprints were legal at capacity 26/30, while the active slot list was ["family/1", "", ""]. Departure was permitted.

This is a policy gap as well as an implementation issue: the plan permits revisions to retain family identity, but does not explicitly say whether different revisions may deploy simultaneously. The implementation chose unrestricted coexistence. Because a revision can contain arbitrary equipment, this will allow a miner, carrier, artillery ship and escort under one family instead of requiring the intended three-way tradeoff.

**Recommended correction:** retain family/history for editing, but allow one active blueprint revision per regular slot. Reserve or refit outdated copies before deployment, or count each distinct deployed blueprint against the three slots. Do not invent a subjective “similar enough” classifier.

**Acceptance:** multiple copies of the same active revision deploy normally; changing a revision does not create free physical refits; different historical revisions cannot silently create a fourth active type. Repeat with materially different roles when mining arrives.

## 3. Medium priority: successful preparation purchases are not durable

**Locations:** scripts/game_state.gd:1044–1060 and 1083–1121. Compare the staged checkpoint behavior of repair_ship() and purchase_research().

purchase_ship() and purchase_material() mutate live resources and fleet state and return success without committing a checkpoint. A later unrelated save may preserve them, but immediate reload rolls them back.

**Independent reproduction:** new campaign had three ships; purchase_ship() returned true and the fleet had four; load_run_checkpoint() returned true and restored three. The corresponding resource changes also belong to the rolled-back preparation state.

docs/ACCOUNTING.md explicitly excludes unsaved preparation purchases from its current recovery boundary. Thus this is a documented implementation gap, not a claim that the atomic ledger itself duplicates transactions. It still needs to be closed before persistence is considered player-ready.

**Recommended correction:** stage ship/material purchases, family/ID changes and resource deductions in a checkpoint, persist it, then apply the live mutation/signals. Use the same failure semantics as repair/research. Audit build-area upgrades and formation/editor saving and document the chosen save boundary.

**Acceptance:** purchase then reload preserves the ship and exact resource cost once. A failed write changes neither fleet, family IDs, next_ship_id nor funds/materials. Repeat for material purchases.

## Other gaps to schedule explicitly

- **Continue/load UI:** load_run_checkpoint() has no production caller outside its definition; the main menu offers a new run but no Continue. This is acknowledged in accounting documentation, so it is not a newly discovered regression. Add an explicit checklist item for resuming checkpoints and clearly explain whether an interrupted battle restarts from deployment or resumes exactly.
- **Starter activation:** close step 18 after Cargo Hold behavior becomes functional. Keep the incomplete status visible; avoid describing Gate C as a completed start-to-research onboarding experience.
- **Step 30 integration:** settle casualty counts and fees before checkpoint validation sees occupied destroyed components or before record_battle() removes dead hulls. Existing PassengerRules.valid() intentionally rejects such occupied references. Test cabin death followed by host death, failed settlement retries, reconstruction, and save/load.
- **Debt purchases:** current construction/repair comparisons reject zero-credit actions when credits are negative. Step 30 must change both backend checks and UI disabled states so owned-material-only construction and zero-credit reconstruction remain possible. This is upcoming work, not a missed step-29 requirement.
- **Loaded capacity:** before enabling passenger equipment, decide the release boundary for reserve/revision/dismantle actions. They must not erase occupancy or become inexplicable save-validation failures. The later step 33 covers the full UI, but a safe backend guard must exist at activation.

## Independent validation performed

Ran tests/run_baseline.ps1 using its isolated APPDATA/save setup. All suites reported zero failures, including:

- definitions, research grants/UI/enforcement, run state and transactions;
- science, adjacency, tuning, shared research, passengers and boarding;
- fleet-independent encounters and 1,080 frozen encounter allocations;
- objective membership, retry settlement and battle replay;
- 1,000 graph seeds and 1,000 content seeds with three complete placeholder campaign traversals;
- fleet slots/capacity, shared stats and 58 recipe/rank entries yielding 46 canonical signatures;
- the final battle suite with 600 basic encounters.

The traversal tests use placeholder battle completion; they do not establish full-campaign combat balance or completion of future boss mechanics.

Full log: .local/review-baseline.log. Isolated run: .local/checks/172991f0dc8a4b4099172997a32cae7f/. Targeted reproduction script and results: .local/review_audit.gd and .local/review-audit.log. These local artifacts are ignored, not permanent regression coverage.

The run also emitted the already-documented certificate-store diagnostic and some ObjectDB shutdown-leak warnings. No assertion failures were reported. These diagnostics should be tracked separately from gameplay acceptance.

## Recommended next handoff

1. Fix the support-module progression lock and add a permanent regression.
2. Specify/enforce one active revision per regular slot, then test mixed historical revisions.
3. Make preparation purchases durable and add failed-write/reload cases.
4. Schedule Continue/checkpoint UX explicitly.
5. Resume step 30 with casualty-before-validation, signed-credit and loaded-capacity safeguards.
6. Finish Cargo Holds/arrival trade, activate the intended starter fleet, and rerun the actual opening research/economy loop before declaring Gates C/D complete.
