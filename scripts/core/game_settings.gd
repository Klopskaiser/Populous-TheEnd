class_name GameSettings extends RefCounted

## Persisted user settings (phase 8). Static helpers in the AudioSettings
## style, but backed by a ConfigFile at user://settings.cfg so choices survive
## restarts. Currently: the FPS overlay toggle (default OFF).

const FILE_PATH: String = "user://settings.cfg"
const SECTION: String = "display"

static var _loaded: bool = false
static var _show_fps: bool = false


static func show_fps() -> bool:
	_ensure_loaded()
	return _show_fps


static func set_show_fps(value: bool) -> void:
	_ensure_loaded()
	_show_fps = value
	_save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(FILE_PATH) == OK:
		_show_fps = bool(cfg.get_value(SECTION, "show_fps", false))


static func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(FILE_PATH)   # keep unrelated sections when the file already exists
	cfg.set_value(SECTION, "show_fps", _show_fps)
	cfg.save(FILE_PATH)
