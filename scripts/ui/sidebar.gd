class_name Sidebar extends Control

## The complete, permanent UI shell in the style of Populous: The Beginning —
## a gold/brown panel down the left edge (fixed width, full height). Top to
## bottom: round minimap, shaman portrait, tab bar (buildings / spells /
## followers / crew), header (per-tribe population bars, population count,
## segmented mana bar, wood readout, growth slider), the active tab's content,
## and a menu panel with a pause button. All optics are procedural (see
## UiTheme); the layout is built in code in _ready() and wired via setup().
##
## The CREW tab shows the occupants of the single selected mannable object
## (hut / forester / workshop / watchtower / catapult) as icon buttons (click
## ejects) plus a production pause toggle; it auto-activates on selection and
## is greyed out otherwise. Displays are signal-driven (Events.*_changed); the
## follower counters and minimap overlay are throttled. SelectionManager and
## BuildMenu ignore mouse events over the panel via is_mouse_over_ui().

const PANEL_WIDTH: float = 260.0
const MINIMAP_SIZE: float = 236.0
## Min height of the tab content area: tall enough for the building tab's full
## grid; every tab scrolls as a safety net for short windows.
const TAB_CONTENT_HEIGHT: float = 300.0
## Index of the auto-activating crew tab.
const TAB_CREW: int = 3
const MANA_SEGMENTS: int = 20
## Mana value that fills the whole segmented bar (display only).
const MANA_DISPLAY_CAP: float = 1000.0
const FOLLOWER_INTERVAL: float = 0.3
## "Holz" counts wood in piles within this radius of any of the player's own
## buildings (delivered/stacked wood at the base), not the whole map.
const WOOD_NEAR_RADIUS: float = 12.0

## Follower rows: kind key -> German label.
const FOLLOWER_ROWS: Array[Dictionary] = [
	{"kind": &"brave", "name": "Gefolgsleute", "active": true},
	{"kind": &"warrior", "name": "Krieger", "active": true},
	{"kind": &"firewarrior", "name": "Feuerkrieger", "active": true},
	{"kind": &"preacher", "name": "Prediger", "active": true},
	{"kind": &"siege", "name": "Belagerungswaffe", "active": true},
	{"kind": &"fireram", "name": "Feuerrammen", "active": true},
	{"kind": &"airship", "name": "Luftschiffe", "active": true},
	{"kind": &"shaman", "name": "Schamanin", "active": true},
]

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const FIREWARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const TEMPLE_SCENE: PackedScene = preload("res://scenes/buildings/temple.tscn")
const FORESTER_SCENE: PackedScene = preload("res://scenes/buildings/forester.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const FIRERAM_WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/fire_ram_workshop.tscn")
const AIRSHIP_WHARF_SCENE: PackedScene = preload("res://scenes/buildings/airship_wharf.tscn")
const WATCHTOWER_SCENE: PackedScene = preload("res://scenes/buildings/watchtower.tscn")

# --- Injected references (setup) --------------------------------------------
var _tribes: Array[Tribe] = []
var _player_id: int = 0
var _unit_manager: UnitManager = null
var _building_manager: BuildingManager = null
var _tree_manager: TreeManager = null
var _wood_pile_manager: WoodPileManager = null
var _tribe_commands: TribeCommands = null
var _build_menu: BuildMenu = null
var _selection: SelectionManager = null
var _spell_targeting: SpellTargeting = null
var _camera_rig: Node3D = null

# --- Widgets ----------------------------------------------------------------
var _panel: PanelContainer = null
var _minimap: Minimap = null
var _pop_label: Label = null
var _wood_label: Label = null
var _tribe_bars: Array[ProgressBar] = []
var _mana_segments: Array[ColorRect] = []
var _mana_label: Label = null   # numeric mana + income per second (phase 7i)
var _growth_slider: HSlider = null   # hut growth control (phase 7i)
var _growth_label: Label = null
var _tab_buttons: Array[Button] = []
var _tab_panels: Array[Control] = []
var _tab_content: Control = null
var _spell_ui: Dictionary = {}       # id -> {"button": Button, "pips": Array[ColorRect]}
var _follower_labels: Dictionary = {}  # kind -> Label
var _idle_button: Button = null
## Per-tribe vehicle-cap steppers (followers tab): one entry per vehicle type
## with {label, title, get_cap, set_cap, get_owned, limit}.
var _cap_steppers: Array[Dictionary] = []
var _pause_menu: Control = null
## Crew tab widgets: occupants of the selected mannable object as icon buttons
## (click ejects) plus a production pause toggle.
var _crew_title: Label = null
var _crew_info: Label = null
var _crew_slot_buttons: Array[Button] = []
var _crew_pause_button: Button = null
var _crew_unload_button: Button = null   # airship "Absetzen an…" (unload arm)
## Edge detection for the crew tab's auto-switch: last polled target, the tab
## to return to on deselection, and the currently active tab index.
var _crew_target_obj: Object = null
var _crew_return_tab: int = 0
var _active_tab: int = 0
## Shaman portrait (below the minimap, Populous style): full live-animated
## figure + health bar; click centres the camera on her and selects ONLY her.
var _portrait_sprite: AnimatedSprite2D = null
var _portrait_hp: ProgressBar = null
var _portrait_status: Label = null

var _follower_timer: float = 0.0

## Single instance for the static mouse guard.
static var _instance: Sidebar = null


# --- Static, headless-testable helpers ---------------------------------------

## Whether the pointer is currently over the sidebar panel (used by
## SelectionManager/BuildMenu to ignore clicks that start over the UI).
static func is_mouse_over_ui() -> bool:
	if _instance == null or not is_instance_valid(_instance) or not _instance.visible:
		return false
	var panel: PanelContainer = _instance._panel
	if panel == null:
		return false
	return panel.get_global_rect().has_point(panel.get_global_mouse_position())


## Filled segment count of the mana bar from a mana value, capped at `segments`.
static func mana_segments(mana: float, cap: float, segments: int) -> int:
	if cap <= 0.0 or segments <= 0:
		return 0
	return clampi(int(floor(mana / cap * float(segments))), 0, segments)


## Charge-pip display state: how many pips are full, how many empty, and the
## fill fraction of the next (partial) pip. When all charges are full the
## progress is 0 (nothing is charging).
static func pip_state(charges: int, max_charges: int, charge_progress: float) -> Dictionary:
	var full: int = clampi(charges, 0, max_charges)
	var empty: int = max_charges - full
	var progress: float = 0.0 if full >= max_charges else clampf(charge_progress, 0.0, 1.0)
	return {"filled": full, "empty": empty, "progress": progress}


## Bar length fractions (0..1) proportional to each tribe's population,
## normalised to the largest tribe. All-zero populations yield all zeros
## (no division by zero).
static func tribe_bar_fractions(populations: Array[int]) -> Array[float]:
	var result: Array[float] = []
	var top: int = 0
	for p in populations:
		top = maxi(top, p)
	for p in populations:
		result.append(0.0 if top <= 0 else float(p) / float(top))
	return result


## Registry for the building tab. Disabled entries have no scene (so they yield
## no start_placement target); the hut entry references the Hut scene and cost.
static func default_build_entries() -> Array[Dictionary]:
	return [
		{"id": &"hut", "name": "Hütte", "scene": HUT_SCENE, "icon": &"hut",
			"wood_cost": Hut.WOOD_COST, "enabled": true, "hotkey": "H"},
		{"id": &"warrior_camp", "name": "Kaserne", "scene": WARRIOR_CAMP_SCENE,
			"icon": &"warrior_camp", "wood_cost": WarriorCamp.WOOD_COST, "enabled": true},
		{"id": &"firewarrior_camp", "name": "Feuertempel", "scene": FIREWARRIOR_CAMP_SCENE,
			"icon": &"firewarrior_camp", "wood_cost": FirewarriorCamp.WOOD_COST, "enabled": true},
		{"id": &"temple", "name": "Tempel", "scene": TEMPLE_SCENE,
			"icon": &"temple", "wood_cost": Temple.WOOD_COST, "enabled": true},
		{"id": &"forester", "name": "Försterei", "scene": FORESTER_SCENE,
			"icon": &"forester", "wood_cost": Forester.WOOD_COST, "enabled": true},
		{"id": &"workshop", "name": "Katapultwerkstatt", "scene": WORKSHOP_SCENE,
			"icon": &"workshop", "wood_cost": Workshop.WOOD_COST, "enabled": true},
		{"id": &"fireram_workshop", "name": "Feuerrammenwerkstatt",
			"scene": FIRERAM_WORKSHOP_SCENE, "icon": &"fireram_workshop",
			"wood_cost": FireRamWorkshop.RAM_WOOD_COST, "enabled": true},
		{"id": &"airship_wharf", "name": "Luftschiffwerft", "scene": AIRSHIP_WHARF_SCENE,
			"icon": &"airship_wharf", "wood_cost": AirshipWharf.WHARF_WOOD_COST,
			"enabled": true},
		{"id": &"watchtower", "name": "Wachturm", "scene": WATCHTOWER_SCENE,
			"icon": &"watchtower", "wood_cost": Watchtower.WOOD_COST, "enabled": true},
	]


## Order matches SpellTargeting.HOTKEY_SPELLS (hotkeys 1-9 and 0 for slot 10).
static func default_spell_entries() -> Array[Dictionary]:
	return [
		{"id": &"fireball", "name": "Feuerball", "icon": &"fireball",
			"max_charges": 4, "hotkey": "1"},
		{"id": &"lightning", "name": "Blitz", "icon": &"lightning",
			"max_charges": 4, "hotkey": "2"},
		{"id": &"swarm", "name": "Insektenschwarm", "icon": &"swarm",
			"max_charges": 4, "hotkey": "3"},
		{"id": &"landbridge", "name": "Landbrücke", "icon": &"landbridge",
			"max_charges": 4, "hotkey": "4"},
		{"id": &"tornado", "name": "Tornado", "icon": &"tornado",
			"max_charges": 3, "hotkey": "5"},
		{"id": &"earthquake", "name": "Erdbeben", "icon": &"earthquake",
			"max_charges": 2, "hotkey": "6"},
		{"id": &"volcano", "name": "Vulkan", "icon": &"volcano",
			"max_charges": 1, "hotkey": "7"},
		{"id": &"firestorm", "name": "Feuerregen", "icon": &"firestorm",
			"max_charges": 2, "hotkey": "8"},
		{"id": &"flatten", "name": "Ebene", "icon": &"flatten",
			"max_charges": 3, "hotkey": "9"},
		{"id": &"sink", "name": "Absinken", "icon": &"sink",
			"max_charges": 3, "hotkey": "0"},
	]


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	_instance = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Runs while the tree is paused so Esc/Fortsetzen can unpause the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_pause_menu()
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.population_changed.connect(_on_population_changed)
		events.mana_changed.connect(_on_mana_changed)
		events.stockpile_changed.connect(_on_stockpile_changed)
		events.spell_charges_changed.connect(_on_spell_charges_changed)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Wires the sidebar to the game and does the initial refresh. Called by Main
## after all managers exist.
func setup(p_tribes: Array[Tribe], p_player_id: int, p_unit_manager: UnitManager,
		p_building_manager: BuildingManager, p_tree_manager: TreeManager,
		p_wood_pile_manager: WoodPileManager, p_tribe_commands: TribeCommands,
		p_build_menu: BuildMenu, p_selection: SelectionManager,
		p_camera_rig: Node3D, p_terrain_data: TerrainData,
		p_spell_targeting: SpellTargeting = null) -> void:
	_tribes = p_tribes
	_player_id = p_player_id
	_unit_manager = p_unit_manager
	_building_manager = p_building_manager
	_tree_manager = p_tree_manager
	_wood_pile_manager = p_wood_pile_manager
	_tribe_commands = p_tribe_commands
	_build_menu = p_build_menu
	_selection = p_selection
	_spell_targeting = p_spell_targeting
	_camera_rig = p_camera_rig

	_minimap.setup(p_terrain_data, p_unit_manager, p_building_manager,
		p_tree_manager, p_camera_rig, MapGenerator.round_mask(GameState.map_id))
	_refresh_tribe_bars()
	var player: Tribe = _tribes[_player_id] if _player_id < _tribes.size() else null
	if player != null:
		_set_population(player.population(), player.housing_capacity())
		_set_mana(player.mana)
		if _growth_slider != null:
			_growth_slider.set_value_no_signal(float(int(player.growth_mode)))
	_update_growth_label()
	_refresh_wood_near_base()
	_refresh_spells()
	_refresh_portrait()


func _process(delta: float) -> void:
	_refresh_crew_tab()   # responsive to selection changes (cheap: a few widgets)
	_follower_timer -= delta
	if _follower_timer <= 0.0:
		_follower_timer = FOLLOWER_INTERVAL
		_refresh_followers()
		_refresh_wood_near_base()
		_refresh_spells()
		_refresh_portrait()
		_update_growth_label()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.offset_right = PANEL_WIDTH
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	add_child(_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_panel.add_child(root)

	_build_minimap(root)
	_build_shaman_portrait(root)
	_build_tab_bar(root)
	_build_header(root)
	_build_tab_content(root)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	_build_menu_panel(root)
	_select_tab(0)


func _build_minimap(root: Control) -> void:
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	var wrap: CenterContainer = CenterContainer.new()
	wrap.add_child(_minimap)
	root.add_child(wrap)


## Populous-style shaman portrait below the minimap: the whole figure with her
## CURRENT animation (front view, tribe-coloured) over a health bar. While she
## is dead it shows the corpse pose and the respawn countdown. Clicking it
## centres the camera on her and selects ONLY her.
func _build_shaman_portrait(root: Control) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ShamanPortrait"
	panel.add_theme_stylebox_override("panel", UiTheme.inset_style())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "Schamanin: Klick zentriert die Kamera und wählt nur sie aus"
	panel.gui_input.connect(_on_portrait_gui_input)
	root.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks land on the panel
	panel.add_child(vb)

	# Stage for the animated figure (AnimatedSprite2D is a Node2D, so it lives
	# inside a plain Control and is re-centred whenever the stage resizes).
	# 72 px = exactly the sprite height (24 px x scale 3): no dead space below.
	var stage: Control = Control.new()
	stage.custom_minimum_size = Vector2(0, 72)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stage)
	_portrait_sprite = AnimatedSprite2D.new()
	_portrait_sprite.sprite_frames = PlaceholderSprites.make_frames(&"shaman")
	_portrait_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_sprite.scale = Vector2(3.0, 3.0)
	_portrait_sprite.animation = &"idle_front"
	_portrait_sprite.play()
	stage.add_child(_portrait_sprite)
	stage.resized.connect(func() -> void:
		_portrait_sprite.position = stage.size * 0.5)

	_portrait_hp = ProgressBar.new()
	_portrait_hp.show_percentage = false
	_portrait_hp.custom_minimum_size = Vector2(0, 8)
	_portrait_hp.max_value = 1.0
	_portrait_hp.value = 1.0
	_portrait_hp.add_theme_stylebox_override("background", UiTheme.inset_style())
	var hp_fill: StyleBoxFlat = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.35, 0.8, 0.3)
	hp_fill.set_corner_radius_all(2)
	_portrait_hp.add_theme_stylebox_override("fill", hp_fill)
	vb.add_child(_portrait_hp)

	# Hidden while empty (alive shaman) so it does not reserve a blank row
	# below the health bar; _refresh_portrait toggles it.
	_portrait_status = Label.new()
	_portrait_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_status.add_theme_color_override("font_color", UiTheme.TEXT)
	_portrait_status.text = ""
	_portrait_status.visible = false
	vb.add_child(_portrait_status)


func _build_tab_bar(root: Control) -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	root.add_child(bar)
	var defs: Array = [
		{"icon": &"house", "tip": "Gebäude"},
		{"icon": &"star", "tip": "Zauber"},
		{"icon": &"people", "tip": "Gefolgsleute"},
		{"icon": &"crew", "tip": "Besatzung"},
	]
	for i in range(defs.size()):
		var b: Button = Button.new()
		b.toggle_mode = true
		b.icon = UiTheme.icon(defs[i]["icon"])
		b.tooltip_text = defs[i]["tip"]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b)
		var idx: int = i
		b.pressed.connect(func() -> void: _select_tab(idx))
		bar.add_child(b)
		_tab_buttons.append(b)


func _build_header(root: Control) -> void:
	var header: PanelContainer = PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.inset_style())
	root.add_child(header)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	header.add_child(vb)

	# Per-tribe population bars.
	var bars: VBoxContainer = VBoxContainer.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_theme_constant_override("separation", 2)
	vb.add_child(bars)
	for i in range(Unit.TRIBE_COLORS.size()):
		var pb: ProgressBar = _make_tribe_bar(Unit.TRIBE_COLORS[i])
		bars.add_child(pb)
		_tribe_bars.append(pb)

	_pop_label = Label.new()
	_pop_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_pop_label.text = "Bevölkerung: 0/0"
	vb.add_child(_pop_label)

	_wood_label = Label.new()
	_wood_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_wood_label.text = "Holz: 0"
	vb.add_child(_wood_label)

	# Segmented mana bar.
	var mana_row: HBoxContainer = HBoxContainer.new()
	mana_row.add_theme_constant_override("separation", 2)
	vb.add_child(mana_row)
	for i in range(MANA_SEGMENTS):
		var seg: ColorRect = ColorRect.new()
		seg.custom_minimum_size = Vector2(0, 10)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.color = _mana_empty_color()
		mana_row.add_child(seg)
		_mana_segments.append(seg)

	# Numeric mana readout + income per second (phase 7i).
	_mana_label = Label.new()
	_mana_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_mana_label.text = "Mana: 0  (+0.0/s)"
	vb.add_child(_mana_label)

	# Growth control (phase 7i): 0 = Kein, 1 = Minimal, 2 = Maximum hut manning.
	var growth_row: HBoxContainer = HBoxContainer.new()
	growth_row.add_theme_constant_override("separation", 6)
	vb.add_child(growth_row)
	var gl: Label = Label.new()
	gl.text = "Wachstum"
	gl.add_theme_color_override("font_color", UiTheme.TEXT)
	growth_row.add_child(gl)
	_growth_slider = HSlider.new()
	_growth_slider.min_value = 0.0
	_growth_slider.max_value = 2.0
	_growth_slider.step = 1.0
	_growth_slider.custom_minimum_size = Vector2(90, 16)
	_growth_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_growth_slider.value_changed.connect(_on_growth_changed)
	growth_row.add_child(_growth_slider)
	_growth_label = Label.new()
	_growth_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_growth_label.text = "Maximum  (+0/min)"
	vb.add_child(_growth_label)


func _make_tribe_bar(color: Color) -> ProgressBar:
	var pb: ProgressBar = ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 8)
	pb.max_value = 1.0
	pb.value = 0.0
	pb.add_theme_stylebox_override("background", UiTheme.inset_style())
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


func _build_tab_content(root: Control) -> void:
	var content: Control = Control.new()
	# Tall enough for the building tab's full grid; every tab also scrolls as a
	# safety net (short windows).
	content.custom_minimum_size = Vector2(0, TAB_CONTENT_HEIGHT)
	content.size_flags_vertical = Control.SIZE_FILL
	content.clip_contents = true
	root.add_child(content)
	_tab_content = content
	_tab_panels.append(_build_building_tab())
	_tab_panels.append(_build_spell_tab())
	_tab_panels.append(_build_followers_tab())
	_tab_panels.append(_build_crew_tab())
	for p in _tab_panels:
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(p)


func _build_building_tab() -> Control:
	# Icon grid like the spell tab: two cells per row, wood cost below the icon,
	# name/hotkey in the tooltip.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in default_build_entries():
		grid.add_child(_make_build_cell(entry))
	scroll.add_child(grid)
	return scroll


func _make_build_cell(entry: Dictionary) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b: Button = Button.new()
	b.icon = UiTheme.icon(entry["icon"])
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tip: String = entry["name"]
	if entry.has("hotkey"):
		tip += "  [%s]" % entry["hotkey"]
	b.tooltip_text = tip if entry["enabled"] else "%s — ab Phase 5" % entry["name"]
	b.disabled = not entry["enabled"]
	UiTheme.style_button(b)
	if entry["enabled"]:
		var scene: PackedScene = entry["scene"]
		b.pressed.connect(func() -> void: _on_build_pressed(scene))
	cell.add_child(b)

	var cost: Label = Label.new()
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color",
		UiTheme.TEXT if entry["enabled"] else UiTheme.TEXT_DIM)
	cost.text = "%d Holz" % int(entry["wood_cost"])
	cell.add_child(cost)
	return cell


func _build_spell_tab() -> Control:
	# Scrolls like the building tab: the tab area shrinks while a building/crew
	# panel is open (see _update_tab_content_height), so all rows must stay
	# reachable at the compact height too.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in default_spell_entries():
		grid.add_child(_make_spell_cell(entry))
	scroll.add_child(grid)
	return scroll


func _make_spell_cell(entry: Dictionary) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pip_row: HBoxContainer = HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 2)
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var pips: Array[ColorRect] = []
	for i in range(int(entry["max_charges"])):
		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 5)
		pip.color = _pip_empty_color()
		pip_row.add_child(pip)
		pips.append(pip)
	cell.add_child(pip_row)

	var b: Button = Button.new()
	b.icon = UiTheme.icon(entry["icon"])
	b.tooltip_text = "%s  [%s]" % [entry["name"], entry.get("hotkey", "")]
	b.disabled = true   # enabled by set_spell_state once a charge is stored
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(b)
	var spell_id: StringName = entry["id"]
	b.pressed.connect(func() -> void: _on_spell_pressed(spell_id))
	cell.add_child(b)

	_spell_ui[entry["id"]] = {"button": b, "pips": pips}
	return cell


func _build_followers_tab() -> Control:
	# Scrolls for the same reason as the spell tab (compact tab height while a
	# building/crew panel is open).
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	for row in FOLLOWER_ROWS:
		var lbl: Label = Label.new()
		var active: bool = row["active"]
		lbl.add_theme_color_override("font_color",
			UiTheme.TEXT if active else UiTheme.TEXT_DIM)
		lbl.text = "%s: 0" % row["name"]
		vb.add_child(lbl)
		_follower_labels[row["kind"]] = lbl

	_idle_button = Button.new()
	_idle_button.text = "Untätige Braves wählen"
	_idle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_idle_button)
	_idle_button.pressed.connect(_on_select_idle)
	vb.add_child(_idle_button)

	# Per-tribe vehicle caps (independent of any selected building): every
	# production shop of the tribe reads its Tribe.max_* value. Label shows
	# "Max. <Typ>: cap (owned)" in one line — three steppers must fit the tab.
	_add_cap_stepper(vb, "Katapulte",
		"Katapult-Limit des Stammes: alle Katapultwerkstätten stoppen die"
		+ " Fertigung, sobald so viele eigene Katapulte existieren",
		Tribe.MAX_CATAPULTS_LIMIT,
		func(t: Tribe) -> int: return t.max_catapults,
		func(t: Tribe, v: int) -> void: t.max_catapults = v,
		func(t: Tribe) -> int: return t.owned_catapult_count())
	_add_cap_stepper(vb, "Feuerrammen",
		"Feuerrammen-Limit des Stammes: alle Feuerrammenwerkstätten stoppen"
		+ " die Fertigung, sobald so viele eigene Feuerrammen existieren",
		Tribe.MAX_FIRE_RAMS_LIMIT,
		func(t: Tribe) -> int: return t.max_fire_rams,
		func(t: Tribe, v: int) -> void: t.max_fire_rams = v,
		func(t: Tribe) -> int: return t.owned_fire_ram_count())
	_add_cap_stepper(vb, "Luftschiffe",
		"Luftschiff-Limit des Stammes: alle Luftschiffwerften stoppen die"
		+ " Fertigung, sobald so viele eigene Luftschiffe existieren",
		Tribe.MAX_AIRSHIPS_LIMIT,
		func(t: Tribe) -> int: return t.max_airships,
		func(t: Tribe, v: int) -> void: t.max_airships = v,
		func(t: Tribe) -> int: return t.owned_airship_count())

	scroll.add_child(vb)
	return scroll


## Builds one vehicle-cap stepper row (−  label  +) and registers it for the
## periodic refresh. The label carries cap AND owned count in one line so the
## followers tab holds three steppers without overflowing.
func _add_cap_stepper(vb: VBoxContainer, title: String, tooltip: String,
		limit: int, get_cap: Callable, set_cap: Callable, get_owned: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	var entry: Dictionary = {"title": title, "limit": limit, "get_cap": get_cap,
		"set_cap": set_cap, "get_owned": get_owned}
	var minus: Button = Button.new()
	minus.text = "−"
	UiTheme.style_button(minus)
	minus.pressed.connect(func() -> void: _on_cap_delta(entry, -1))
	row.add_child(minus)
	var label: Label = Label.new()
	label.add_theme_color_override("font_color", UiTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = tooltip
	row.add_child(label)
	var plus: Button = Button.new()
	plus.text = "+"
	UiTheme.style_button(plus)
	plus.pressed.connect(func() -> void: _on_cap_delta(entry, 1))
	row.add_child(plus)
	entry["label"] = label
	_cap_steppers.append(entry)


func _on_cap_delta(entry: Dictionary, delta: int) -> void:
	var player: Tribe = _player_tribe()
	if player == null:
		return
	var cap: int = int((entry["get_cap"] as Callable).call(player))
	(entry["set_cap"] as Callable).call(player,
		clampi(cap + delta, 0, int(entry["limit"])))
	_refresh_cap_steppers()


func _refresh_cap_steppers() -> void:
	var player: Tribe = _player_tribe()
	if player == null:
		return
	for entry in _cap_steppers:
		var label: Label = entry["label"]
		if label == null or not is_instance_valid(label):
			continue
		label.text = "Max. %s: %d (%d)" % [entry["title"],
			int((entry["get_cap"] as Callable).call(player)),
			int((entry["get_owned"] as Callable).call(player))]


# --- Crew tab (occupancy of the selected mannable object) ---------------------

## German label for a crew unit kind (shown in the slot tooltips).
static func _crew_kind_label(kind: StringName) -> String:
	match kind:
		&"brave":
			return "Gefolgsmann"
		&"warrior":
			return "Krieger"
		&"firewarrior":
			return "Feuerkrieger"
		&"preacher":
			return "Prediger"
		&"shaman":
			return "Schamanin"
	return "Einheit"


## Crew tab: title + info line, one icon button per occupant (click ejects)
## and a production pause toggle for producers.
func _build_crew_tab() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)

	_crew_title = Label.new()
	_crew_title.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(_crew_title)

	_crew_info = Label.new()
	_crew_info.add_theme_color_override("font_color", UiTheme.TEXT)
	_crew_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_crew_info)

	# Slot buttons for the largest crew (the catapult); surplus slots hide.
	var slot_row: HBoxContainer = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 4)
	vb.add_child(slot_row)
	for i in range(SiegeEngine.MAX_CREW):
		var b: Button = Button.new()
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiTheme.style_button(b)
		var idx: int = i
		b.pressed.connect(func() -> void: _on_crew_eject(idx))
		slot_row.add_child(b)
		_crew_slot_buttons.append(b)

	_crew_pause_button = Button.new()
	_crew_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_crew_pause_button)
	_crew_pause_button.pressed.connect(_on_crew_pause)
	vb.add_child(_crew_pause_button)

	# Airship only: arms the unload mode — the next right-click on terrain
	# sends the ship there and drops ALL passengers (SelectionManager).
	_crew_unload_button = Button.new()
	_crew_unload_button.text = "Absetzen an…"
	_crew_unload_button.tooltip_text = "Rechtsklick auf einen Zielpunkt:" \
		+ " das Luftschiff fliegt hin und setzt die gesamte Besatzung ab"
	_crew_unload_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_crew_unload_button)
	_crew_unload_button.pressed.connect(_on_crew_unload)
	vb.add_child(_crew_unload_button)

	scroll.add_child(vb)
	return scroll


func _on_crew_unload() -> void:
	var target: Object = _selected_crew_target()
	if target is Airship and _selection != null:
		_selection.arm_unload(target as Airship)


## The single selected mannable object (own building or own catapult), or null.
func _selected_crew_target() -> Object:
	if _selection == null:
		return null
	var b: Building = _selection.selected_building
	if is_instance_valid(b) and not b.under_construction and b.health > 0 \
			and b.tribe_id == _player_id:
		return b
	if _selection.selected.size() == 1:
		var u: Unit = _selection.selected[0]
		if is_instance_valid(u) and u is CrewedVehicle and u.state != Unit.State.DEAD \
				and u.tribe_id == _player_id:
			return u
	return null


## Normalised occupancy view of a crew target: occupants list, slot capacity
## and info line (bridges the crew/occupants field split across the classes).
func _crew_view(target: Object) -> Dictionary:
	if target is Hut:
		var hut: Hut = target as Hut
		return {"members": hut.crew, "cap": Hut.CREW_CAPACITY,
			"info": "Besatzung: %d/%d   Wachstum: +%.1f/min" % [
				hut.crew_count(), Hut.CREW_CAPACITY, hut.growth_per_minute()]}
	if target is Forester:
		var f: Forester = target as Forester
		return {"members": f.occupants, "cap": Forester.WORKER_SLOTS,
			"info": "Arbeiter: %d/%d" % [f.occupants.size(), Forester.WORKER_SLOTS]}
	# Subclasses BEFORE the Workshop branch (`is Workshop` matches them too).
	if target is FireRamWorkshop:
		var rws: FireRamWorkshop = target as FireRamWorkshop
		return {"members": rws.occupants, "cap": rws.worker_slots(),
			"info": "Arbeiter: %d/%d   Vorrat: %d/%d   Feuerrammen: %d/%d" % [
				rws.occupants.size(), rws.worker_slots(),
				rws.stock_wood(), Workshop.STOCK_TARGET,
				rws.tribe.owned_fire_ram_count() if rws.tribe != null else 0,
				rws.tribe.max_fire_rams if rws.tribe != null else 0]}
	if target is AirshipWharf:
		var aw: AirshipWharf = target as AirshipWharf
		return {"members": aw.occupants, "cap": aw.worker_slots(),
			"info": "Arbeiter: %d/%d   Vorrat: %d/%d   Luftschiffe: %d/%d" % [
				aw.occupants.size(), aw.worker_slots(),
				aw.stock_wood(), Workshop.STOCK_TARGET,
				aw.tribe.owned_airship_count() if aw.tribe != null else 0,
				aw.tribe.max_airships if aw.tribe != null else 0]}
	if target is Workshop:
		var ws: Workshop = target as Workshop
		return {"members": ws.occupants, "cap": ws.worker_slots(),
			"info": "Arbeiter: %d/%d   Vorrat: %d/%d   Katapulte: %d/%d" % [
				ws.occupants.size(), ws.worker_slots(),
				ws.stock_wood(), Workshop.STOCK_TARGET,
				ws.tribe.owned_catapult_count() if ws.tribe != null else 0,
				ws.tribe.max_catapults if ws.tribe != null else 0]}
	if target is Watchtower:
		var t: Watchtower = target as Watchtower
		return {"members": t.crew, "cap": Watchtower.CREW_CAPACITY,
			"info": "Besatzung: %d/%d" % [t.crew.size(), Watchtower.CREW_CAPACITY]}
	if target is Airship:
		var a: Airship = target as Airship
		return {"members": a.crew, "cap": a.max_crew,
			"info": "Passagiere: %d/%d  (Kampf nur im Stand, +3 Reichweite)" % [
				a.boarded_count(), a.max_crew]}
	if target is CrewedVehicle:
		var e: CrewedVehicle = target as CrewedVehicle
		return {"members": e.crew, "cap": e.max_crew,
			"info": "Besatzung: %d/%d  %s" % [
				e.boarded_count(), e.max_crew, _vehicle_crew_hint(e)]}
	if target is TrainingBuilding:
		var tb: TrainingBuilding = target as TrainingBuilding
		var queue: int = tb.incoming.size() + (1 if is_instance_valid(tb.trainee) else 0)
		return {"members": [], "cap": 0, "info": "In Ausbildung: %d" % queue}
	return {"members": [], "cap": 0, "info": ""}


## Short crew-rule hint per vehicle type for the crew tab's info line.
func _vehicle_crew_hint(e: CrewedVehicle) -> String:
	match e.unit_kind():
		&"siege":
			return "(min. 1 fahren, 2 feuern)"
		&"fireram":
			return "(min. 1 fahren & feuern)"
	return ""


## Whether the target has a production the player can pause (crew tab toggle).
func _crew_target_pausable(target: Object) -> bool:
	return target is Hut or target is TrainingBuilding \
		or target is Forester or target is Workshop


## Polled every frame: auto-activates the crew tab when a mannable object
## becomes the single selection (edge, not level — manual tab clicks while the
## selection persists are respected), returns to the previous tab when the
## selection drops, and greys the tab button out while there is no target.
func _refresh_crew_tab() -> void:
	if _crew_title == null or _tab_buttons.size() <= TAB_CREW:
		return
	var target: Object = _selected_crew_target()
	_tab_buttons[TAB_CREW].disabled = target == null
	if target != null and _crew_target_obj == null:
		_crew_return_tab = _active_tab if _active_tab != TAB_CREW else 0
		_select_tab(TAB_CREW)
	elif target == null and _crew_target_obj != null and _active_tab == TAB_CREW:
		_select_tab(_crew_return_tab)
	_crew_target_obj = target
	if target == null:
		return
	var view: Dictionary = _crew_view(target)
	_crew_title.text = target.display_name() if target.has_method("display_name") \
		else "Belagerungswaffe"
	_crew_info.text = view["info"]
	_crew_info.visible = view["info"] != ""
	var members: Array = view["members"]
	var cap: int = view["cap"]
	for i in range(_crew_slot_buttons.size()):
		var btn: Button = _crew_slot_buttons[i]
		if i >= cap:
			btn.visible = false
			continue
		btn.visible = true
		var member = members[i] if i < members.size() else null
		if member != null and is_instance_valid(member):
			btn.icon = UiTheme.icon(member.unit_kind())
			btn.disabled = false
			var label: String = _crew_kind_label(member.unit_kind())
			if target is CrewedVehicle and not member.siege_boarded:
				label += " (unterwegs)"
			btn.tooltip_text = "%s — Klick: rauswerfen" % label
		else:
			btn.icon = null
			btn.disabled = true
			btn.tooltip_text = "frei"
	_crew_pause_button.visible = _crew_target_pausable(target)
	if _crew_pause_button.visible:
		_crew_pause_button.text = "Produktion fortsetzen" if target.paused \
			else "Produktion pausieren"
	if _crew_unload_button != null:
		_crew_unload_button.visible = target is Airship \
			and (target as Airship).boarded_count() > 0


## Slot click: eject that occupant. The hut eject is MANUAL (pins the crew
## size so the growth mode does not refill it, see Hut.manual_crew_override).
func _on_crew_eject(index: int) -> void:
	var target: Object = _selected_crew_target()
	if target == null:
		return
	if target is Hut:
		(target as Hut).eject_crew(index, true)
	elif target is Forester:
		(target as Forester).eject_worker(index)
	elif target is Workshop:
		(target as Workshop).eject_worker(index)
	elif target is Watchtower:
		(target as Watchtower).eject_crew(index)
	elif target is Airship:
		# Airship eject: the passenger is DROPPED to the ground below (a plain
		# leave_crew would strand it standing mid-air).
		var ship: Airship = target as Airship
		if index >= 0 and index < ship.crew.size():
			var passenger = ship.crew[index]
			if passenger != null and is_instance_valid(passenger):
				ship.drop_member(passenger)
	elif target is CrewedVehicle:
		var engine: CrewedVehicle = target as CrewedVehicle
		if index >= 0 and index < engine.crew.size():
			var member = engine.crew[index]
			if member != null and is_instance_valid(member):
				member.leave_crew()
	_refresh_crew_tab()


func _on_crew_pause() -> void:
	var target: Object = _selected_crew_target()
	if target != null and _crew_target_pausable(target):
		target.paused = not target.paused
		_refresh_crew_tab()


func _build_menu_panel(root: Control) -> void:
	var pause: Button = Button.new()
	pause.icon = UiTheme.icon(&"pause")
	pause.text = "Menü"
	pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(pause)
	pause.pressed.connect(_toggle_pause)
	root.add_child(pause)


func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.visible = false
	add_child(_pause_menu)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	_pause_menu.add_child(dim)

	var box: PanelContainer = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel_style())
	box.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.add_child(box)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	box.add_child(vb)

	var title: Label = Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(title)

	var resume: Button = Button.new()
	resume.text = "Fortsetzen"
	UiTheme.style_button(resume)
	resume.pressed.connect(_toggle_pause)
	vb.add_child(resume)

	# Sound volume (master bus), session-scoped.
	var volume_label: Label = Label.new()
	volume_label.text = "Soundlautstärke"
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	volume_label.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	vb.add_child(volume_label)

	var volume: HSlider = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 5.0
	volume.custom_minimum_size = Vector2(180, 20)
	volume.value = AudioSettings.master_volume_percent()
	volume.value_changed.connect(AudioSettings.set_master_volume_percent)
	vb.add_child(volume)

	var battle: Button = Button.new()
	battle.text = "Debugschlacht"
	UiTheme.style_button(battle)
	battle.pressed.connect(_start_debug_battle)
	vb.add_child(battle)

	var menu: Button = Button.new()
	menu.text = "Hauptmenü"
	UiTheme.style_button(menu)
	menu.pressed.connect(_back_to_main_menu)
	vb.add_child(menu)

	var quit: Button = Button.new()
	quit.text = "Beenden"
	UiTheme.style_button(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)


## Reloads the map as the debug battle scenario (two 800-unit armies meeting
## in the middle; Main._ready consumes GameState.match_config).
func _start_debug_battle() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.match_config = MatchConfig.debug_battle()
	# No GameState.reset() here: the old scene still runs until the deferred
	# reload, and Main._ready re-populates everything anyway.
	get_tree().paused = false
	get_tree().reload_current_scene()


## Leaves the running match and returns to the full-screen main menu.
func _back_to_main_menu() -> void:
	get_tree().paused = false
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# --- Tab switching ----------------------------------------------------------

func _select_tab(index: int) -> void:
	_active_tab = index
	for i in range(_tab_panels.size()):
		_tab_panels[i].visible = i == index
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = i == index


# --- Signal handlers --------------------------------------------------------

func _on_population_changed(tribe_id: int, population: int, capacity: int) -> void:
	if tribe_id == _player_id:
		_set_population(population, capacity)
	_refresh_tribe_bars()


func _on_mana_changed(tribe_id: int, amount: float) -> void:
	if tribe_id == _player_id:
		_set_mana(amount)


func _on_stockpile_changed(_total: int) -> void:
	# The readout is "wood near own buildings", not the global total, so
	# recompute from the piles rather than using the emitted total.
	_refresh_wood_near_base()


## Sums wood in piles near the player's own buildings (delivered/base wood).
func _refresh_wood_near_base() -> void:
	if _wood_pile_manager == null or _building_manager == null:
		return
	var positions: Array[Vector3] = []
	for b: Building in _building_manager.get_buildings_of_tribe(_player_id):
		positions.append(b.center_world())
	_set_wood(_wood_pile_manager.wood_near_positions(positions, WOOD_NEAR_RADIUS))


func _set_population(population: int, capacity: int) -> void:
	if _pop_label != null:
		_pop_label.text = "Bevölkerung: %d/%d" % [population, capacity]


## Growth slider moved: apply the mode to the player's tribe (clears all manual
## hut-crew overrides — the slider is the master switch) and refresh the label.
func _on_growth_changed(value: float) -> void:
	if _player_id < _tribes.size():
		_tribes[_player_id].set_growth_mode(int(value) as Tribe.GrowthMode)
	_update_growth_label()


func _update_growth_label() -> void:
	if _growth_label == null:
		return
	var names: Array[String] = ["Kein", "Minimal", "Maximum"]
	var mode: int = 0
	if _player_id < _tribes.size():
		mode = int(_tribes[_player_id].growth_mode)
	_growth_label.text = "%s  (+%.0f/min)" % [names[clampi(mode, 0, 2)], _player_growth_per_min()]


## Total brave growth per minute across the player's manned huts (readout).
func _player_growth_per_min() -> float:
	if _building_manager == null:
		return 0.0
	var total: float = 0.0
	for b: Building in _building_manager.get_buildings_of_tribe(_player_id):
		if is_instance_valid(b) and b is Hut:
			total += (b as Hut).growth_per_minute()
	return total


func _set_wood(amount: int) -> void:
	if _wood_label != null:
		_wood_label.text = "Holz: %d" % amount


func _set_mana(amount: float) -> void:
	var filled: int = mana_segments(amount, MANA_DISPLAY_CAP, MANA_SEGMENTS)
	for i in range(_mana_segments.size()):
		_mana_segments[i].color = _mana_fill_color() if i < filled else _mana_empty_color()
	if _mana_label != null:
		var rate: float = _tribes[_player_id].mana_rate() if _player_id < _tribes.size() else 0.0
		_mana_label.text = "Mana: %d  (+%.1f/s)" % [int(amount), rate]


func _refresh_tribe_bars() -> void:
	var pops: Array[int] = []
	for i in range(_tribe_bars.size()):
		pops.append(_tribes[i].population() if i < _tribes.size() else 0)
	var fracs: Array[float] = tribe_bar_fractions(pops)
	for i in range(_tribe_bars.size()):
		_tribe_bars[i].value = fracs[i]


func _refresh_followers() -> void:
	if _unit_manager == null:
		return
	var counts: Dictionary = {}
	for row in FOLLOWER_ROWS:
		counts[row["kind"]] = 0
	for u: Unit in _unit_manager.get_units_of_tribe(_player_id):
		if u.state == Unit.State.DEAD:
			continue
		var kind: StringName = u.unit_kind()
		if counts.has(kind):
			counts[kind] += 1
	for row in FOLLOWER_ROWS:
		var kind: StringName = row["kind"]
		var lbl: Label = _follower_labels.get(kind)
		if lbl != null:
			lbl.text = "%s: %d" % [row["name"], counts[kind]]
	_refresh_cap_steppers()


# --- Spells & shaman portrait (phase 6) ----------------------------------------

func _player_tribe() -> Tribe:
	if _player_id >= 0 and _player_id < _tribes.size():
		return _tribes[_player_id]
	return null


func _player_shaman_alive() -> bool:
	var player: Tribe = _player_tribe()
	if player == null:
		return false
	var shaman: Unit = player.shaman
	return shaman != null and is_instance_valid(shaman) \
		and shaman.state != Unit.State.DEAD


func _on_spell_charges_changed(tribe_id: int) -> void:
	if tribe_id == _player_id:
		_refresh_spells()


## Feeds the charge system into the pip display: castable = stored charge +
## living shaman.
func _refresh_spells() -> void:
	var player: Tribe = _player_tribe()
	if player == null:
		return
	if player.spells.is_empty():
		for entry in default_spell_entries():
			set_spell_state(entry["id"], 0, entry["max_charges"], 0.0, false)
		return
	var alive: bool = _player_shaman_alive()
	for spell in player.spells:
		set_spell_state(spell.id, spell.charges, spell.max_charges,
			spell.charge_progress, alive and spell.charges > 0)


func _on_spell_pressed(spell_id: StringName) -> void:
	if _spell_targeting != null:
		_spell_targeting.toggle_targeting(spell_id)


func _on_portrait_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_portrait_pressed()


## Portrait click: centre the camera on the shaman and select ONLY her
## (select_units replaces the whole selection and clears any building).
func _on_portrait_pressed() -> void:
	var player: Tribe = _player_tribe()
	if player == null or not _player_shaman_alive():
		return
	var shaman: Unit = player.shaman
	if _selection != null:
		_selection.select_units([shaman] as Array[Unit])
	if _camera_rig != null:
		_camera_rig.global_position = shaman.position


## Mirrors the shaman into the portrait: her current animation (front view),
## tribe colour, health bar; corpse pose + respawn countdown while dead.
func _refresh_portrait() -> void:
	if _portrait_sprite == null:
		return
	var player: Tribe = _player_tribe()
	if player != null:
		_portrait_sprite.modulate = player.color
	if _player_shaman_alive():
		var shaman: Unit = player.shaman
		_set_portrait_anim(StringName("%s_front" % shaman.anim_base_name))
		_portrait_hp.value = float(shaman.health) / float(maxi(shaman.max_health, 1))
		_portrait_status.text = ""
		_portrait_status.visible = false
		return
	_set_portrait_anim(&"dead_front")
	_portrait_hp.value = 0.0
	var remaining: float = -1.0
	if player != null:
		for b in player.buildings:
			if is_instance_valid(b) and b is ReincarnationSite:
				remaining = (b as ReincarnationSite).respawn_remaining()
				break
	if remaining >= 0.0:
		_portrait_status.text = "Wiederkehr in %d s" % int(ceil(remaining))
	else:
		_portrait_status.text = "Keine Wiederkehr"
	_portrait_status.visible = true


func _set_portrait_anim(anim: StringName) -> void:
	var frames: SpriteFrames = _portrait_sprite.sprite_frames
	if frames == null:
		return
	if not frames.has_animation(anim):
		anim = &"idle_front"
	if _portrait_sprite.animation != anim or not _portrait_sprite.is_playing():
		_portrait_sprite.play(anim)


# --- Spell display API ---------------------------------------------------------

func set_spell_state(id: StringName, charges: int, max_charges: int,
		charge_progress: float, castable: bool) -> void:
	if not _spell_ui.has(id):
		return
	var ui: Dictionary = _spell_ui[id]
	var pips: Array = ui["pips"]
	var st: Dictionary = pip_state(charges, max_charges, charge_progress)
	var filled: int = st["filled"]
	var progress: float = st["progress"]
	for i in range(pips.size()):
		var pip: ColorRect = pips[i]
		if i < filled:
			pip.color = _pip_full_color()
		elif i == filled and progress > 0.0:
			pip.color = _pip_empty_color().lerp(_pip_full_color(), progress)
		else:
			pip.color = _pip_empty_color()
	(ui["button"] as Button).disabled = not castable


# --- Button actions ---------------------------------------------------------

func _on_build_pressed(scene: PackedScene) -> void:
	if _spell_targeting != null and _spell_targeting.is_active():
		_spell_targeting.cancel()   # only one target mode at a time
	if _build_menu != null and scene != null:
		_build_menu.start_placement(scene)


func _on_select_idle() -> void:
	if _unit_manager == null or _selection == null:
		return
	var idle: Array[Unit] = []
	for u: Unit in _unit_manager.get_units_of_tribe(_player_id):
		if is_instance_valid(u) and u is Brave and u.state == Unit.State.IDLE:
			idle.append(u)
	_selection.select_units(idle)


# --- Pause menu -------------------------------------------------------------

func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	if _pause_menu != null:
		_pause_menu.visible = paused


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# While placing a building, targeting a spell or with an armed attack-move,
	# Esc cancels that mode (handled there) instead of pausing.
	if _build_menu != null and _build_menu.is_active():
		return
	if _spell_targeting != null and _spell_targeting.is_active():
		return
	if SelectionManager.attack_arm_active:
		return
	_toggle_pause()
	get_viewport().set_input_as_handled()


# --- Colours ----------------------------------------------------------------

func _mana_fill_color() -> Color:
	return Color(0.35, 0.6, 1.0)


func _mana_empty_color() -> Color:
	return Color(0.1, 0.12, 0.18)


func _pip_full_color() -> Color:
	return UiTheme.GOLD_BRIGHT


func _pip_empty_color() -> Color:
	return Color(0.15, 0.11, 0.06)
