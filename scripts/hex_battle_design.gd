class_name HexBattleDesign
extends Ship

# Runtime view for existing combat/support APIs. This is not a square blueprint:
# serialization always retains the explicit hex schema, rejected by legacy loaders.
var blueprint: HexShipDesign

func to_design_data() -> Dictionary:
	return blueprint.to_data() if blueprint != null else {}
