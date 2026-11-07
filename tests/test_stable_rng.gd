extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func draws(rng: StableRng, count: int) -> Array:
	var values := []
	for index in count:
		values.append(rng.next_u32())
	return values


func run() -> void:
	# Reference vectors come from an independent arbitrary-precision implementation.
	check(StableHash.hex64("") == "cbf29ce484222325", "FNV empty vector")
	check(StableHash.hex64("a") == "af63dc4c8601ec8c", "FNV 'a' vector")
	check(StableHash.hex64("foobar") == "85944171f73967e8", "FNV 'foobar' vector")
	check(StableHash.hex64("Leviathan Protocol") == "4b06b338ccfe70af", "FNV ASCII phrase")
	check(StableHash.hex64("\u00e9\u03c9") == "fa4182c6f3ca6699", "FNV hashes UTF-8 bytes")
	check(StableHash.int63("Leviathan Protocol") == 5406205459243626671, "Non-negative 63-bit hash")
	check(StableHash.key(["ab", "c"]) != StableHash.key(["a", "bc"]), "Key parts stay separated")

	check(draws(StableRng.from_key("key"), 6) == [4102585624, 3878020359, 1265156367, 4040881408, 97679053, 1706862446], "xoshiro128** reference sequence")
	var streams := RngStreams.new("test")
	check(draws(streams.rng("galaxy"), 6) == [2145235037, 3638347410, 1205665217, 3950590266, 2501492851, 1254978499], "Named stream reference sequence")
	var dice := StableRng.from_key("dice")
	var rolls := []
	for index in 10:
		rolls.append(dice.randi_range(1, 6))
	check(rolls == [6, 5, 4, 6, 5, 2, 2, 4, 6, 4], "Unbiased dice reference rolls")
	check(StableRng.from_key("key").randf_range(-2, 6) == -2 + 8 * (4102585624.0 / 4294967296.0), "Float range consumes the stable reference word")
	check(not StableRng.from_key("key").chance(0.5), "Chance uses the stable float reference")
	check(StableRng.from_key("key").weighted_index([1, 0, 3]) == 2, "Weighted choice uses the stable float reference")
	check(StableRng.from_key("dice").pick(["a", "b", "c", "d", "e", "f"]) == "f", "Picking uses the stable dice reference")
	var first_deck := [0, 1, 2, 3, 4, 5, 6, 7]
	var next_deck := first_deck.duplicate()
	StableRng.from_key("deck").shuffle(first_deck)
	seed(12345) # Unrelated global draws cannot affect stable convenience methods.
	for index in range(10):
		randf()
	StableRng.from_key("deck").shuffle(next_deck)
	check(first_deck == next_deck, "Shuffle repeats independently of global RNG state")

	check(streams.counter("galaxy") == 1, "Stream counter advances per request")
	var second := draws(streams.rng("galaxy"), 3)
	var other_scope := draws(streams.rng("galaxy", "sector_2"), 3)
	check(second != other_scope, "Scopes draw independently")
	var saved := streams.snapshot()
	var after_save := draws(streams.rng("galaxy"), 3)
	var reloaded := RngStreams.new()
	check(reloaded.restore(JSON.parse_string(JSON.stringify(saved))), "Counters restore from JSON")
	check(draws(reloaded.rng("galaxy"), 3) == after_save, "Reload reproduces the next draw")
	check(draws(streams.fixed("names", "ship_7"), 2) == draws(streams.fixed("names", "ship_7"), 2), "Fixed draws are stable")
	check(streams.counter("names", "ship_7") == 0, "Fixed draws do not advance counters")
	check(not reloaded.restore({"seed": "x", "counters": {"a/": -1}}), "Negative counters rejected")
	check(not reloaded.restore({"counters": {}}), "Missing seed rejected")
	check(reloaded.run_seed == "test", "Failed restore keeps prior state")

	var rng := StableRng.from_key("bounds")
	var in_bounds := true
	var low_seen := false
	var high_seen := false
	var mean := 0.0
	for index in 4000:
		var value := rng.randi_range(-3, 3)
		in_bounds = in_bounds and value >= -3 and value <= 3
		low_seen = low_seen or value == -3
		high_seen = high_seen or value == 3
		var unit := rng.randf()
		in_bounds = in_bounds and unit >= 0.0 and unit < 1.0
		mean += unit
	check(in_bounds and low_seen and high_seen, "Ranges are inclusive and bounded")
	check(absf(mean / 4000.0 - 0.5) < 0.03, "Unit floats are centered")
	check(rng.randi_range(5, 5) == 5, "Single-value range")

	var counts := [0, 0, 0]
	for index in 3000:
		counts[rng.weighted_index([1.0, 0.0, 3.0])] += 1
	check(counts[1] == 0, "Zero weights are never chosen")
	check(counts[2] > counts[0] * 2, "Weights bias choices")
	check(rng.weighted_index([0, -1]) == -1, "No positive weight returns -1")
	var deck := [1, 2, 3, 4, 5, 6, 7, 8]
	rng.shuffle(deck)
	var sorted := deck.duplicate()
	sorted.sort()
	check(sorted == [1, 2, 3, 4, 5, 6, 7, 8] and deck != sorted, "Shuffle permutes")
	check(rng.pick([]) == null, "Picking from empty returns null")

	print("test_stable_rng: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
