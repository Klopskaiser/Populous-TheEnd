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
