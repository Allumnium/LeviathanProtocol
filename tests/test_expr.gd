extends SceneTree

var checks := 0
var failures := 0

const SCHEMA := {
	"credits": "number",
	"day": "number",
	"stat": {"wealth": "number"},
	"region": {"lawless": "number", "name": "string"},
	"vars": {"*": "any"},
	"fleet": "list",
	"flagship": "entity",
	"faction": {"*": {"standing": "number"}},
}


class Probe:
	extends RefCounted
	func expr_get(name: String) -> Variant:
		return 42 if name == "answer" else null


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func values() -> Dictionary:
	return {
		"credits": 2500,
		"day": 12,
		"stat": {"wealth": 1800},
		"region": {"lawless": 0.7, "name": "Drift"},
		"vars": {"debt": 300, "zero": 0, "label": "x", "flag": true},
		"fleet": [{"hull": 20, "tags": ["pirate"]}, {"hull": 5, "tags": []}, {"hull": 12, "tags": ["pirate"]}],
		"flagship": {"hull": 30, "probe": Probe.new()},
		"faction": {"syndicate": {"standing": -20}},
	}


func value(source: String, functions: ExprFunctions = null) -> Variant:
	var formula := Formula.compile(source, SCHEMA, "any", functions)
	if not formula.ok():
		push_error("Unexpected compile error in '%s': %s" % [source, formula.error_text()])
		return "<compile error>"
	return formula.evaluate(values())


func same(source: String, expected: Variant) -> void:
	var actual: Variant = value(source)
	var ok := ExprEvaluator.equals(actual, expected) if not (expected is float and actual is float) else absf(actual - expected) < 0.000001
	check(ok, "%s gave %s, expected %s" % [source, actual, expected])


func compile_error(source: String, fragment: String, expected_type := "any", column := -1) -> void:
	var formula := Formula.compile(source, SCHEMA, expected_type)
	var text := formula.error_text()
	var ok := not formula.ok() and text.contains(fragment)
	if ok and column > 0:
		ok = formula.errors[0].column == column
	check(ok, "'%s' should fail with '%s' (column %d), got '%s'" % [source, fragment, column, text])


func runtime_error(source: String, fragment: String) -> void:
	var formula := Formula.compile(source, SCHEMA)
	var result: Variant = formula.evaluate(values())
	check(formula.ok() and result == null and formula.last_error.contains(fragment), "'%s' should fail at runtime with '%s', got %s / '%s'" % [source, fragment, result, formula.last_error])


func run() -> void:
	# Precedence and associativity.
	same("1 + 2 * 3", 7.0)
	same("(1 + 2) * 3", 9.0)
	same("10 - 4 - 3", 3.0)
	same("2 ^ 3 ^ 2", 512.0)
	same("-2 ^ 2", -4.0)
	same("2 ^ -1", 0.5)
	same("7 % 3", 1.0)
	same("-7 % 3", 2.0)
	same("10 / 4", 2.5)
	same("true or false and false", true)
	same("not 1 > 2", true)
	same("2 * 3 > 5 and not false", true)
	same("not 2 in [1, 3]", true)
	same("1 + 2 == 3", true)
	same("if 3 > 2 then 'a' else 'b'", "a")
	same("1 + if false then 1 else 2 * 5", 11.0)
	# Values, strings and lists.
	same("'it\\'s' + \"!\"", "it's!")
	same("'rift' in 'drift'", true)
	same("2 in [1, 2, 3]", true)
	same("4 not in [1, 2]", true)
	same("[1, 2, 3][1]", 2.0)
	same("[1, 2][5] == null", true)
	same("len([1, 2]) + len('abc')", 5.0)
	same(".5 + 1.25", 1.75)
	# Functions.
	same("max(1, 7, 3) - min(4, 2)", 5.0)
	same("clamp(stat.wealth / 1500, 0.5, 3)", 1.2)
	same("round(2.5) + floor(-1.5) + ceil(0.2) + abs(-3)", 5.0)
	same("lerp(0, 10, 0.25)", 2.5)
	same("between(5, 1, 5) and not between(6, 1, 5)", true)
	same("sqrt(16)", 4.0)
	# Context paths, wildcards and entities.
	same("credits > 2000 and region.lawless >= 0.6", true)
	same("credits == 2500", true)
	same("vars.debt + 1", 301.0)
	same("region.name + '!'", "Drift!")
	same("faction.syndicate.standing < 0", true)
	same("flagship.hull * 2", 60.0)
	same("flagship.probe.answer", 42.0)
	same("fleet[0].hull + fleet[2].hull", 32.0)
	same("'pirate' in fleet[0].tags", true)
	var reads := Formula.compile("credits > 2000 and region.lawless >= 0.6 or vars.debt > stat.wealth", SCHEMA).reads
	check(reads == PackedStringArray(["credits", "region.lawless", "stat.wealth", "vars.debt"]), "Reads list context paths: %s" % [reads])

	# Short-circuiting never evaluates the skipped side.
	same("false and 1 / 0 > 1", false)
	same("true or 1 / 0 > 1", true)
	same("if true then 1 else 1 / 0", 1.0)

	# Compile errors carry 1-based columns and designer-readable messages.
	compile_error("credts > 1", "Did you mean 'credits'", "any", 1)
	var lawless_source := "credits > 2000 and region.lawles >= 0.6"
	compile_error(lawless_source, "Did you mean 'lawless'", "any", lawless_source.find("lawles") + 1)
	compile_error("stat", "pick a field")
	compile_error("stat + 1", "pick a field")
	compile_error("1 +", "ends too early", "any", 4)
	compile_error("credits = 1", "Use '=='", "any", 9)
	compile_error("true && false", "Use 'and'")
	compile_error("1 < 2 < 3", "cannot be chained")
	compile_error("'a' + 1", "Cannot add")
	compile_error("credits and true", "needs true/false")
	compile_error("if credits then 1 else 2", "true/false condition")
	compile_error("if true then 1 else 'x'", "make them the same")
	compile_error("min(1)", "takes 2 or more")
	compile_error("clamp('a', 1, 2)", "needs a number")
	compile_error("foo(1)", "Unknown function")
	compile_error("credits(1)", "is a value, not a function")
	compile_error("max", "is a function")
	compile_error("'abc", "closing quote")
	compile_error("1 == 'a'", "always false")
	compile_error("credits + 1", "Expected a condition", "bool")
	compile_error("(1 + 2", "to close '('")
	compile_error("1 2", "Unexpected '2'")
	compile_error("12abc", "followed by letters")
	compile_error("", "empty")
	compile_error("this.hull", "Unknown name 'this'")
	check(Formula.compile("credits > 1", SCHEMA, "bool").ok(), "Bool formula accepted for bool field")
	check(Formula.compile("vars.debt", SCHEMA, "number").ok(), "Any-typed paths defer to runtime")

	# Runtime errors give null and readable messages; conditions fail closed.
	runtime_error("vars.debt / vars.zero", "Division by zero")
	runtime_error("vars.label + 1", "Cannot add")
	runtime_error("sqrt(-1)", "negative")
	runtime_error("max(vars.label, 1)", "max needs a number")
	runtime_error("vars.missing > 1", "got nothing")
	var guarded := Formula.compile("vars.debt / vars.zero > 1", SCHEMA, "bool")
	check(not guarded.test(values()), "Failing conditions are false")
	check(Formula.compile("vars.debt / vars.zero", SCHEMA, "number").number(values(), 7.0) == 7.0, "Failing numbers use the fallback")
	var typed := Formula.compile("vars.label", SCHEMA, "number")
	check(typed.evaluate(values()) == null and typed.last_error.contains("Expected a number"), "Runtime result type is enforced")

	# Lazy arguments bind extra names only inside their argument.
	var functions := Formula.standard_functions().extended()
	var count_where := func(args: Array, _env: Variant) -> Variant:
		var total := 0
		for item in args[0]:
			if args[1].call({"this": item}) == true:
				total += 1
		return float(total)
	functions.register("count_where", ["list", "fn:bool"], "number", count_where, {"binds": {"this": "entity"}})
	check(ExprEvaluator.equals(value("count_where(fleet, this.hull > 10)", functions), 2.0), "Lazy argument binds this per item")
	check(ExprEvaluator.equals(value("count_where(fleet, 'pirate' in this.tags and credits > 0)", functions), 2.0), "Lazy argument still reads the outer context")
	check(not Formula.compile("count_where(fleet, 5) > 1", SCHEMA, "any", functions).ok(), "Lazy argument result is type-checked")
	check(not Formula.compile("count_where(fleet, true) + this.hull", SCHEMA, "any", functions).ok(), "Bound names do not leak outside the argument")
	check(not Formula.standard_functions().has("count_where"), "Extended registries leave the standard set unchanged")

	var timed := Formula.compile("clamp(stat.wealth / 1500, 0.5, 3) * (if region.lawless > 0.5 then 2 else 1)", SCHEMA, "number")
	var context := values()
	var started := Time.get_ticks_usec()
	for index in 10000:
		timed.number(context)
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(elapsed_ms < 3000.0, "10k evaluations stay fast (%.1f ms)" % elapsed_ms)

	print("test_expr: %d checks, %d failures (10k evaluations %.1f ms)" % [checks, failures, elapsed_ms])
	quit(1 if failures > 0 else 0)
