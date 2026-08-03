extends TestBase

## Headless tests for the sidebar/minimap UI *logic* — only the pure static
## functions (no viewport, no texture contents, per the headless rule).

const WORLD: float = float(TerrainData.SIZE)   # 128 m
const MAP: float = 200.0


# --- Minimap coordinate mapping ---------------------------------------------

func test_world_to_map_centre_and_corners() -> void:
	var mid: Vector2 = Minimap.world_to_map(Vector2(WORLD * 0.5, WORLD * 0.5), MAP, WORLD)
	check_near(mid.x, MAP * 0.5, "world centre -> map centre x")
	check_near(mid.y, MAP * 0.5, "world centre -> map centre y")
	var origin: Vector2 = Minimap.world_to_map(Vector2.ZERO, MAP, WORLD)
	check_near(origin.x, 0.0, "world origin -> map 0 x")
	check_near(origin.y, 0.0, "world origin -> map 0 y")
	var far: Vector2 = Minimap.world_to_map(Vector2(WORLD, WORLD), MAP, WORLD)
	check_near(far.x, MAP, "world max -> map edge x")
	check_near(far.y, MAP, "world max -> map edge y")


func test_world_to_map_clamps_outside() -> void:
	var over: Vector2 = Minimap.world_to_map(Vector2(WORLD * 2.0, -50.0), MAP, WORLD)
	check_near(over.x, MAP, "beyond world clamps to map edge")
	check_near(over.y, 0.0, "negative world clamps to map 0")


func test_map_world_roundtrip() -> void:
	var world: Vector2 = Vector2(40.0, 90.0)
	var m: Vector2 = Minimap.world_to_map(world, MAP, WORLD)
	var back: Vector2 = Minimap.map_to_world(m, MAP, WORLD)
	check_near(back.x, world.x, "roundtrip world x")
	check_near(back.y, world.y, "roundtrip world z")


func test_mapping_zero_size_safe() -> void:
	check(Minimap.world_to_map(Vector2(10, 10), MAP, 0.0) == Vector2.ZERO,
		"world_size 0 -> zero (no div by zero)")
	check(Minimap.map_to_world(Vector2(10, 10), 0.0, WORLD) == Vector2.ZERO,
		"map_size 0 -> zero (no div by zero)")


# --- Minimap height colour ---------------------------------------------------

func test_height_color_water_is_dark() -> void:
	var water: Color = Minimap.height_to_color(TerrainData.SEA_LEVEL - 1.0)
	var sand: Color = Minimap.height_to_color(TerrainData.SEA_LEVEL + 0.5)
	check(water.v < sand.v, "water below sea level is darker than sand")
	check(water.b > water.r, "water is bluish")


func test_height_color_steps_match_terrain_thresholds() -> void:
	# Just above the sea line is sand; the grass/rock ramp climbs from there.
	var sand: Color = Minimap.height_to_color(TerrainData.SEA_LEVEL + 0.5)
	check(sand.is_equal_approx(Minimap.COLOR_SAND), "just above sea = sand colour")
	var high: Color = Minimap.height_to_color(Minimap.ROCK_BOTTOM + 6.0)
	check(high.is_equal_approx(Minimap.COLOR_ROCK), "very high = rock colour")
	var grass: Color = Minimap.height_to_color(Minimap.ROCK_BOTTOM - 0.01)
	check(grass.g > grass.r and grass.g > grass.b, "mid heights are greenish")


# --- Mana bar segmentation ---------------------------------------------------

func test_mana_segments_basic() -> void:
	check(Sidebar.mana_segments(0.0, 1000.0, 20) == 0, "0 mana -> 0 segments")
	check(Sidebar.mana_segments(500.0, 1000.0, 20) == 10, "half cap -> half segments")
	check(Sidebar.mana_segments(1000.0, 1000.0, 20) == 20, "full cap -> all segments")


func test_mana_segments_caps_and_guards() -> void:
	check(Sidebar.mana_segments(5000.0, 1000.0, 20) == 20, "over cap clamps to max")
	check(Sidebar.mana_segments(100.0, 0.0, 20) == 0, "cap 0 -> 0 (no div by zero)")
	check(Sidebar.mana_segments(100.0, 1000.0, 0) == 0, "segments 0 -> 0")


# --- Charge pips -------------------------------------------------------------

func test_pip_state_partial() -> void:
	var st: Dictionary = Sidebar.pip_state(2, 5, 0.5)
	check(st["filled"] == 2, "2 of 5 filled")
	check(st["empty"] == 3, "3 of 5 empty")
	check_near(st["progress"], 0.5, "partial progress passes through")


func test_pip_state_full_has_no_progress() -> void:
	var st: Dictionary = Sidebar.pip_state(5, 5, 0.7)
	check(st["filled"] == 5, "all filled")
	check(st["empty"] == 0, "none empty")
	check_near(st["progress"], 0.0, "full -> no charging progress")


func test_pip_state_zero_and_clamp() -> void:
	var zero: Dictionary = Sidebar.pip_state(0, 3, 0.0)
	check(zero["filled"] == 0 and zero["empty"] == 3, "0 charges -> all empty")
	var over: Dictionary = Sidebar.pip_state(9, 3, 0.9)
	check(over["filled"] == 3 and over["empty"] == 0, "charges above max clamp")
	check_near(over["progress"], 0.0, "clamped-full has no progress")


# --- Tribe bars --------------------------------------------------------------

func test_tribe_bar_fractions_proportional() -> void:
	var f: Array[float] = Sidebar.tribe_bar_fractions([50, 100, 25, 0])
	check_near(f[0], 0.5, "50/100 -> 0.5")
	check_near(f[1], 1.0, "top tribe -> full bar")
	check_near(f[2], 0.25, "25/100 -> 0.25")
	check_near(f[3], 0.0, "empty tribe -> 0")


func test_tribe_bar_fractions_all_zero_safe() -> void:
	var f: Array[float] = Sidebar.tribe_bar_fractions([0, 0, 0])
	check(f.size() == 3, "one fraction per tribe")
	for v in f:
		check_near(v, 0.0, "all-zero populations -> 0 (no div by zero)")


# --- Build registration ------------------------------------------------------

func test_build_entries_hut_active() -> void:
	var entries: Array[Dictionary] = Sidebar.default_build_entries()
	var hut: Dictionary = {}
	for e in entries:
		if e["id"] == &"hut":
			hut = e
	check(not hut.is_empty(), "hut entry exists")
	check(hut["enabled"], "hut is enabled")
	check(hut["scene"] == Sidebar.HUT_SCENE, "hut references the Hut scene")
	check(int(hut["wood_cost"]) == Hut.WOOD_COST, "hut cost matches Hut.WOOD_COST")


func test_build_entries_training_buildings_active() -> void:
	var entries: Array[Dictionary] = Sidebar.default_build_entries()
	var by_id: Dictionary = {}
	for e in entries:
		by_id[e["id"]] = e
	var expected: Dictionary = {
		&"warrior_camp": [Sidebar.WARRIOR_CAMP_SCENE, WarriorCamp.WOOD_COST],
		&"firewarrior_camp": [Sidebar.FIREWARRIOR_CAMP_SCENE, FirewarriorCamp.WOOD_COST],
		&"temple": [Sidebar.TEMPLE_SCENE, Temple.WOOD_COST],
	}
	for id: StringName in expected:
		var e: Dictionary = by_id.get(id, {})
		check(not e.is_empty(), "%s entry exists" % [id])
		check(e["enabled"], "%s is enabled" % [id])
		check(e["scene"] == expected[id][0], "%s references its scene" % [id])
		check(int(e["wood_cost"]) == int(expected[id][1]), "%s cost matches" % [id])


func test_spell_entries_count() -> void:
	var entries: Array[Dictionary] = Sidebar.default_spell_entries()
	check(entries.size() == 11, "eleven spells registered (phase 6 + 7c + supertornado)")
	# Entry order and max_charges must match the tribes' spell set — the UI
	# builds its pips from these values.
	var by_id: Dictionary = {}
	for e in entries:
		by_id[e["id"]] = e
	for spell in Spell.create_default_set():
		check(by_id.has(spell.id), "entry exists for %s" % spell.id)
		check(int(by_id[spell.id]["max_charges"]) == spell.max_charges,
			"%s entry pips match max_charges" % spell.id)
	# Hotkey order matches the targeting hotkey list (keys 1-9, 0).
	for i in range(entries.size()):
		check(SpellTargeting.HOTKEY_SPELLS[i] == entries[i]["id"],
			"hotkey slot %d wired to %s" % [i + 1, entries[i]["id"]])


## Regression: a selected unit may be freed while still referenced in the
## selection (e.g. a brave that graduated from a training building via
## queue_free). Selecting/pruning must not crash on the freed reference.
func test_selection_tolerates_freed_unit() -> void:
	var sm: SelectionManager = SelectionManager.new()
	var live: Unit = Unit.new()
	var gone: Unit = Unit.new()
	sm.selected = [live, gone] as Array[Unit]
	gone.free()
	sm._set_selection([] as Array[Unit])
	check(sm.selected.size() == 0, "_set_selection clears without crashing on a freed unit")

	var live2: Unit = Unit.new()
	var gone2: Unit = Unit.new()
	sm.selected = [live2, gone2] as Array[Unit]
	gone2.free()
	sm._prune_selection()
	check(sm.selected.size() == 1 and sm.selected[0] == live2, "_prune drops the freed unit")

	sm.free()
	live.free()
	live2.free()


# --- Selection ring basis (oval must rotate with the platform) ----------------

## The airship's oval selection ring must keep its LONG axis along `facing` at
## any heading. Basis.scaled() (world-axis scaling) pinned the ellipse to the
## world axes so it never turned with the deck; ring_basis uses scaled_local.
func test_selection_ring_oval_follows_facing() -> void:
	var ext: Vector2 = Vector2(3.3, 6.0)
	# Diagonal facing: a world-axis-scaled ellipse (the bug) would misalign here.
	var facing: Vector3 = Vector3(1, 0, 1).normalized()
	var b: Basis = SelectionRingRenderer.ring_basis(facing, true, ext)
	var long_axis: Vector3 = b * Vector3(0, 0, 1)   # local +Z = oval long axis
	check(absf(long_axis.length() - 6.0) < 0.01, "long axis carries the long extent (~6 m)")
	check(long_axis.normalized().dot(facing) > 0.999, "the oval long axis follows facing")
	var short_axis: Vector3 = b * Vector3(1, 0, 0)  # local +X = oval short axis
	check(absf(short_axis.length() - 3.3) < 0.01, "short axis carries the short extent (~3.3 m)")
	check(absf(short_axis.normalized().dot(facing)) < 0.001, "short axis is perpendicular to facing")


## A circle (equal extents, not oriented) is unaffected by facing.
func test_selection_ring_circle_is_uniform() -> void:
	var b: Basis = SelectionRingRenderer.ring_basis(
		Vector3(1, 0, 1).normalized(), false, Vector2(4.5, 4.5))
	check(absf((b * Vector3(0, 0, 1)).length() - 4.5) < 0.01, "circle keeps its radius on Z")
	check(absf((b * Vector3(1, 0, 0)).length() - 4.5) < 0.01, "circle keeps its radius on X")


# --- Phase 10c: spell cell wiring (right-click toggle) ------------------------

## Regression guard for a bug the user hit: the toggle handler sits on the CELL,
## but a child Control with MOUSE_FILTER_STOP ends Godot's gui_input bubbling
## even for events it does not handle. Button and decorations therefore MUST NOT
## be STOP, or the right-click never reaches the handler and nothing happens.
## Widget construction only — no viewport, no texture contents.
func test_spell_cell_lets_the_right_click_through_to_the_cell() -> void:
	var sidebar: Sidebar = Sidebar.new()
	var entries: Array = Sidebar.default_spell_entries()
	check(not entries.is_empty(), "there are spell entries to build from")
	var cell: Control = sidebar._make_spell_cell(entries[0])
	check(cell != null, "the cell was built")
	check(cell.mouse_filter == Control.MOUSE_FILTER_STOP,
		"the cell itself receives gui_input")
	check(cell.gui_input.get_connections().size() == 1,
		"exactly one toggle handler on the cell")
	var blockers: Array[String] = []
	_collect_input_blockers(cell, cell, blockers)
	check(blockers.is_empty(),
		"no child swallows the right-click: %s" % ", ".join(blockers))
	cell.free()   # built detached, so the sidebar does not own it
	sidebar.free()


## Every Control BELOW the cell must be PASS or IGNORE — STOP would end the
## bubbling before the cell's handler runs.
func _collect_input_blockers(node: Node, cell: Control,
		out: Array[String]) -> void:
	for child in node.get_children():
		if child is Control and child != cell \
				and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			out.append(child.get_class())
		_collect_input_blockers(child, cell, out)


# --- Status overlays never cast shadows ---------------------------------------

## Project rule (user spec): a unit's STATE display is a UI glyph floating over
## its head — it must never reach the Sun's shadow map. The circling crit-damage
## stars were still on Godot's default SHADOW_CASTING_ON and did cast shadows in
## a mass battle (user report); every status renderer is checked here so the next
## one cannot slip through the same way.
func test_status_overlays_never_cast_shadows() -> void:
	var stars: StarsRenderer = StarsRenderer.new()
	stars._ready()
	check(stars.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the crit-damage stars cast no shadow")
	stars.free()

	var fx: StatusFxRenderer = StatusFxRenderer.new()
	fx._ready()
	var checked: int = 0
	for child in fx.get_children():
		if child is GeometryInstance3D:
			checked += 1
			check((child as GeometryInstance3D).cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s casts no shadow" % child.name)
	check(checked >= 3, "panic, burning and injured overlays were all checked")
	fx.free()


# --- Selection state (phase 10d) ---------------------------------------------
# Pure state, no viewport: the SelectionManager is built outside the tree and
# only its state functions are exercised.

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")


func _make_selection() -> SelectionManager:
	var sel: SelectionManager = SelectionManager.new()
	sel.player_tribe_id = 0
	sel._ready()
	return sel


## Bug (user report): arming the attack-move with F and then LEFT-clicking left
## the red "Angriff" cursor on screen until the next right-click or Esc.
func test_cancel_armed_modes_clears_attack() -> void:
	var sel: SelectionManager = _make_selection()
	SelectionManager.attack_arm_active = true
	SelectionManager.unload_arm_active = true
	sel.cancel_armed_modes()
	check(not SelectionManager.attack_arm_active, "the armed attack-move is cleared")
	check(not SelectionManager.unload_arm_active, "the armed airship unload is cleared")
	sel.free()


func test_left_click_cancels_armed_attack() -> void:
	var sel: SelectionManager = _make_selection()
	SelectionManager.attack_arm_active = true
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(400.0, 300.0)
	sel._unhandled_input(press)
	check(not SelectionManager.attack_arm_active,
		"a left-click press drops the armed attack-move right away")
	SelectionManager.drag_active = false   # do not leak the drag flag
	sel.free()


## Bug (user report): a unit converted away by an enemy preacher kept counting
## in the cursor's selection number. The bus signal drops it immediately.
func test_converted_unit_leaves_selection() -> void:
	var sel: SelectionManager = _make_selection()
	var mine: Unit = BRAVE_SCENE.instantiate() as Unit
	mine.tribe_id = 0
	var lost: Unit = BRAVE_SCENE.instantiate() as Unit
	lost.tribe_id = 0
	sel.selected = [mine, lost] as Array[Unit]

	lost.tribe_id = 1                 # the conversion switched its tribe
	sel._on_unit_converted(lost)
	check(sel.selected.size() == 1, "the converted unit left the selection")
	check(sel.selected[0] == mine, "the own unit stayed selected")
	# An own unit reported by mistake must not be dropped.
	sel._on_unit_converted(mine)
	check(sel.selected.size() == 1, "an own unit is never dropped")
	mine.free()
	lost.free()
	sel.free()


func test_selected_braves_filters_dead_and_foreign() -> void:
	var sel: SelectionManager = _make_selection()
	var good: Unit = BRAVE_SCENE.instantiate() as Unit
	good.tribe_id = 0
	var dead: Unit = BRAVE_SCENE.instantiate() as Unit
	dead.tribe_id = 0
	dead.state = Unit.State.DEAD
	var foreign: Unit = BRAVE_SCENE.instantiate() as Unit
	foreign.tribe_id = 1
	var warrior: Unit = WARRIOR_SCENE.instantiate() as Unit
	warrior.tribe_id = 0
	sel.selected = [good, dead, foreign, warrior] as Array[Unit]

	var braves: Array[Unit] = sel.selected_braves()
	check(braves.size() == 1, "only the living own brave is returned")
	check(braves[0] == good, "and it is the right one")
	good.free()
	dead.free()
	foreign.free()
	warrior.free()
	sel.free()


# --- Controls menu completeness -----------------------------------------------

## Guard (10d follow-up): the "Steuerung" page is generated from
## InputSettings.ACTIONS, so a new key action that nobody adds there is invisible
## AND unrebindable — that is exactly how `demolish_building` slipped through.
## Rule: every KEY action in the InputMap must be listed, except Godot's own
## ui_* actions and the debug tools. Mouse-only actions have no key event and are
## skipped automatically (they are deliberately not rebindable).
func test_every_key_action_is_in_the_controls_menu() -> void:
	var listed: Dictionary = {}
	for entry in InputSettings.ACTIONS:
		listed[entry[0]] = true

	var missing: Array[String] = []
	for action in InputMap.get_actions():
		var name: String = String(action)
		if name.begins_with("ui_"):
			continue                      # Godot built-ins (Esc & co.)
		if action in InputSettings._BLOCKED_ACTIONS:
			continue                      # debug tools, on purpose
		var has_key: bool = false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
				break
		if not has_key:
			continue                      # mouse-only action, not rebindable
		if not listed.has(action):
			missing.append(name)
	check(missing.is_empty(),
		"every key action appears in the controls menu (fehlen: %s)" % str(missing))


## Every listed action must actually exist and carry a label + category, so the
## menu can never render an empty row or rebind into the void.
func test_controls_menu_has_no_dead_entries() -> void:
	var dead: Array[String] = []
	var unlabelled: Array[String] = []
	for entry in InputSettings.ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			dead.append(String(action))
		if String(entry[1]).is_empty() or String(entry[2]).is_empty():
			unlabelled.append(String(action))
	check(dead.is_empty(), "no listed action is missing from the InputMap (%s)" % str(dead))
	check(unlabelled.is_empty(), "every listed action has label + category (%s)" % str(unlabelled))


# --- Harvest rectangle (key B, phase 10e) ---------------------------------------

func _key_event(physical: int, shift: bool = false) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = physical as Key
	ev.shift_pressed = shift
	ev.pressed = true
	return ev


## Arming needs BRAVES — a pure warrior selection cannot fell trees, so the key
## must do nothing rather than leave a green cursor that fires an empty order.
func test_harvest_arm_requires_selected_braves() -> void:
	var sel: SelectionManager = _make_selection()
	SelectionManager.harvest_arm_active = false
	sel._unhandled_input(_key_event(KEY_B))
	check(not SelectionManager.harvest_arm_active,
		"with an empty selection B does not arm the rectangle")

	var warrior: Unit = WARRIOR_SCENE.instantiate() as Unit
	warrior.tribe_id = 0
	sel.selected = [warrior] as Array[Unit]
	sel._unhandled_input(_key_event(KEY_B))
	check(not SelectionManager.harvest_arm_active,
		"a warrior-only selection does not arm the rectangle either")

	var brave: Unit = BRAVE_SCENE.instantiate() as Unit
	brave.tribe_id = 0
	sel.selected = [brave] as Array[Unit]
	sel._unhandled_input(_key_event(KEY_B))
	check(SelectionManager.harvest_arm_active, "with a brave selected B arms it")

	SelectionManager.harvest_arm_active = false   # do not leak the static flag
	warrior.free()
	brave.free()
	sel.free()


## The armed modes are mutually exclusive: two cursor markers at once (and two
## meanings for the next click) would be ambiguous.
func test_harvest_arm_and_attack_arm_are_exclusive() -> void:
	var sel: SelectionManager = _make_selection()
	var brave: Unit = BRAVE_SCENE.instantiate() as Unit
	brave.tribe_id = 0
	sel.selected = [brave] as Array[Unit]

	SelectionManager.attack_arm_active = true
	sel._unhandled_input(_key_event(KEY_B))
	check(SelectionManager.harvest_arm_active, "B arms the rectangle")
	check(not SelectionManager.attack_arm_active, "and drops the armed attack-move")

	sel._unhandled_input(_key_event(KEY_F))
	check(SelectionManager.attack_arm_active, "F arms the attack-move")
	check(not SelectionManager.harvest_arm_active, "and drops the harvest rectangle")

	SelectionManager.attack_arm_active = false
	SelectionManager.harvest_arm_active = false
	brave.free()
	sel.free()


## Godot compares key modifiers ONLY with exact_match = true, so plain B and
## Shift+B would otherwise both trigger both actions and the elif order would
## silently decide. Pins the project.godot bindings as well.
func test_shift_b_and_b_are_distinct_actions() -> void:
	var plain: InputEventKey = _key_event(KEY_B)
	check(plain.is_action_pressed(&"harvest_area_arm", false, true),
		"plain B is the harvest rectangle")
	check(not plain.is_action_pressed(&"select_all_huts", false, true),
		"plain B is NOT 'select all huts'")
	var shifted: InputEventKey = _key_event(KEY_B, true)
	check(shifted.is_action_pressed(&"select_all_huts", false, true),
		"Shift+B selects all huts")
	check(not shifted.is_action_pressed(&"harvest_area_arm", false, true),
		"Shift+B is NOT the harvest rectangle")


## The rebind path must keep the Shift modifier: without it "Zurücksetzen" turned
## Shift+B into a plain B and collided with harvest_area_arm for good.
func test_reset_keeps_the_shift_modifier_on_select_all_huts() -> void:
	InputSettings.reset_all()
	var shift_kept: bool = false
	for event in InputMap.action_get_events(&"select_all_huts"):
		if event is InputEventKey and (event as InputEventKey).shift_pressed:
			shift_kept = true
	check(shift_kept, "after a reset select_all_huts still carries Shift")
	var plain: InputEventKey = _key_event(KEY_B)
	check(not plain.is_action_pressed(&"select_all_huts", false, true),
		"so plain B still does not select all huts")


## Shift+X and plain X live in separate binding spaces — the controls menu must
## not report a phantom conflict between them.
func test_shift_binding_is_no_conflict_with_the_plain_key() -> void:
	var conflict: StringName = InputSettings.action_using_keycode(
		KEY_B, &"harvest_area_arm")
	check(conflict != &"select_all_huts",
		"Shift+B does not count as a conflict for the plain-B action")
