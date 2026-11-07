class_name ExprLexer
extends RefCounted

## Tokens are Dictionaries: {"k": kind, "v": value, "pos": 0-based offset}.
## Kinds: num, str, name, op, kw, eof.

const KEYWORDS := ["and", "or", "not", "in", "if", "then", "else", "true", "false", "null"]
const TWO_CHAR := ["==", "!=", "<=", ">="]
const ONE_CHAR := "+-*/%^()[],.<>"
const MISTAKES := {"&&": "and", "||": "or", "!": "not", "=": "=="}

var error: String = ""
var error_pos: int = -1


func tokenize(source: String) -> Array:
	error = ""
	error_pos = -1
	var tokens: Array = []
	var index := 0
	var length := source.length()
	while index < length:
		var c := source[index]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			index += 1
			continue
		var start := index
		if _is_digit(c) or (c == "." and index + 1 < length and _is_digit(source[index + 1])):
			while index < length and _is_digit(source[index]):
				index += 1
			if index < length and source[index] == "." and index + 1 < length and _is_digit(source[index + 1]):
				index += 1
				while index < length and _is_digit(source[index]):
					index += 1
			if index < length and (_is_alpha(source[index])):
				return _fail("Number is followed by letters", start)
			var digits := source.substr(start, index - start)
			tokens.append({"k": "num", "v": digits.to_float(), "s": digits, "pos": start})
			continue
		if _is_alpha(c):
			while index < length and (_is_alpha(source[index]) or _is_digit(source[index])):
				index += 1
			var word := source.substr(start, index - start)
			tokens.append({"k": "kw" if word in KEYWORDS else "name", "v": word, "pos": start})
			continue
		if c == "'" or c == "\"":
			index += 1
			var text := ""
			var closed := false
			while index < length:
				var d := source[index]
				if d == "\\" and index + 1 < length:
					var escaped := source[index + 1]
					text += "\n" if escaped == "n" else escaped
					index += 2
					continue
				if d == c:
					closed = true
					index += 1
					break
				text += d
				index += 1
			if not closed:
				return _fail("Text is missing its closing quote", start)
			tokens.append({"k": "str", "v": text, "pos": start})
			continue
		var pair := source.substr(index, 2)
		if pair in TWO_CHAR:
			tokens.append({"k": "op", "v": pair, "pos": start})
			index += 2
			continue
		if MISTAKES.has(pair):
			return _fail("Use '%s' instead of '%s'" % [MISTAKES[pair], pair], start)
		if MISTAKES.has(c):
			return _fail("Use '%s' instead of '%s'" % [MISTAKES[c], c], start)
		if ONE_CHAR.contains(c):
			tokens.append({"k": "op", "v": c, "pos": start})
			index += 1
			continue
		return _fail("Unexpected character '%s'" % c, start)
	tokens.append({"k": "eof", "v": "", "pos": length})
	return tokens


func _fail(message: String, pos: int) -> Array:
	error = message
	error_pos = pos
	return []


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_alpha(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
