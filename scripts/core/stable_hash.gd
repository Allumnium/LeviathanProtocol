class_name StableHash
extends RefCounted

## FNV-1a 64-bit over UTF-8, computed in 32-bit limbs so results never depend on
## engine hashing or signed 64-bit overflow behavior.

const MASK32 := 0xFFFFFFFF
const OFFSET_HI := 0xcbf29ce4
const OFFSET_LO := 0x84222325
const PRIME_LO := 0x1b3
const SEPARATOR := "\u001f"


static func limbs(text: String) -> PackedInt64Array:
	return limbs_bytes(text.to_utf8_buffer())


static func limbs_bytes(bytes: PackedByteArray) -> PackedInt64Array:
	var hi := OFFSET_HI
	var lo := OFFSET_LO
	for byte in bytes:
		lo = lo ^ byte
		var low_product := lo * PRIME_LO
		# The prime is 2^40 + 0x1b3: the 2^40 term shifts lo's low 24 bits into hi.
		var next_hi := (hi * PRIME_LO + (low_product >> 32) + ((lo & 0xFFFFFF) << 8)) & MASK32
		lo = low_product & MASK32
		hi = next_hi
	return PackedInt64Array([hi, lo])


static func hex64(text: String) -> String:
	var parts := limbs(text)
	return "%08x%08x" % [parts[0], parts[1]]


## Non-negative 63-bit integer, safe for seeds and Dictionary keys.
static func int63(text: String) -> int:
	var parts := limbs(text)
	return ((parts[0] & 0x7FFFFFFF) << 32) | parts[1]


static func u32(text: String) -> int:
	var parts := limbs(text)
	return (parts[0] ^ parts[1]) & MASK32


## Joins parts with a unit separator so ["ab", "c"] and ["a", "bc"] differ.
static func key(parts: Array) -> String:
	var strings := PackedStringArray()
	for part in parts:
		strings.append(str(part))
	return SEPARATOR.join(strings)


static func of_parts(parts: Array) -> int:
	return int63(key(parts))
