extends RefCounted

# Missing art renders as a solid pink square and missing sounds play one
# shared clip, so unfinished assets are easy to spot and replace later.
const ART_COLOR := Color(1.0, 0.0, 1.0)
const SFX_PATH := "res://assets/audio/sfx/dialogue_type.mp3"

static var _art: Texture2D

static func art() -> Texture2D:
	if _art == null:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(ART_COLOR)
		_art = ImageTexture.create_from_image(image)
	return _art

static func texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return art()
	return load(path)

static func sfx() -> AudioStream:
	return load(SFX_PATH)
