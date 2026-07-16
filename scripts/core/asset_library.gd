class_name AssetLibrary extends RefCounted

## Central resolver for optional user-provided assets under res://assets/.
##
## Every lookup returns null (or an empty container) when the file is missing,
## so callers fall back to their procedural placeholder. Conventions (paths,
## sheet layouts, formats) are documented in assets/README.md.
##
## Import caveat: resources (.png/.glb/.ogg/...) only load once Godot has
## imported them (.godot cache). ResourceLoader.exists() honors that cache;
## FileAccess is only used for plain files (.json) and to diagnose the
## "file on disk but not imported" case with a one-time warning.

const ROOT: String = "res://assets/"

static var _cache: Dictionary = {}          # abs path -> Resource (or null)
static var _warned: Dictionary = {}         # abs path -> true (warning emitted)


static func exists(rel: String) -> bool:
	return ResourceLoader.exists(ROOT + rel)


## Loads any imported resource; null when missing. Results (including misses)
## are cached — assets do not change during a session.
static func _resource(rel: String) -> Resource:
	var path: String = ROOT + rel
	if _cache.has(path):
		return _cache[path]
	var res: Resource = null
	if ResourceLoader.exists(path):
		res = load(path)
	elif FileAccess.file_exists(path) and not _warned.has(path):
		_warned[path] = true
		push_warning("AssetLibrary: '%s' liegt auf der Platte, ist aber nicht importiert — bitte '--headless --import' ausfuehren (Fallback auf Platzhalter)." % path)
	_cache[path] = res
	return res


static func texture(rel: String) -> Texture2D:
	return _resource(rel) as Texture2D


## Returns a decompressed, mutable Image copy of a texture (for atlas
## blitting); null when missing.
static func image(rel: String) -> Image:
	var tex: Texture2D = texture(rel)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		push_warning("AssetLibrary: '%s' ist VRAM-komprimiert importiert — fuer Unit-Sheets Lossless-Import verwenden (Qualitaetsverlust)." % (ROOT + rel))
		img.decompress()
	return img


static func model(rel: String) -> PackedScene:
	return _resource(rel) as PackedScene


static func instantiate_model(rel: String) -> Node3D:
	var scene: PackedScene = model(rel)
	if scene == null:
		return null
	return scene.instantiate() as Node3D


static func stream(rel: String) -> AudioStream:
	return _resource(rel) as AudioStream


## Parses a plain JSON file (not an imported resource); {} when missing/invalid.
static func json(rel: String) -> Dictionary:
	var path: String = ROOT + rel
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("AssetLibrary: '%s' ist kein gueltiges JSON-Objekt." % path)
	return {}


## Collects numbered variants <prefix>_0.<ext>, <prefix>_1.<ext>, ... (ogg or
## wav) and stops at the first gap. Empty array when none exist.
static func stream_variants(rel_prefix: String) -> Array[AudioStream]:
	var variants: Array[AudioStream] = []
	var index: int = 0
	while true:
		var found: AudioStream = null
		for ext in ["ogg", "wav"]:
			var rel: String = "%s_%d.%s" % [rel_prefix, index, ext]
			if exists(rel):
				found = stream(rel)
				break
		if found == null:
			break
		variants.append(found)
		index += 1
	return variants


## Lists imported audio streams directly inside an assets/ folder (used for
## music/ambience playlists). Sorted by filename for a stable order.
static func stream_folder(rel_dir: String) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	var dir: DirAccess = DirAccess.open(ROOT + rel_dir)
	if dir == null:
		return streams
	var names: Array[String] = []
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			# Exported builds list "<name>.import" remaps instead of the source.
			var base: String = name.trim_suffix(".import")
			if base.get_extension() in ["ogg", "wav"] and not names.has(base):
				names.append(base)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var s: AudioStream = stream(rel_dir + "/" + n)
		if s != null:
			streams.append(s)
	return streams
