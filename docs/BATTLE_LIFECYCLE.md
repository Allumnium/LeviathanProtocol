# Attempts, settlement and replay

## Retry and withdrawal

Each deployed node records its attempt count, outcome, deployed ship IDs and initial deployment inputs. Retrying instantiates the original frozen enemy roster at full health. Surviving player components retain their actual HP; destroyed ships are removed. Withdrawal leaves the current node unchanged and permits another attempt at the same reachable destination. A fleet wipe ends the run, regardless of remaining credits. New runs reset this terminal state.

The controller settles the simulation's actual result through `GameState.settle_battle`. It validates the deployed ship identities, records physical losses and saves the result with the existing checkpoint/ledger. Victory advances the route and grants the frozen reward once. Withdrawal/defeat grant no victory credits, RP or enemy salvage. Failed settlement writes leave the outcome unpaid and retryable; the controller waits for a durable result before completing its report. Physical ship references remain intact while retrying a failed write.

Lab-generated RP remains step 24. Existing RP is preserved on failure; these changes introduce no RP source.

## Persistent fields

`encounter_progress[node_id].field` is independent of the resettable enemy roster. `commit_field_pickup(pickup_id, material_delta, field_after)` atomically commits the finite field snapshot, ore amounts and run-scoped pickup identity. Duplicate pickup replay acknowledges without paying again or replacing the field with an older snapshot. Conflicting identities and invalid snapshots fail. Withdrawal, retry and reload retain the field.

This is a persistence boundary for future mining. Actual asteroid schemas, mass/ore conservation, extraction eligibility, visibility and collection rules arrive with the asteroid/mining steps. No live mining content is enabled here.

## Deterministic commands

The production controller drives the simulation at 30 Hz. Pause, camera, sound, rendering interpolation and speed controls stay outside authoritative battle state. Speed changes the number of fixed steps, not the step size. Diagnostic comparisons omit moving wreck visuals and post-result effect time.

`issue_command(type, payload)` records and executes UI intent at the current tick boundary. Supported commands are `attack`, `clear_attack`, `neutral_cleanup` and `withdraw`. `queue_command` schedules the same envelope for replay: `{id, tick, type, payload}`. Same-tick commands execute in recorded insertion order. Runtime validation rejects invalid targets/sources without spending cooldowns. Identical command IDs acknowledge without executing twice; conflicting reuse fails. Direct simulation methods remain available for setup and low-level tests.

Each event has a stable battle-scoped ID and simulation tick. Command receipts, weapon cooldown expenditures, destruction snapshots and terminal objective results are recorded without references to UI objects. Battle IDs include run, node and attempt. `authoritative_snapshot()` returns detached diagnostic state including RNG state, component HP, targets/orders, projectiles, cooldowns, objectives and rewards.

Settlement stores the initial deployment inputs, command/event streams and final snapshot in the same checkpoint as losses and payout. These are replay diagnostics, not an exact in-flight save loader or a new Continue/replay UI. Unsaved combat ticks still recover from the last durable checkpoint. Cross-engine/platform bitwise floating-point compatibility is not promised.

## Gate A review

Steps 1–9 now provide versioned definitions and save compatibility, current-run authorization independent of Archive, atomic accounting with event deduplication/recovery, fleet-independent frozen enemies/rewards, explicit objective membership, optional neutral cleanup, durable retry/loss handling and deterministic command replay.

`test_retry_settlement.gd` covers two withdrawals followed by success, damaged/destroyed ship persistence, reset enemies, finite-field pickup replay, failed settlement writes, one-time payment and terminal defeat. `test_battle_replay.gd` compares complete diagnostic state and events through the production clock at normal, 2× and accelerated batches, including physical component damage and salvage. Existing import, definition, metadata, transaction, encounter, objective and battle suites remain required.

At Gate A, campaign topology, labs, abilities and mining remained later milestones. Steps 11–16 now activate the 24-row campaign (CAMPAIGN_MAP.md); historical maps retain their legacy bridge. Three starter Drones remain until step 18. No future equipment or economy system is exposed as a purchasable stub.

Final validation (2026-10-26): the complete isolated baseline passed with zero failures, including 864 encounter allocations, 600 battle regressions, retry settlement and normal/accelerated replay. Logs: `.local/checks/49b577c0346d465488d507cd4e291fb3/`. `git diff --check` passed. The existing Windows certificate-store diagnostic remains unrelated to assertions; player saves were not used.
