class_name GameSettings extends RefCounted

## Persisted user settings (phase 8). Static helpers in the AudioSettings
## style, but backed by a ConfigFile at user://settings.cfg so choices survive
## restarts. Currently: the FPS overlay toggle (default OFF) and the window
## resolution (default 1920x1080; supported targets 1080p and 1440p).

const FILE_PATH: String = "user://settings.cfg"
const SECTION: String = "display"

const DEFAULT_RESOLUTION: Vector2i = Vector2i(1920, 1080)
## Selectable window resolutions (bug backlog #1: 1080p and 1440p must both
## show the full UI). Index-aligned with the options menu entries.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2560, 1440)]

static var _loaded: bool = false
static var _show_fps: bool = false
static var _resolution: Vector2i = DEFAULT_RESOLUTION


static func show_fps() -> bool:
	_ensure_loaded()
	return _show_fps


static func set_show_fps(value: bool) -> void:
	_ensure_loaded()
	_show_fps = value
	_save()


static func resolution() -> Vector2i:
	_ensure_loaded()
	return _resolution


static func set_resolution(value: Vector2i) -> void:
	_ensure_loaded()
	_resolution = value
	_save()


## Resizes and re-centres the OS window to the stored resolution. No-op in
## headless runs (tests/benchmarks) where there is no window to resize.
static func apply_resolution() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_loaded()
	var window_id: int = DisplayServer.MAIN_WINDOW_ID
	if DisplayServer.window_get_mode(window_id) != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	DisplayServer.window_set_size(_resolution, window_id)
	var screen: int = DisplayServer.window_get_current_screen(window_id)
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - _resolution) / 2, window_id)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(FILE_PATH) == OK:
		_show_fps = bool(cfg.get_value(SECTION, "show_fps", false))
		var w: int = int(cfg.get_value(SECTION, "resolution_w", DEFAULT_RESOLUTION.x))
		var h: int = int(cfg.get_value(SECTION, "resolution_h", DEFAULT_RESOLUTION.y))
		_resolution = Vector2i(w, h)


static func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(FILE_PATH)   # keep unrelated sections when the file already exists
	cfg.set_value(SECTION, "show_fps", _show_fps)
	cfg.set_value(SECTION, "resolution_w", _resolution.x)
	cfg.set_value(SECTION, "resolution_h", _resolution.y)
	cfg.save(FILE_PATH)
