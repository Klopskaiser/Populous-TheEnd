class_name MainMenu extends Control

## Full-screen main menu (project main scene, phase 7). Three pages built in
## code with the procedural UiTheme look: the root menu, the skirmish setup
## (AI count + map) and the options (master volume). Starting a match stores a
## MatchConfig in GameState and switches to the game scene.

const GAME_SCENE_PATH: String = "res://scenes/main.tscn"

var _pages: Array[Control] = []
var _center: CenterContainer = null
var _ai_count_option: OptionButton = null
var _map_option: OptionButton = null
var _map_desc: Label = null
## Selectable map ids, index-aligned with the OptionButton items.
var _map_ids: PackedStringArray = MapGenerator.map_ids()


## Short German blurb per map, shown under the selector.
static func _map_description(map_id: String) -> String:
	match map_id:
		"island": return "Runde Insel, Wasser ringsum. Standardgröße."
		"seenland": return "Doppelt groß. See in der Mitte, Start in den Ecken, angehobene Ecken."
		"bergpass": return "Doppelt groß. Gebirge mit 3 engen Pässen teilt die Karte in zwei Hälften."
		"plateau": return "Standardgröße. Start auf erhöhtem Plateau mit harten Kanten und einer Rampe."
	return ""


func _ready() -> void:
	# Leaving a match with an active time-lapse (F10) must not speed up the menu.
	Engine.time_scale = 1.0
	# Apply the persisted window resolution once at startup (main_menu is the
	# main scene); afterwards only the options menu changes it.
	GameSettings.apply_resolution()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var background: ColorRect = ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.09, 0.06, 0.04)
	add_child(background)

	# The pages live in a CenterContainer: panels stay centred at any window
	# size (an anchor preset alone lets the growing panel expand down-right).
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	_pages.append(_build_root_page())
	_pages.append(_build_skirmish_page())
	_pages.append(_build_options_page())
	_show_page(0)

	# Headless verification hook: `godot ... -- skirmish=N [map=<id>]` skips the
	# menu and starts a skirmish with N AIs right away (the menu needs mouse input).
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Profiling shortcut (phase 8): `godot ... -- lagtest` starts the
	# reproducible early-lag scenario (bergpass, 3 AIs + player) directly —
	# quick re-entry for editor-profiler runs (F10 time-lapse speeds up the
	# build-up phase in-game).
	if args.has("lagtest"):
		_launch.call_deferred(MatchConfig.skirmish(3, "bergpass"))
		return
	# `godot ... -- stresstest` starts the stress-test match directly (same
	# scenario as the menu button — headless verification + profiler re-entry).
	if args.has("stresstest"):
		_launch.call_deferred(MatchConfig.stress_test())
		return
	var map_arg: String = MapGenerator.DEFAULT_MAP
	for arg in args:
		if arg.begins_with("map="):
			map_arg = arg.get_slice("=", 1)
	for arg in args:
		if arg.begins_with("skirmish="):
			_launch.call_deferred(MatchConfig.skirmish(int(arg.get_slice("=", 1)), map_arg))
			return


# --- Page framework -----------------------------------------------------------

## Centered gold/brown panel with a title; returns the VBox for the content.
func _make_page(title_text: String) -> VBoxContainer:
	var page: PanelContainer = PanelContainer.new()
	page.add_theme_stylebox_override("panel", UiTheme.panel_style())
	page.custom_minimum_size = Vector2(340, 0)
	_center.add_child(page)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	page.add_child(vb)

	var game_title: Label = Label.new()
	game_title.text = "Populous — The End"
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.add_theme_font_size_override("font_size", 28)
	game_title.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(game_title)

	var subtitle: Label = Label.new()
	subtitle.text = title_text
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(subtitle)

	vb.add_child(HSeparator.new())
	# _pages indexes the PanelContainer; content goes into the VBox.
	return vb


func _show_page(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index


func _add_button(vb: VBoxContainer, text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(button)
	button.pressed.connect(handler)
	vb.add_child(button)
	return button


# --- Pages ---------------------------------------------------------------------

func _build_root_page() -> Control:
	var vb: VBoxContainer = _make_page("Hauptmenü")
	_add_button(vb, "Neues Skirmish", func() -> void: _show_page(1))
	_add_button(vb, "Startmission", _start_mission)
	_add_button(vb, "Debugschlacht", _start_debug_battle)
	_add_button(vb, "Stresstest", _start_stress_test)
	_add_button(vb, "Optionen", func() -> void: _show_page(2))
	_add_button(vb, "Beenden", func() -> void: get_tree().quit())
	return vb.get_parent() as Control


func _build_skirmish_page() -> Control:
	var vb: VBoxContainer = _make_page("Neues Skirmish")

	var ai_label: Label = Label.new()
	ai_label.text = "Gegner (KIs)"
	ai_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(ai_label)
	_ai_count_option = OptionButton.new()
	UiTheme.style_button(_ai_count_option)
	for n in range(MatchConfig.MIN_AI, MatchConfig.MAX_AI + 1):
		_ai_count_option.add_item("%d KI%s" % [n, "" if n == 1 else "s"], n)
	_ai_count_option.select(0)
	vb.add_child(_ai_count_option)

	var map_label: Label = Label.new()
	map_label.text = "Karte"
	map_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(map_label)
	_map_option = OptionButton.new()
	UiTheme.style_button(_map_option)
	for map_id in _map_ids:
		_map_option.add_item(MapGenerator.display_name(map_id))
	_map_option.select(0)
	_map_option.item_selected.connect(_on_map_selected)
	vb.add_child(_map_option)

	_map_desc = Label.new()
	_map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_desc.custom_minimum_size = Vector2(300, 0)
	_map_desc.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_map_desc)
	_on_map_selected(0)

	vb.add_child(HSeparator.new())
	_add_button(vb, "Starten", _start_skirmish)
	_add_button(vb, "Zurück", func() -> void: _show_page(0))
	return vb.get_parent() as Control


func _build_options_page() -> Control:
	var vb: VBoxContainer = _make_page("Optionen")

	var volume_label: Label = Label.new()
	volume_label.text = "Soundlautstärke"
	volume_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(volume_label)

	var volume: HSlider = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 5.0
	volume.custom_minimum_size = Vector2(220, 20)
	volume.value = AudioSettings.master_volume_percent()
	volume.value_changed.connect(AudioSettings.set_master_volume_percent)
	vb.add_child(volume)

	# FPS overlay toggle (phase 8), persisted via GameSettings.
	var fps_check: CheckButton = CheckButton.new()
	fps_check.text = "FPS-Anzeige"
	UiTheme.style_button(fps_check)
	fps_check.button_pressed = GameSettings.show_fps()
	fps_check.toggled.connect(GameSettings.set_show_fps)
	vb.add_child(fps_check)

	# Window resolution (bug backlog #1), persisted via GameSettings.
	var resolution_label: Label = Label.new()
	resolution_label.text = "Auflösung"
	resolution_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(resolution_label)

	var resolution_option: OptionButton = OptionButton.new()
	UiTheme.style_button(resolution_option)
	for res in GameSettings.RESOLUTIONS:
		resolution_option.add_item("%d × %d" % [res.x, res.y])
	var current_index: int = GameSettings.RESOLUTIONS.find(GameSettings.resolution())
	resolution_option.select(maxi(current_index, 0))
	resolution_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_resolution(GameSettings.RESOLUTIONS[index])
		GameSettings.apply_resolution())
	vb.add_child(resolution_option)

	vb.add_child(HSeparator.new())
	_add_button(vb, "Zurück", func() -> void: _show_page(0))
	return vb.get_parent() as Control


# --- Match start -----------------------------------------------------------------

func _on_map_selected(index: int) -> void:
	if _map_desc != null and index >= 0 and index < _map_ids.size():
		_map_desc.text = _map_description(_map_ids[index])


func _start_skirmish() -> void:
	var ai_count: int = _ai_count_option.get_selected_id()
	var map_id: String = _map_ids[_map_option.selected]
	_launch(MatchConfig.skirmish(ai_count, map_id))


func _start_mission() -> void:
	_launch(MatchConfig.start_mission())


func _start_debug_battle() -> void:
	_launch(MatchConfig.debug_battle())


func _start_stress_test() -> void:
	_launch(MatchConfig.stress_test())


func _launch(config: MatchConfig) -> void:
	GameState.match_config = config
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
