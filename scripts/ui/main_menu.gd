class_name MainMenu extends Control

## Full-screen main menu (project main scene, phase 7). Three pages built in
## code with the procedural UiTheme look: the root menu, the skirmish setup
## (AI count + map) and the options (master volume). Starting a match stores a
## MatchConfig in GameState and switches to the game scene.

const GAME_SCENE_PATH: String = "res://scenes/main.tscn"

var _pages: Array[Control] = []
## Index of the survival scenario page in _pages.
const SURVIVAL_PAGE: int = 4
## Index of the save-game page in _pages (2026-11-23).
const LOAD_PAGE: int = 5
var _load_list: VBoxContainer = null
var _load_status: Label = null
var _center: CenterContainer = null
var _ai_count_option: OptionButton = null
## One personality choice per AI slot (2026-11-22); rows beyond the AI count hide.
var _personality_rows: Array[HBoxContainer] = []
var _personality_options: Array[OptionButton] = []
## Personality ids, index-aligned with the items of every personality option.
const PERSONALITY_CHOICES: Array[StringName] = [
	MatchConfig.PERSONALITY_RANDOM, &"aggressive", &"economic", &"defensive"]
const PERSONALITY_LABELS: Array[String] = ["Zufällig", "Aggressiv", "Ökonom", "Verteidiger"]
var _map_option: OptionButton = null
var _map_desc: Label = null
## Selectable map ids, index-aligned with the OptionButton items.
var _map_ids: PackedStringArray = MapGenerator.map_ids()

## Controls page (rebinding): action currently waiting for a key press,
## &"" = no capture running.
var _rebind_action: StringName = &""
var _key_buttons: Dictionary = {}   # StringName action -> Button
var _rebind_hint: Label = null


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
	_pages.append(_build_controls_page())
	_pages.append(_build_survival_page())   # index SURVIVAL_PAGE
	_pages.append(_build_load_page())       # index LOAD_PAGE
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
	# `godot ... -- survival` starts the survival mode directly (same match as
	# the menu button "Überleben").
	if args.has("survival"):
		_launch.call_deferred(MatchConfig.survival())
		return
	# `godot ... -- survival_endless` starts the endless survival directly.
	if args.has("survival_endless"):
		_launch.call_deferred(MatchConfig.survival_endless())
		return
	# `-- survival_large` / `-- survival_golems`: the scenarios of 2026-11-19 directly.
	if args.has("survival_large"):
		_launch.call_deferred(MatchConfig.survival_large())
		return
	if args.has("survival_golems"):
		_launch.call_deferred(MatchConfig.survival_golems())
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
	_add_button(vb, "Survivalszenarien", func() -> void: _show_page(SURVIVAL_PAGE))
	_add_button(vb, "Spielstand laden", _open_load_page)
	_add_button(vb, "Stresstest", _start_stress_test)
	_add_button(vb, "Optionen", func() -> void: _show_page(2))
	_add_button(vb, "Beenden", func() -> void: get_tree().quit())
	return vb.get_parent() as Control


## Survival scenarios (user spec 2026-11-16): the 20-wave survival and the
## endless one, where the waves never stop and keep growing.
func _build_survival_page() -> Control:
	var vb: VBoxContainer = _make_page("Survivalszenarien")
	_add_button(vb, "Überleben (%d Wellen)" % Balance.SURVIVAL_WAVE_COUNT, _start_survival)
	_add_button(vb, "Endlos-Überleben", _start_survival_endless)
	_add_button(vb, "Überleben auf großer Karte (%d Wellen)" % Balance.SURVIVAL_WAVE_COUNT,
		func() -> void: _launch(MatchConfig.survival_large()))
	_add_button(vb, "Golem-Überleben", func() -> void: _launch(MatchConfig.survival_golems()))
	var note: Label = Label.new()
	note.text = ("Endlos: nach Welle %d geht es weiter, jede Welle größer als die davor — bis die Basis fällt.\n"
		+ "Große Karte: doppelte Kantenlänge, doppelter Zuwachs je Welle, doppelte Pause.\n"
		+ "Golem-Überleben: zwei Golems mit %.1f m, Gegner von allen Seiten, %d mehr je Welle alle %.0f s — "
		+ "verloren, wenn beide tot sind.") % [Balance.SURVIVAL_WAVE_COUNT, Balance.GOLEM_SURVIVAL_HEIGHT,
		Balance.GOLEM_SURVIVAL_WAVE_STEP, Balance.GOLEM_SURVIVAL_INTERVAL]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	note.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(note)
	vb.add_child(HSeparator.new())
	_add_button(vb, "Zurück", func() -> void: _show_page(0))
	return vb.get_parent() as Control


## Save games (2026-11-23): one button per slot, newest first. Today the match
## writes only the quick slot, but the list already shows every slot on disk.
func _build_load_page() -> Control:
	var vb: VBoxContainer = _make_page("Spielstand laden")
	_load_list = VBoxContainer.new()
	_load_list.add_theme_constant_override("separation", 6)
	vb.add_child(_load_list)
	_load_status = Label.new()
	_load_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_load_status.custom_minimum_size = Vector2(300, 0)
	_load_status.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_load_status)
	vb.add_child(HSeparator.new())
	_add_button(vb, "Zurück", func() -> void: _show_page(0))
	return vb.get_parent() as Control


func _open_load_page() -> void:
	for child in _load_list.get_children():
		child.queue_free()
	var slots: Array[Dictionary] = SaveGame.list_slots()
	_load_status.text = ("" if not slots.is_empty()
		else "Noch kein Spielstand vorhanden. Im Spiel speichert F5 (oder das Pausemenü).")
	for header in slots:
		var slot: String = String(header.get("slot", ""))
		_add_button(_load_list, SaveGame.describe(header), func() -> void:
			var error: String = SaveGame.load_into_game(get_tree(), slot)
			if error != "":
				_load_status.text = error)
	_show_page(LOAD_PAGE)


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
	_ai_count_option.item_selected.connect(func(_i: int) -> void: _update_personality_rows())
	vb.add_child(_ai_count_option)

	# Personality per AI (2026-11-22): aggressive attacks early, the economist builds
	# many huts first, the defender towers and vehicles.
	var pers_label: Label = Label.new()
	pers_label.text = "KI-Persönlichkeit"
	pers_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	pers_label.tooltip_text = "Aggressiv: greift früh mit kleinen Wellen an.\n" \
		+ "Ökonom: baut früh viele Hütten, greift später und stärker an.\n" \
		+ "Verteidiger: mehr Türme, früh Fahrzeuge, breitet sich langsamer aus."
	pers_label.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(pers_label)
	for slot in range(MatchConfig.MAX_AI):
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = Label.new()
		name_label.text = "KI %d" % (slot + 1)
		name_label.custom_minimum_size = Vector2(48, 0)
		name_label.add_theme_color_override("font_color", UiTheme.GOLD)
		row.add_child(name_label)
		var option: OptionButton = OptionButton.new()
		UiTheme.style_button(option)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for label in PERSONALITY_LABELS:
			option.add_item(label)
		option.select(0)
		row.add_child(option)
		vb.add_child(row)
		_personality_rows.append(row)
		_personality_options.append(option)
	_update_personality_rows()

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

	# Ein Regler je Kanal (Gesamt, Effekte, Bedienung, Musik & Umgebung); die
	# Liste steht in AudioSettings.CHANNELS, der Bau in UiTheme.volume_row.
	var sound_label: Label = Label.new()
	sound_label.text = "Lautstärke"
	sound_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(sound_label)
	for channel in AudioSettings.CHANNELS:
		vb.add_child(UiTheme.volume_row(channel["key"] as StringName, 220))

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
	_add_button(vb, "Steuerung", func() -> void: _show_page(3))
	_add_button(vb, "Zurück", func() -> void: _show_page(0))
	return vb.get_parent() as Control


## Controls page (index 3): every rebindable action as a label + key button.
## Clicking a key button starts the capture mode (_input); the next key press
## rebinds via InputSettings, Esc cancels, conflicts are rejected with a hint.
func _build_controls_page() -> Control:
	var vb: VBoxContainer = _make_page("Steuerung")

	var scroll: ScrollContainer = ScrollContainer.new()
	# ~25 rows would blow past the window height — scroll inside the panel.
	scroll.custom_minimum_size = Vector2(460, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var last_category: String = ""
	for entry in InputSettings.ACTIONS:
		var action: StringName = entry[0]
		var category: String = entry[2]
		if category != last_category:
			last_category = category
			var header: Label = Label.new()
			header.text = category
			header.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
			list.add_child(header)

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(row)

		var name_label: Label = Label.new()
		name_label.text = entry[1]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var key_button: Button = Button.new()
		key_button.text = InputSettings.key_display_name(action)
		key_button.custom_minimum_size = Vector2(90, 0)
		UiTheme.style_button(key_button)
		key_button.pressed.connect(_start_rebind.bind(action))
		row.add_child(key_button)
		_key_buttons[action] = key_button

	vb.add_child(HSeparator.new())
	_rebind_hint = Label.new()
	_rebind_hint.text = " "
	_rebind_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rebind_hint.custom_minimum_size = Vector2(300, 0)
	_rebind_hint.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_rebind_hint)

	_add_button(vb, "Auf Standard zurücksetzen", _on_reset_bindings)
	_add_button(vb, "Zurück", func() -> void:
		_end_rebind()
		_show_page(2))
	return vb.get_parent() as Control


func _start_rebind(action: StringName) -> void:
	# Refresh a possibly still-capturing previous button first.
	_end_rebind()
	_rebind_action = action
	var button: Button = _key_buttons[action]
	button.text = "Taste drücken…"
	# Without this, Space/Enter would activate the focused button again
	# instead of being captured as the new binding.
	button.release_focus()
	_rebind_hint.text = "Neue Taste für »%s« drücken — Esc bricht ab." \
		% InputSettings.action_label(action)


func _end_rebind() -> void:
	_rebind_action = &""
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = InputSettings.key_display_name(action)


func _on_reset_bindings() -> void:
	_end_rebind()
	InputSettings.reset_all()
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = InputSettings.key_display_name(action)
	_rebind_hint.text = "Alle Tasten auf Standard zurückgesetzt."


## Key capture for the controls page. _input (not _unhandled_input) so the
## pressed key cannot be swallowed by a focused control first.
func _input(event: InputEvent) -> void:
	if _rebind_action == &"" or not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode == KEY_ESCAPE:
		_end_rebind()
		_rebind_hint.text = "Abgebrochen."
		return
	var other: StringName = InputSettings.action_using_keycode(
		int(key.physical_keycode), _rebind_action)
	if other == _rebind_action:
		# Same key again: nothing to change, just leave the capture mode.
		_end_rebind()
		_rebind_hint.text = " "
		return
	if other != &"":
		var owner_label: String = InputSettings.action_label(other)
		if other == &"ui_cancel":
			owner_label = "Abbrechen/Pause (Esc)"
		elif other in InputSettings._BLOCKED_ACTIONS:
			owner_label = "Debug (%s)" % OS.get_keycode_string(key.physical_keycode)
		_rebind_hint.text = "Taste bereits belegt: %s — andere Taste drücken." % owner_label
		return
	var rebound: StringName = _rebind_action
	InputSettings.rebind(rebound, int(key.physical_keycode))
	_end_rebind()
	_rebind_hint.text = "»%s« liegt jetzt auf %s." % [
		InputSettings.action_label(rebound),
		InputSettings.key_display_name(rebound)]


# --- Match start -----------------------------------------------------------------

func _on_map_selected(index: int) -> void:
	if _map_desc != null and index >= 0 and index < _map_ids.size():
		_map_desc.text = _map_description(_map_ids[index])


## Shows one personality row per selected AI.
func _update_personality_rows() -> void:
	var count: int = _ai_count_option.get_selected_id() if _ai_count_option != null else 1
	for slot in range(_personality_rows.size()):
		_personality_rows[slot].visible = slot < count


func _start_skirmish() -> void:
	var ai_count: int = _ai_count_option.get_selected_id()
	var map_id: String = _map_ids[_map_option.selected]
	var personalities: Array[StringName] = []
	for slot in range(ai_count):
		var index: int = _personality_options[slot].selected if slot < _personality_options.size() else 0
		personalities.append(PERSONALITY_CHOICES[clampi(index, 0, PERSONALITY_CHOICES.size() - 1)])
	_launch(MatchConfig.skirmish(ai_count, map_id, personalities))


func _start_mission() -> void:
	_launch(MatchConfig.start_mission())


func _start_debug_battle() -> void:
	_launch(MatchConfig.debug_battle())


func _start_stress_test() -> void:
	_launch(MatchConfig.stress_test())


func _start_survival() -> void:
	_launch(MatchConfig.survival())


func _start_survival_endless() -> void:
	_launch(MatchConfig.survival_endless())


func _launch(config: MatchConfig) -> void:
	GameState.match_config = config
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
