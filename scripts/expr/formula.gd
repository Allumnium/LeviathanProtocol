class_name Formula
extends RefCounted

## A compiled, type-checked formula. Compile once at load time, evaluate many
## times. Evaluation never raises: errors give null and set last_error.

var source: String = ""
var expected: String = "any"
var result_type: String = "error"
## Compile errors: [{"column": 1-based, "message": String}].
var errors: Array[Dictionary] = []
## Dotted context paths the formula reads, such as "stat.wealth".
var reads: PackedStringArray = PackedStringArray()
var last_error: String = ""
var _root: Callable
var _functions: ExprFunctions


static var _standard: ExprFunctions


static func standard_functions() -> ExprFunctions:
	if _standard == null:
		_standard = ExprFunctions.standard()
	return _standard


## `schema` maps root names to type names or nested namespace Dictionaries.
## `expected` is the required result type, such as "bool" or "number|null".
static func compile(text: String, schema: Dictionary = {}, expected_type: String = "any", functions: ExprFunctions = null) -> Formula:
	var formula := Formula.new()
	formula.source = text
	formula.expected = expected_type
	formula._functions = functions if functions != null else standard_functions()
	var parser := ExprParser.new()
	var ast: Variant = parser.parse(text)
	if ast == null:
		formula._add_error(parser.error_pos, parser.error)
		return formula
	var checker := ExprTypeChecker.new()
	var result := checker.check(ast, schema, formula._functions)
	for problem in checker.errors:
		formula._add_error(problem.pos, problem.message)
	if not formula.errors.is_empty():
		return formula
	if not ExprTypeChecker.fits(result, expected_type):
		formula._add_error(0, "Expected %s, but this gives %s" % [_describe(expected_type), _describe(result)])
		return formula
	formula.result_type = result
	var keys := checker.reads.keys()
	keys.sort()
	formula.reads = PackedStringArray(keys)
	formula._root = ExprEvaluator.new().compile(ast)
	return formula


## A literal field value used where a formula is allowed, such as "weight": 2.
static func constant(value: Variant, expected_type: String = "any") -> Formula:
	var formula := Formula.new()
	formula.source = JSON.stringify(value)
	formula.expected = expected_type
	formula._functions = standard_functions()
	var fixed: Variant = float(value) if value is int else value
	formula.result_type = "null" if fixed == null else ("bool" if fixed is bool else ("number" if fixed is float else "any"))
	formula._root = func(_env: ExprEvaluator.Env) -> Variant: return fixed
	return formula


static func _describe(kind: String) -> String:
	match kind:
		"bool":
			return "a condition (true/false)"
		"number":
			return "a number"
		"string":
			return "text"
	return kind.replace("|", " or ")


func _add_error(pos: int, message: String) -> void:
	errors.append({"column": maxi(pos, 0) + 1, "message": message})


func ok() -> bool:
	return errors.is_empty()


func error_text() -> String:
	var lines := PackedStringArray()
	for problem in errors:
		lines.append("column %d: %s" % [problem.column, problem.message])
	return "; ".join(lines)


## Evaluates against a Dictionary, or an object with expr_get(name), of root values.
func evaluate(values: Variant = {}) -> Variant:
	last_error = ""
	if not ok():
		last_error = error_text()
		return null
	var env := ExprEvaluator.Env.new(values, _functions)
	var result: Variant = _root.call(env)
	if not env.error.is_empty():
		last_error = "column %d: %s" % [maxi(env.error_pos, 0) + 1, env.error]
		return null
	if result is int:
		result = float(result)
	if result != null and not ExprFunctions.value_fits(result, expected):
		last_error = "Expected %s, got %s" % [_describe(expected), ExprEvaluator.type_name(result)]
		return null
	return result


## A condition: any error or non-true result is false.
func test(values: Variant = {}) -> bool:
	var result: Variant = evaluate(values)
	return result is bool and result


func number(values: Variant = {}, fallback: float = 0.0) -> float:
	var result: Variant = evaluate(values)
	return float(result) if result is float else fallback
