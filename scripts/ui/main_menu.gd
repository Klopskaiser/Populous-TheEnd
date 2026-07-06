class_name MainMenu extends Control

## Full-screen main menu (project main scene, phase 7). Three pages built in
## code with the procedural UiTheme look: the root menu, the skirmish setup
## (AI count + map) and the options (master volume). Starting a match stores a
## MatchConfig in GameState and switches to the game scene.

const GAME_SCENE_PATH: String = "res://scenes/main.tscn"

## Selectable maps (only the fixed skirmish island exists so far).
const MAPS: Array[Dictionary] = [
	{"id": "island", "name": "Insel"},
]

var _pages: Array[Control] = []
var _center: CenterContainer = null
var _ai_count_option: OptionButton = null
var _map_option: OptionButton = null


func _ready() -> void:
	# Leaving a match with an active time-lapse (F10) must not speed up the menu.
	Engine.time_scale = 1.0
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

	# Headless verification hook: `godot ... -- skirmish=N` skips the menu and
	# starts a skirmish with N AIs right away (the menu needs mouse input).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("skirmish="):
			_launch.call_deferred(MatchConfig.skirmish(int(arg.get_slice("=", 1))))
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
	for map_entry in MAPS:
		_map_option.add_item(map_entry["name"])
	_map_option.select(0)
	vb.add_child(_map_option)

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

	vb.add_child(HSeparator.new())
	_add_button(vb, "Zurück", func() -> void: _show_page(0))
	return vb.get_parent() as Control


# --- Match start -----------------------------------------------------------------

func _start_skirmish() -> void:
	var ai_count: int = _ai_count_option.get_selected_id()
	var map_id: String = MAPS[_map_option.selected]["id"]
	_launch(MatchConfig.skirmish(ai_count, map_id))


func _start_mission() -> void:
	_launch(MatchConfig.start_mission())


func _start_debug_battle() -> void:
	_launch(MatchConfig.debug_battle())


func _launch(config: MatchConfig) -> void:
	GameState.match_config = config
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
