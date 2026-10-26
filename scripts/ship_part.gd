class_name ShipPart
extends RefCounted

enum Type {
	# Serialized values: never reorder or recycle these IDs.
	ARMOR_BLOCK = 0,
	LASER = 1,
	DOUBLE_LASER = 2,
	SINGLE_PLATE = 3,
	SHIELD = 4,
	MINI_TURRET = 5,
	THRUSTER = 6,
	LARGE_THRUSTER = 7,
	COMMAND_CENTER = 8,
	CREW_QUARTERS = 9,
	RESEARCH_LAB = 10,
	REPAIR_STATION = 11,
	POINT_DEFENSE_TURRET = 12,
	MISSILE_RACK = 13,
	FOCUSING_LENS = 14,
	BEAM_LANCE = 15,
	STELLAR_LANCE = 16,
	ION_EMITTER = 17,
	GRAVITIC_SNARE = 18,
	SINGULARITY_PROJECTOR = 19,
	REACTIVE_BULKHEAD = 20,
	SHIELD_RELAY = 21,
	AEGIS_CITADEL = 22,
	REPAIR_DRONE_BAY = 23,
	NANOFORGE = 24,
	ARK_RESTORATION_CORE = 25,
	AMMUNITION_MAGAZINE = 26,
	RAILGUN = 27,
	SIEGE_MASS_DRIVER = 28,
	FLIGHT_DECK = 29,
	TORPEDO_BOMBER_BAY = 30,
	HIVE_CARRIER_CORE = 31,
	COMMAND_UPLINK = 32,
	TACTICAL_COMPUTER = 33,
	ADMIRALTY_NEXUS = 34,
	ECM_SUITE = 35,
	PHASE_DRIVE = 36,
	GHOST_NETWORK = 37,
	PASSENGER_CABIN = 38,
	OBSERVATION_DECK = 39,
	LUXURY_SUITES = 40,
	GRAND_PROMENADE = 41,
	CARGO_HOLD = 42,
	TRACTOR_ARRAY = 43,
	SORTING_REFINERY = 44,
	INDUSTRIAL_FOUNDRY = 45,
	ANALYSIS_ARRAY = 46,
	QUANTUM_OBSERVATORY = 47,
	SENSOR_ARRAY = 48,
	RADAR_RELAY = 49,
	CLOAK_GENERATOR = 50,
	MINING_LASER = 51,
	EXTRACTION_DRILL = 52,
	ORE_PROCESSOR = 53,
	SEISMIC_CUTTER = 54,
	PLANETCRACKER_CORE = 55,
}

enum Category {
	OFFENSE = 0,
	DEFENSE = 1,
	SPECIAL = 2, # Tech; legacy serialized name.
	CORE = 3, # Civic; legacy serialized name.
}

enum TechCategory {
	CORE = 0, # Foundation; legacy serialized name.
	ENERGY = 1,
	UTILITY = 2,
}

var type: int
var category: int
var origin: Vector2i
var cell_offsets: Array[Vector2i] = []
var hidden_tile_offsets: Array[Vector2i] = []
var stats: ShipPartStats


func _init(
	part_type: int,
	part_category: int,
	part_origin: Vector2i,
	part_cell_offsets: Array[Vector2i],
	part_stats: ShipPartStats,
	part_hidden_tile_offsets: Array[Vector2i] = []
) -> void:
	if part_stats == null:
		push_error("A ship part must have stat values.")
		return

	type = part_type
	category = part_category
	origin = part_origin
	cell_offsets = part_cell_offsets.duplicate()
	hidden_tile_offsets = part_hidden_tile_offsets.duplicate()
	stats = part_stats.copy()


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in cell_offsets:
		cells.append(origin + offset)
	return cells


func get_hidden_tile_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in hidden_tile_offsets:
		cells.append(origin + offset)
	return cells


func occupies_cell(cell: Vector2i) -> bool:
	return cell_offsets.has(cell - origin)
