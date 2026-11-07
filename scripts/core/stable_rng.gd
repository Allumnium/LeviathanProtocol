class_name StableRng
extends RefCounted

## xoshiro128** with 32-bit masked state. Sequences are identical across engine
## versions and platforms, unlike RandomNumberGenerator.

const MASK32 := 0xFFFFFFFF
const TWO_32 := 4294967296.0

var _s: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])


static func from_key(seed_key: String) -> StableRng:
	var rng := StableRng.new()
	rng.seed_key(seed_key)
	return rng


static func from_parts(parts: Array) -> StableRng:
	return from_key(StableHash.key(parts))


func seed_key(seed_key_text: String) -> void:
	for index in 4:
		_s[index] = fmix32(StableHash.u32(seed_key_text + StableHash.SEPARATOR + str(index)))
	if _s[0] == 0 and _s[1] == 0 and _s[2] == 0 and _s[3] == 0:
		_s[0] = 1


## 32-bit multiply without overflowing signed 64-bit intermediates.
static func mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK32


## Murmur3 finalizer: FNV words for adjacent keys are correlated, so mix them.
static func fmix32(value: int) -> int:
	var h := value & MASK32
	h ^= h >> 16
	h = mul32(h, 0x85ebca6b)
	h ^= h >> 13
	h = mul32(h, 0xc2b2ae35)
	h ^= h >> 16
	return h


func state() -> PackedInt64Array:
	return _s.duplicate()


func set_state(value: PackedInt64Array) -> bool:
	if value.size() != 4:
		return false
	for word in value:
		if word < 0 or word > MASK32:
			return false
	_s = value.duplicate()
	return true


static func _rotl(value: int, shift: int) -> int:
	return ((value << shift) | (value >> (32 - shift))) & MASK32


func next_u32() -> int:
	var result := (_rotl((_s[1] * 5) & MASK32, 7) * 9) & MASK32
	var t := (_s[1] << 9) & MASK32
	_s[2] ^= _s[0]
	_s[3] ^= _s[1]
	_s[1] ^= _s[2]
	_s[0] ^= _s[3]
	_s[2] ^= t
	_s[3] = _rotl(_s[3], 11)
	return result


## Uniform in [0, 1).
func randf() -> float:
	return float(next_u32()) / TWO_32


func randf_range(from: float, to: float) -> float:
	return from + (to - from) * randf()


## Uniform integer in [from, to], inclusive and unbiased.
func randi_range(from: int, to: int) -> int:
	if to < from:
		var swap := from
		from = to
		to = swap
	var span := to - from + 1
	if span <= 1:
		return from
	if span > MASK32:
		return from + int(randf() * float(span))
	var limit := (MASK32 + 1) - ((MASK32 + 1) % span)
	var value := next_u32()
	while value >= limit:
		value = next_u32()
	return from + value % span


func chance(probability: float) -> bool:
	return randf() < probability


## Returns an index chosen by non-negative weights, or -1 when nothing can be chosen.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for weight in weights:
		total += maxf(float(weight), 0.0)
	if total <= 0.0:
		return -1
	var roll := randf() * total
	var last_positive := -1
	for index in weights.size():
		var weight := maxf(float(weights[index]), 0.0)
		if weight <= 0.0:
			continue
		last_positive = index
		if roll < weight:
			return index
		roll -= weight
	return last_positive


func pick(values: Array) -> Variant:
	if values.is_empty():
		return null
	return values[randi_range(0, values.size() - 1)]


func shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := randi_range(0, index)
		var swap: Variant = values[index]
		values[index] = values[other]
		values[other] = swap
