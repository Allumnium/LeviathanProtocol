extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _run() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://transaction_test/run.json"
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 2468), "Create an initial durable run.")
	var start_credits: int = state.credits
	var start_materials: int = state.red_tiles_available
	var owned: FleetShip = state.fleet[0]
	owned.units[0].hp *= 0.5
	state.economy_state = {"example_hold": {"quantity": 7, "origin_value": 3}}
	_check(state.commit_event("arrival", "port/4", 32, [1, 0, 0, 0], 20), "Commit an arrival and its amounts together.")
	_check(state.credits == start_credits + 32 and state.red_tiles_available == start_materials + 1 and state.research_points == 20,
		"Committed balances must match the event.")
	_check(state.fleet[0] == owned, "Live commits must preserve simulation-owned physical ship references.")
	_check(state.commit_event("arrival", "port/4", 32, [1, 0, 0, 0], 20), "Replayed event should be acknowledged.")
	_check(not state.commit_event("arrival", "port/4", 64), "Conflicting event identity must be rejected.")
	_check(state.credits == start_credits + 32 and state.transaction_ledger.size() == 1,
		"Replaying an arrival cannot pay twice.")
	state.credits = 0
	state.red_tiles_available = 0
	state.research_points = 0
	_check(state.load_run_checkpoint(), "Load amounts and ledger from one checkpoint.")
	_check(state.credits == start_credits + 32 and state.red_tiles_available == start_materials + 1 and state.research_points == 20,
		"Loading must restore accounting state.")
	_check(is_equal_approx(state.fleet[0].units[0].hp, owned.units[0].hp) and state.economy_state.example_hold.quantity == 7,
		"Damage and economy state must survive accounting recovery.")
	_check(state.commit_event("arrival", "port/4", 32, [1, 0, 0, 0], 20) and state.credits == start_credits + 32,
		"An arrival cannot pay again after reload.")
	var loaded_hold := {"example_hold": {"quantity": 10, "origin_value": 6}}
	_check(state.commit_event("cargo_sale", "hold/atomic", 21, [0, 0, 0, 0], 0, {"sold": 7}, loaded_hold),
		"Commit cargo sale and replacement load together.")
	_check(state.load_run_checkpoint() and state.economy_state.example_hold.quantity == 10,
		"Economic component state must recover with its sale ledger.")
	var sale_balance: int = state.credits
	_check(state.commit_event("cargo_sale", "hold/atomic", 21, [0, 0, 0, 0], 0, {"sold": 7}, loaded_hold)
		and state.credits == sale_balance, "Replayed sale must not sell/refill again.")
	for kind in ["cargo_sale", "casualty", "ore_pickup", "enemy_salvage"]:
		var amount := -2000 if kind == "casualty" else 21
		_check(state.commit_event(kind, "stable-source", amount), "Commit %s." % kind)
		var balance: int = state.credits
		_check(state.commit_event(kind, "stable-source", amount) and state.credits == balance, "Deduplicate %s." % kind)
	_check(state.credits < 0 and state.load_run_checkpoint() and state.credits < 0, "Debt must remain signed after reload.")
	_check(not state.commit_event("ore_pickup", "negative-material", 0, [-100000, 0, 0, 0]), "Reject negative inventory results.")
	_check(not state.commit_event("unknown_kind", "source", 5), "Reject unknown event kinds.")
	_check(not state.commit_event("arrival", "", 5), "Reject events without stable source identity.")

	# Simulate each process-interruption boundary using separate checkpoint files.
	var store := AtomicRunStore.new()
	var base: Dictionary = RunCheckpoint.capture(state)
	for phase in ["before_stage", "after_stage", "after_backup", "promoted"]:
		var path: String = "user://transaction_test/interrupt_%s.json" % phase
		var initial := store.commit(path, base, RunCheckpoint.valid)
		_check(initial.ok, "Create interruption fixture.")
		var applied := TransactionLedger.apply(base, "ore_pickup", "rock/root/fragment", 7, [0, 2, 0, 0], 0)
		var next: Dictionary = applied.checkpoint
		var result := store.commit(path, next, RunCheckpoint.valid, initial.generation, phase)
		var recovered := store.load_latest(path, RunCheckpoint.valid)
		var expected: Dictionary = base if phase == "before_stage" else next
		_check(result.ok == (phase != "before_stage"), "Commit status must match its durable boundary.")
		_check(int(recovered.payload.progress.credits) == int(expected.progress.credits), "Recover a complete balance at %s." % phase)
		_check(recovered.payload.ledger.size() == expected.ledger.size(), "Recover the matching ledger at %s." % phase)
		var replay := TransactionLedger.apply(recovered.payload, "ore_pickup", "rock/root/fragment", 7, [0, 2, 0, 0], 0)
		_check(int(replay.checkpoint.progress.credits) == int(base.progress.credits) + 7,
			"Recovery plus event retry pays exactly once at %s." % phase)
		_check(store.commit(path, replay.checkpoint, RunCheckpoint.valid, recovered.generation).ok,
			"A recovered staged checkpoint must permit a subsequent commit.")

	var backup_path := "user://transaction_test/corrupt.json"
	var first := store.commit(backup_path, base, RunCheckpoint.valid)
	var update := TransactionLedger.apply(base, "cargo_sale", "hold/12", 21, [0, 0, 0, 0], 0)
	_check(store.commit(backup_path, update.checkpoint, RunCheckpoint.valid, first.generation).ok, "Create a backup generation.")
	_write(backup_path, "{interrupted")
	_write(backup_path + ".next", "{broken-stage")
	var fallback := store.load_latest(backup_path, RunCheckpoint.valid)
	_check(not fallback.is_empty() and int(fallback.payload.progress.credits) == int(base.progress.credits),
		"Corrupt main/staged files must recover the complete backup.")
	var recovered_sale := TransactionLedger.apply(fallback.payload, "cargo_sale", "hold/12", 21, [0, 0, 0, 0], 0)
	_check(int(recovered_sale.checkpoint.progress.credits) == int(base.progress.credits) + 21,
		"Backup recovery and event retry cannot duplicate sale value.")
	_check(not store.commit(backup_path, base, RunCheckpoint.valid, 999).ok, "Reject a stale writer generation.")
	_check(store.commit(backup_path, recovered_sale.checkpoint, RunCheckpoint.valid, fallback.generation).ok,
		"Commit again after backup recovery.")
	_write(backup_path, "{second-corruption")
	var second_fallback := store.load_latest(backup_path, RunCheckpoint.valid)
	_check(not second_fallback.is_empty() and int(second_fallback.payload.progress.credits) == int(base.progress.credits),
		"Replacing a corrupt main must preserve the last good backup.")

	# A filesystem write failure cannot mutate live balances, ledger or inventory.
	var good_path: String = state.run_save_path
	_write("user://transaction_test/blocker", "file, not a directory")
	state.run_save_path = "user://transaction_test/blocker/run.json"
	var before: Dictionary = state.run_progress_snapshot()
	var ledger_size: int = state.transaction_ledger.size()
	var economy_before: Dictionary = state.economy_state.duplicate(true)
	_check(not state.commit_event("cargo_sale", "write-failure", 500, [0, 0, 0, 0], 0, {}, {}), "Failed staging must reject the event.")
	_check(state.run_progress_snapshot() == before and state.transaction_ledger.size() == ledger_size,
		"Failed staging must leave live amounts and deduplication records unchanged.")
	_check(state.economy_state == economy_before, "Failed staging must not clear economic component state.")
	state.run_save_path = good_path
	_check(state.commit_event("cargo_sale", "write-failure", 500, [0, 0, 0, 0], 0, {}, {}), "A failed event remains retryable.")

	# Real victory settlement persists route progression, materials and credits once.
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 1357), "Start the victory scenario.")
	_check(state.set_destination(1), "Persist deployment and its actual current roster.")
	var roster_size: int = state.battle_aliens.size()
	_check(state.load_run_checkpoint() and state.battle_pending and state.battle_aliens.size() == roster_size,
		"Reload a pending deployment without rerolling that roster.")
	var red_before: int = state.red_tiles_available
	var credit_before: int = state.credits
	var frozen_reward: Dictionary = state.get_frozen_encounter(1).rewards
	_check(state.complete_battle(-1, [0, 0, 2]), "Commit one victory with salvage.")
	_check(state.current_node_id == 1 and state.credits == credit_before + int(frozen_reward.credits)
		and state.red_tiles_available == red_before + int(frozen_reward.materials[0]), "Victory amounts and progression must agree.")
	_check(state.load_run_checkpoint() and state.current_node_id == 1 and not state.battle_pending,
		"Reloading a victory cannot reopen its pending settlement.")
	var source := "node/1"
	_check(state.commit_event("victory", source, int(frozen_reward.credits), frozen_reward.materials)
		and state.credits == credit_before + int(frozen_reward.credits),
		"Replaying the settled victory after reload cannot pay again.")
	var previous_run: String = state.run_id
	_check(state.start_new_run() and state.run_id != previous_run and state.transaction_ledger.is_empty(),
		"New runs must have fresh event identity and no inherited ledger.")
	print("Transaction tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
