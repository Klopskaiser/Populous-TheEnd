class_name InputSettings extends RefCounted

## Persisted keyboard bindings (rebindable via the main menu's "Steuerung"
## page). Static helpers in the GameSettings style, backed by the same
## ConfigFile at user://settings.cfg but with its own [input] section. Only
## OVERRIDES are stored (action name -> physical keycode); actions without an
## override keep following the project.godot defaults, so tuning a default
## later still reaches every player who never rebound that key.
##
## Deliberately NOT rebindable:
## - Mouse actions (select/command/add_waypoint/camera_zoom_*): the
##   SelectionManager reads raw MOUSE_BUTTON_* indices, so remapping the
##   actions would have no effect and only fake a choice.
## - ui_cancel (Esc): context-sensitive cancel/pause wiring — remapping it
##   risks states the player cannot leave.
## - stress_test / time_scale_toggle (F1/F2): debug tools, not game functions.

const FILE_PATH: String = "user://settings.cfg"
const SECTION: String = "input"

## Rebindable actions: [action, German label, category]. Order = display order
## in the controls menu; categories group consecutive rows under one header.
## Spell labels follow SpellTargeting.HOTKEY_SPELLS (keys 1-9 and 0).
const ACTIONS: Array[Array] = [
	[&"camera_forward", "Kamera vor", "Kamera"],
	[&"camera_back", "Kamera zurück", "Kamera"],
	[&"camera_left", "Kamera links", "Kamera"],
	[&"camera_right", "Kamera rechts", "Kamera"],
	[&"camera_rotate_left", "Kamera drehen links", "Kamera"],
	[&"camera_rotate_right", "Kamera drehen rechts", "Kamera"],
	[&"attack_move_arm", "Angriffsbewegung", "Befehle"],
	[&"toggle_patrol", "Patrouille an/aus", "Befehle"],
	[&"toggle_ranges", "Reichweiten anzeigen", "Befehle"],
	[&"build_hut", "Hütte bauen", "Bauen"],
	[&"rotate_building", "Gebäude drehen", "Bauen"],
	[&"select_all_huts", "Alle Hütten wählen", "Gebäude-Auswahl"],
	[&"select_all_warrior_camps", "Alle Kasernen wählen", "Gebäude-Auswahl"],
	[&"select_all_temples", "Alle Tempel wählen", "Gebäude-Auswahl"],
	[&"select_all_firewarrior_camps", "Alle Feuertempel wählen", "Gebäude-Auswahl"],
	[&"cast_spell_1", "Zauber 1 (Feuerball)", "Zauber"],
	[&"cast_spell_2", "Zauber 2 (Blitz)", "Zauber"],
	[&"cast_spell_3", "Zauber 3 (Schwarm)", "Zauber"],
	[&"cast_spell_4", "Zauber 4 (Landbrücke)", "Zauber"],
	[&"cast_spell_5", "Zauber 5 (Tornado)", "Zauber"],
	[&"cast_spell_6", "Zauber 6 (Erdbeben)", "Zauber"],
	[&"cast_spell_7", "Zauber 7 (Vulkan)", "Zauber"],
	[&"cast_spell_8", "Zauber 8 (Feuerregen)", "Zauber"],
	[&"cast_spell_9", "Zauber 9 (Ebene)", "Zauber"],
	[&"cast_spell_10", "Zauber 0 (Absinken)", "Zauber"],
	[&"cast_spell_11", "Zauber ß (Supertornado)", "Zauber"],
]

## Non-rebindable actions whose keys are still off-limits for rebinding (their
## keycodes are read from the live InputMap, so enum values never drift).
const _BLOCKED_ACTIONS: Array[StringName] = [&"stress_test", &"time_scale_toggle"]

static var _loaded: bool = false
static var _overrides: Dictionary = {}   # StringName -> int (physical keycode)
static var _defaults: Dictionary = {}    # StringName -> int (project.godot keycode)


static func action_label(action: StringName) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[1]
	return String(action)


static func action_category(action: StringName) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return entry[2]
	return ""


## Current physical keycode of the action (override, or project.godot default).
static func current_keycode(action: StringName) -> int:
	_ensure_loaded()
	return int(_overrides.get(action, _defaults.get(action, 0)))


## Layout-correct key name for the controls menu buttons ("W", "Ö", "F5", ...).
static func key_display_name(action: StringName) -> String:
	var pk: int = current_keycode(action)
	if pk == 0:
		return "—"
	var keycode: int = pk
	# The physical->layout mapping needs a real display server; headless runs
	# (tests/verification) fall back to the physical key name.
	if DisplayServer.get_name() != "headless":
		var mapped: int = DisplayServer.keyboard_get_keycode_from_physical(pk)
		if mapped != 0:
			keycode = mapped
	return OS.get_keycode_string(keycode)


## Other rebindable action already using this physical keycode (conflict
## check), or the blocked debug/cancel action holding it. &"" when free.
static func action_using_keycode(keycode: int, except: StringName) -> StringName:
	_ensure_loaded()
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if action != except and current_keycode(action) == keycode:
			return action
	if keycode == KEY_ESCAPE:
		return &"ui_cancel"
	for action in _BLOCKED_ACTIONS:
		if _action_keycode_from_map(action) == keycode:
			return action
	return &""


## Rebinds the action: applies the key to the live InputMap and persists it.
static func rebind(action: StringName, physical_keycode: int) -> void:
	_ensure_loaded()
	if physical_keycode == _defaults.get(action, 0):
		_overrides.erase(action)   # back on default -> drop the override
	else:
		_overrides[action] = physical_keycode
	_apply_to_map(action, physical_keycode)
	_save()


## Drops every override and restores the project.godot defaults.
static func reset_all() -> void:
	_ensure_loaded()
	_overrides.clear()
	for entry in ACTIONS:
		var action: StringName = entry[0]
		_apply_to_map(action, int(_defaults.get(action, 0)))
	_save()


## Applies the persisted overrides to the InputMap. Called once at startup
## (GameState._ready), before any scene processes input.
static func apply_overrides() -> void:
	_ensure_loaded()
	for action in _overrides:
		_apply_to_map(action, int(_overrides[action]))


static func _apply_to_map(action: StringName, physical_keycode: int) -> void:
	if physical_keycode == 0 or not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = physical_keycode as Key
	InputMap.action_add_event(action, key)


## First key event's physical keycode of an action in the live InputMap.
static func _action_keycode_from_map(action: StringName) -> int:
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return int((event as InputEventKey).physical_keycode)
	return 0


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# Snapshot the project.godot defaults BEFORE any override touches the map.
	for entry in ACTIONS:
		_defaults[entry[0]] = _action_keycode_from_map(entry[0])
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(FILE_PATH) == OK and cfg.has_section(SECTION):
		for key in cfg.get_section_keys(SECTION):
			var action: StringName = StringName(key)
			var pk: int = int(cfg.get_value(SECTION, key, 0))
			if pk > 0 and _defaults.has(action) and pk != int(_defaults[action]):
				_overrides[action] = pk


static func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(FILE_PATH)   # keep unrelated sections when the file already exists
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	for action in _overrides:
		cfg.set_value(SECTION, String(action), int(_overrides[action]))
	cfg.save(FILE_PATH)
