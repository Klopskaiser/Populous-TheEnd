extends TestBase

## Headless tests for Unit movement logic (tick-driven, outside the scene
## tree) and the UnitManager spatial hash. Nodes are freed manually to avoid
## leaked instances.
##
## Phase 10j note: the positions below sit near the MAP CENTRE, not near the origin.
## The world is a disc inscribed in the square grid, so the old (10, 10) corner area
## is the void — a unit placed there falls out of the world and every motion
## assertion fails. These are relative-motion tests; only the origin moved.

const TICK: float = 0.05
const MAX_TICKS: int = 20000


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_unit(td: TerrainData) -> Unit:
	var unit: Unit = Unit.new()
	unit.terrain_data = td
	return unit


## Ticks until the unit is IDLE (or the tick budget runs out).
func _tick_until_idle(unit: Unit) -> int:
	var ticks: int = 0
	while unit.state != Unit.State.IDLE and ticks < MAX_TICKS:
		unit.tick(TICK)
		ticks += 1
	return ticks


func test_unit_follows_path_to_target() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(50.0, 0.0, 50.0)
	unit._sync_soa_pos()
	unit.set_path(PackedVector3Array([Vector3(55.0, 0.0, 50.0), Vector3(55.0, 0.0, 58.0)]))
	check(unit.state == Unit.State.MOVE, "unit is MOVE after set_path")
	_tick_until_idle(unit)
	check(unit.state == Unit.State.IDLE, "unit is IDLE after finishing the path")
	var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
	check(flat.distance_to(Vector2(55.0, 58.0)) <= 0.1,
		"unit reached the path end (at %s)" % str(flat))
	unit.free()


func test_y_snapping_follows_terrain() -> void:
	var td: TerrainData = _flat_terrain()
	# Give the terrain a distinct bump so Y actually changes along the way.
	td.raise_area(Vector2(60.0, 60.0), 8.0, 4.0)
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(52.0, 0.0, 60.0)
	unit._sync_soa_pos()
	unit.set_path(PackedVector3Array([Vector3(60.0, 0.0, 60.0)]))
	var snapped_ok: bool = true
	for i in range(200):
		unit.tick(TICK)
		var expected: float = td.get_height(unit.position.x, unit.position.z)
		if absf(unit.position.y - expected) > 0.0001:
			snapped_ok = false
			break
		if unit.state == Unit.State.IDLE:
			break
	check(snapped_ok, "position.y always matches TerrainData.get_height()")
	check_near(unit.position.y, td.get_height(unit.position.x, unit.position.z),
		"final Y matches terrain height")
	unit.free()


func test_carry_animation_base() -> void:
	var td: TerrainData = _flat_terrain()
	var brave: Brave = Brave.new()
	brave.terrain_data = td
	brave.state = Unit.State.GATHER
	brave._working = false
	brave.carried_wood = 0
	brave._path = PackedVector3Array()
	brave._path_index = 0
	check(brave._anim_base() == &"idle", "not carrying + standing -> idle")
	brave.carried_wood = 2
	check(brave._anim_base() == &"carry", "carrying + standing -> carry")
	brave._path = PackedVector3Array([Vector3(5.0, 0.0, 0.0)])
	brave._path_index = 0
	check(brave._anim_base() == &"carry_walk", "carrying + moving -> carry_walk")
	brave.carried_wood = 0
	check(brave._anim_base() == &"walk", "not carrying + moving -> walk")
	brave.free()


func test_group_slot_offset() -> void:
	check(TribeCommands.group_slot_offset(0) == Vector3.ZERO, "first slot at the centre")
	var within: float = TribeCommands.group_slot_offset(3).length()
	var new_group: float = TribeCommands.group_slot_offset(6).length()
	check(new_group > within, "index 6 starts a new group farther out than members 1..5")
	for i in range(1, TribeCommands.GROUP_SIZE):
		check(TribeCommands.group_slot_offset(i).length() < TribeCommands.GROUP_SPACING,
			"member %d stays tight within its group" % i)


func test_waypoint_queue_in_order() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(50.0, 0.0, 50.0)
	unit._sync_soa_pos()
	var wp1: Vector3 = Vector3(54.0, 0.0, 50.0)
	var wp2: Vector3 = Vector3(54.0, 0.0, 54.0)
	var wp3: Vector3 = Vector3(50.0, 0.0, 54.0)
	unit.order_move(wp1)
	unit.order_move(wp2, true)
	unit.order_move(wp3, true)
	check(unit.waypoint_queue.size() == 3, "queue holds 3 waypoints")

	var reach_order: Array[int] = []
	var waypoints: Array[Vector3] = [wp1, wp2, wp3]
	var ticks: int = 0
	while unit.state != Unit.State.IDLE and ticks < MAX_TICKS:
		unit.tick(TICK)
		ticks += 1
		for i in range(waypoints.size()):
			if i in reach_order:
				continue
			var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
			if flat.distance_to(Vector2(waypoints[i].x, waypoints[i].z)) <= 0.1:
				reach_order.append(i)
	check(unit.state == Unit.State.IDLE, "unit is IDLE after the route")
	check(reach_order == ([0, 1, 2] as Array[int]),
		"waypoints reached in order (got %s)" % str(reach_order))
	check(unit.waypoint_queue.is_empty(), "queue is empty after a one-shot route")
	unit.free()


func test_patrol_repeats_route() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(50.0, 0.0, 50.0)
	unit._sync_soa_pos()
	var wp1: Vector3 = Vector3(53.0, 0.0, 50.0)
	var wp2: Vector3 = Vector3(53.0, 0.0, 53.0)
	var wp3: Vector3 = Vector3(50.0, 0.0, 53.0)
	unit.patrol = true
	unit.order_move(wp1)
	unit.order_move(wp2, true)
	unit.order_move(wp3, true)

	# Enough ticks for several laps around the triangle.
	var visits_wp1: int = 0
	var near_wp1: bool = false
	for i in range(4000):
		unit.tick(TICK)
		var flat: Vector2 = Vector2(unit.position.x, unit.position.z)
		var is_near: bool = flat.distance_to(Vector2(wp1.x, wp1.z)) <= 0.1
		if is_near and not near_wp1:
			visits_wp1 += 1
		near_wp1 = is_near
	check(unit.state == Unit.State.MOVE, "patrol: unit keeps moving")
	check(unit.waypoint_queue.size() == 3, "patrol: queue length stays constant")
	check(visits_wp1 >= 2, "patrol: first waypoint visited again (%d visits)" % visits_wp1)
	unit.free()


func test_view_suffix_directions() -> void:
	# Camera looks north (-Z), its right vector points east (+X).
	var fwd: Vector3 = Vector3(0, 0, -1)
	var right: Vector3 = Vector3(1, 0, 0)
	check(Unit.view_suffix(Vector3(0, 0, -1), fwd, right) == &"back",
		"walking away from camera -> back view")
	check(Unit.view_suffix(Vector3(0, 0, 1), fwd, right) == &"front",
		"walking toward camera -> front view")
	check(Unit.view_suffix(Vector3(1, 0, 0), fwd, right) == &"right",
		"walking screen-right -> right view")
	check(Unit.view_suffix(Vector3(-1, 0, 0), fwd, right) == &"left",
		"walking screen-left -> left view")
	check(Unit.view_suffix(Vector3.ZERO, fwd, right) == &"front",
		"zero facing falls back to front view")
	# Rotated camera: looking east -> a unit walking east is seen from behind.
	check(Unit.view_suffix(Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)) == &"back",
		"rotated camera: same heading -> back view")


func test_view_index_diagonals() -> void:
	# Camera looks north (-Z), its right vector points east (+X).
	var fwd: Vector3 = Vector3(0, 0, -1)
	var right: Vector3 = Vector3(1, 0, 0)
	var s2: float = sqrt(0.5)
	# The four diagonal headings sit exactly between their two cardinals.
	check(Unit.view_suffix(Vector3(s2, 0, s2), fwd, right) == &"front_right",
		"heading front+right -> front_right view")
	check(Unit.view_suffix(Vector3(-s2, 0, s2), fwd, right) == &"front_left",
		"heading front+left -> front_left view")
	check(Unit.view_suffix(Vector3(s2, 0, -s2), fwd, right) == &"back_right",
		"heading back+right -> back_right view")
	check(Unit.view_suffix(Vector3(-s2, 0, -s2), fwd, right) == &"back_left",
		"heading back+left -> back_left view")
	# Cardinal indices are unchanged (0..3), diagonals are 4..7.
	check(Unit.view_index(Vector3(0, 0, 1), fwd, right) == 0, "front index stays 0")
	check(Unit.view_index(Vector3(0, 0, -1), fwd, right) == 1, "back index stays 1")
	check(Unit.view_index(Vector3(1, 0, 0), fwd, right) == 2, "right index stays 2")
	check(Unit.view_index(Vector3(-1, 0, 0), fwd, right) == 3, "left index stays 3")
	# The table and VIEWS both hold eight views.
	check(Unit.SECTOR_TO_VIEW.size() == 8, "sector table has 8 entries")
	check(PlaceholderSprites.VIEWS.size() == 8, "VIEWS has 8 entries")


func test_view_index_sector_boundaries() -> void:
	# 22.5-degree sector boundaries: just inside a diagonal sector picks the
	# diagonal, just past the boundary toward a cardinal picks the cardinal.
	var fwd: Vector3 = Vector3(0, 0, -1)
	var right: Vector3 = Vector3(1, 0, 0)
	# Front (screen -Z here is "away"; +Z is toward camera = front at angle pi).
	# Sweep the heading angle around and confirm every 45-deg centre resolves to
	# the expected view, and that a small nudge past 22.5 deg flips the view.
	var centres := {
		0.0: &"back", 45.0: &"back_right", 90.0: &"right", 135.0: &"front_right",
		180.0: &"front", 225.0: &"front_left", 270.0: &"left", 315.0: &"back_left"}
	for deg in centres:
		var a: float = deg_to_rad(deg)
		# angle 0 = along camera forward (away). facing = forward*cos + right*sin.
		var facing: Vector3 = fwd * cos(a) + right * sin(a)
		check(Unit.view_suffix(facing, fwd, right) == centres[deg],
			"sector centre %d deg -> %s" % [int(deg), centres[deg]])

	# Rotated camera (looking east): a diagonal heading still maps correctly.
	var fwd_e: Vector3 = Vector3(1, 0, 0)
	var right_e: Vector3 = Vector3(0, 0, 1)
	var s2: float = sqrt(0.5)
	# Heading north-east, camera looking east: to the screen this is up-left of
	# straight-away -> back_left.
	check(Unit.view_suffix(Vector3(s2, 0, -s2), fwd_e, right_e) == &"back_left",
		"rotated camera: NE heading -> back_left view")


## The lying poses are a SHARED convention (sprite factory, renderer, picking,
## sidebar portrait): painted upright in the portrait cell, rolled 90 degrees on
## screen. A typo in FLAT_ANIMS would switch the roll off silently.
func test_flat_anims_are_the_lying_poses() -> void:
	check(PlaceholderSprites.anim_lies_flat(&"dead"), "the corpse lies flat")
	check(PlaceholderSprites.anim_lies_flat(&"airborne"), "a flyer lies flat")
	check(not PlaceholderSprites.anim_lies_flat(&"roll"),
		"tumbling ALONG the ground stays screen-upright")
	check(not PlaceholderSprites.anim_lies_flat(&"drown"),
		"the drowning flail stays screen-upright")
	for anim: StringName in [&"idle", &"walk", &"sit", &"jump", &"cast"]:
		check(not PlaceholderSprites.anim_lies_flat(anim), "%s stays upright" % anim)
	var brave: Array[StringName] = PlaceholderSprites._anims_for(&"brave")
	for anim: StringName in PlaceholderSprites.FLAT_ANIMS:
		check(anim in brave, "flat animation '%s' exists on the brave" % anim)
	# BOTH flat poses are viewless: a body on the ground or tumbling through the
	# air has no front the camera could circle.
	for anim: StringName in PlaceholderSprites.FLAT_ANIMS:
		check(PlaceholderSprites.anim_is_viewless(anim), "'%s' is viewless" % anim)
	for anim: StringName in [&"idle", &"walk", &"roll", &"drown", &"attack"]:
		check(not PlaceholderSprites.anim_is_viewless(anim), "'%s' keeps its views" % anim)
	# The corpse has the two landings, the flying body only one.
	check(PlaceholderSprites.slot_count(&"dead") == 2,
		"the corpse has a back and a belly variant")
	check(PlaceholderSprites.slot_count(&"airborne") == 1,
		"a flung body always falls belly-first")
	check(PlaceholderSprites.slot_count(&"walk") == PlaceholderSprites.VIEWS.size(),
		"a normal pose still has one slot per view")
	# Sheet suffix names the POSE, paint view names the side we SEE — for the
	# corpse those are deliberately opposite. Getting this backwards would ship
	# face-up art for the belly landing.
	check(PlaceholderSprites.variant_suffix(&"dead", 0) == &"back"
		and PlaceholderSprites.slot_paint_view(&"dead", 0) == &"front",
		"dead_back.png lies on its back and is drawn face UP")
	check(PlaceholderSprites.variant_suffix(&"dead", 1) == &"front"
		and PlaceholderSprites.slot_paint_view(&"dead", 1) == &"back",
		"dead_front.png lies on its belly and shows only its back")
	check(PlaceholderSprites.variant_suffix(&"airborne", 0) == &""
		and PlaceholderSprites.slot_paint_view(&"airborne", 0) == &"back",
		"airborne is one plain file, drawn belly-down")
	check(PlaceholderSprites.variant_suffix(&"walk", 0) == &"",
		"a normal pose has no variant suffix")
	# _build_frames must not mirror a viewless drawing, so its paint views may
	# never be mirrored or diagonal ones.
	for anim: StringName in PlaceholderSprites.FLAT_ANIMS:
		for slot in range(PlaceholderSprites.slot_count(anim)):
			var pv: StringName = PlaceholderSprites.slot_paint_view(anim, slot)
			check(pv in PlaceholderSprites.VIEWS, "%s/%d paints a real view" % [anim, slot])
			check(not (pv in PlaceholderSprites.MIRRORED_VIEWS),
				"%s/%d is never mirrored" % [anim, slot])


## The roll is ONE fixed direction now: which side of the body you see is carried
## by the artwork (two corpse variants), not by the rotation.
func test_pose_roll_is_a_single_fixed_direction() -> void:
	check(absf(UnitRenderer.LIE_ROLL) == 1.0, "a flat pose rolls a full 90 degrees")
	for anim: StringName in PlaceholderSprites.FLAT_ANIMS:
		check(UnitRenderer.pose_roll(anim) == UnitRenderer.LIE_ROLL,
			"'%s' uses the one roll direction" % anim)
	for anim: StringName in [&"idle", &"walk", &"roll", &"drown", &"cast"]:
		check(UnitRenderer.pose_roll(anim) == 0.0, "'%s' is not rolled at all" % anim)


## Which atlas entry a unit reads: its VIEW for a normal pose, its VARIANT for a
## viewless one. The corpse's landing picks the variant; everything with a single
## variant stays on entry 0 whatever the bit says.
func test_pose_slot_picks_view_or_variant() -> void:
	for v in range(PlaceholderSprites.VIEWS.size()):
		check(UnitRenderer.pose_slot(&"walk", v, false) == v,
			"an upright pose reads its view (%d)" % v)
		check(UnitRenderer.pose_slot(&"walk", v, true) == v,
			"the landing bit never touches an upright pose (view %d)" % v)
		check(UnitRenderer.pose_slot(&"dead", v, false) == 0,
			"the corpse on its back reads variant 0, whatever the facing (view %d)" % v)
		check(UnitRenderer.pose_slot(&"dead", v, true) == 1,
			"the corpse on its belly reads variant 1 (view %d)" % v)
		check(UnitRenderer.pose_slot(&"airborne", v, true) == 0,
			"a single-variant pose always reads entry 0 (view %d)" % v)
	check(Balance.LIE_FACE_DOWN_CHANCE > 0.0 and Balance.LIE_FACE_DOWN_CHANCE < 1.0,
		"both corpse landings actually occur")


# --- Idle: stand frame with an occasional playback ------------------------------------

## Sampling helper: every playback the schedule produces over `span_ms`, as
## [start_ms, [frames...]]. Pure input -> pure output, no renderer, no RNG.
func _idle_playbacks(seed_value: int, interval_ms: int, count: int, fps: float,
		span_ms: int, step_ms: int) -> Array:
	var runs: Array = []
	var current: Array = []
	var start: int = -1
	for t in range(0, span_ms, step_ms):
		var f: int = UnitRenderer.idle_frame(t, seed_value, interval_ms, count, fps)
		if f < 0:
			if not current.is_empty():
				runs.append([start, current])
				current = []
			continue
		if current.is_empty():
			start = t
		current.append(f)
	if not current.is_empty():
		runs.append([start, current])
	return runs


## The whole point: a standing unit RESTS almost all of the time and plays its
## idle animation only now and then — whole, from the first frame to the last.
func test_idle_rests_between_playbacks() -> void:
	var interval: int = int(Balance.UNIT_IDLE_ANIM_INTERVAL * 1000.0)
	var count: int = 2
	var fps: float = 2.0
	var span: int = 120000
	var step: int = 50
	var resting: int = 0
	for t in range(0, span, step):
		if UnitRenderer.idle_frame(t, 4711, interval, count, fps) < 0:
			resting += 1
	var rest_share: float = float(resting) / float(span / step)
	check(rest_share > 0.8,
		"a standing unit rests %.0f %% of the time (0 %% with the old loop)"
			% (rest_share * 100.0))
	var runs: Array = _idle_playbacks(4711, interval, count, fps, span, step)
	check(runs.size() >= 12 and runs.size() <= 18,
		"roughly one playback per %.0f s (%d in 120 s)"
			% [Balance.UNIT_IDLE_ANIM_INTERVAL, runs.size()])
	for run: Array in runs:
		var frames: Array = run[1]
		check(int(frames[0]) == 0, "every playback starts at frame 0, never mid-animation")
		check(int(frames[frames.size() - 1]) == count - 1,
			"every playback reaches its last frame (no cut-off at the cycle edge)")
		var monotone: bool = true
		for i in range(1, frames.size()):
			if int(frames[i]) < int(frames[i - 1]) or int(frames[i]) >= count:
				monotone = false
		check(monotone, "frames run forward and stay inside the animation")


## The gap is jittered so a group that arrived together does not twitch in step,
## but its MEAN stays the configured interval.
func test_idle_gap_stays_within_the_jitter_band() -> void:
	var interval: int = 8000
	var runs: Array = _idle_playbacks(20260904, interval, 2, 2.0, interval * 60, 10)
	check(runs.size() > 40, "enough playbacks to judge the spread (%d)" % runs.size())
	var lo: float = float(interval) * (1.0 - Balance.UNIT_IDLE_ANIM_JITTER)
	var hi: float = float(interval) * (1.0 + Balance.UNIT_IDLE_ANIM_JITTER)
	var total: int = 0
	var in_band: bool = true
	var varies: bool = false
	for i in range(1, runs.size()):
		var gap: int = int(runs[i][0]) - int(runs[i - 1][0])
		total += gap
		if float(gap) < lo - 20.0 or float(gap) > hi + 20.0:
			in_band = false
		if absi(gap - interval) > 200:
			varies = true
	check(in_band, "every gap sits inside [%.1f s, %.1f s]" % [lo * 0.001, hi * 0.001])
	check(varies, "and the gap actually varies — not a metronome")
	check_near(float(total) / float(runs.size() - 1), float(interval),
		"the mean gap is the configured interval", 400.0)


## Units that start resting in the SAME frame must not animate in unison. Godot
## hands out consecutive instance IDs, so this is really a test of the hash.
func test_idle_schedule_desynchronises_units() -> void:
	# Both magnitudes matter: a small counter AND the ~10^11 range Godot actually
	# hands out (seen in a live run), because the two exercise different bits.
	for base: int in [300000, 78181829619]:
		var interval: int = 8000
		var buckets: Dictionary = {}
		var first: Array = []
		for i in range(200):
			var runs: Array = _idle_playbacks(base + i, interval, 2, 2.0, interval, 10)
			check(runs.size() == 1, "unit %d plays exactly once in the first cycle" % i)
			var start: int = int(runs[0][0])
			first.append(start)
			var b: int = start / 200
			buckets[b] = int(buckets.get(b, 0)) + 1
		var same_as_neighbour: int = 0
		for i in range(1, first.size()):
			if int(first[i]) == int(first[i - 1]):
				same_as_neighbour += 1
		check(same_as_neighbour < 10,
			"consecutive IDs from %d get their own start times (%d collisions of 199)"
				% [base, same_as_neighbour])
		var worst: int = 0
		for b: int in buckets:
			worst = maxi(worst, int(buckets[b]))
		check(worst < 40,
			"no 200 ms window collects a crowd (worst %d of 200, base %d)"
				% [worst, base])
		check(buckets.size() > 8,
			"the starts spread over the whole window (%d windows, base %d)"
				% [buckets.size(), base])


## The renderer evaluates a unit only every VISUAL_SLICES-th frame, so at 20 fps
## up to 150 ms pass between two samples. No playback may slip through unseen.
func test_idle_survives_a_dropped_visual_slice() -> void:
	var runs: Array = _idle_playbacks(99, 8000, 2, 2.0, 120000, 150)
	check(runs.size() >= 12, "the playbacks are still all there (%d)" % runs.size())
	for run: Array in runs:
		check((run[1] as Array).size() >= 2,
			"a 1 s playback is sampled at least twice even at 150 ms")


## The escape hatch: interval 0 is exactly the old behaviour, frame for frame.
func test_idle_interval_zero_restores_the_loop() -> void:
	var count: int = 2
	var fps: float = 2.0
	var matches: bool = true
	for t in range(0, 20000, 25):
		if UnitRenderer.idle_frame(t, 12345, 0, count, fps) \
				!= int(float(t) * 0.001 * fps) % count:
			matches = false
	check(matches, "interval 0 loops frame for frame like before")
	check(UnitRenderer.idle_frame(500, 12345, 1000, 4, 2.0) >= 0,
		"an animation longer than the interval keeps looping")
	check(UnitRenderer.idle_frame(0, 12345, 8000, 1, 2.0) == 0,
		"a single-frame animation is its own rest pose")


## The rest pose per kind: its own stand.png where delivered, otherwise frame 0
## of that kind's OWN idle — and of the SAME slot, or every resting unit would
## suddenly face the camera.
func test_rest_frame_falls_back_on_idle_frame_zero() -> void:
	var idle_rows: Array = []
	var stand_rows: Array = []
	for slot in range(PlaceholderSprites.VIEWS.size()):
		idle_rows.append([100 + slot * 2, 2, 2.0])
		stand_rows.append([900 + slot, 1, 2.0])
	var without: Dictionary = UnitRenderer.rest_frames({&"brave": {&"idle": idle_rows}})
	var with_sheet: Dictionary = UnitRenderer.rest_frames(
		{&"brave": {&"idle": idle_rows, &"stand": stand_rows}})
	for slot in range(PlaceholderSprites.VIEWS.size()):
		check(int((without[&"brave"] as PackedInt32Array)[slot]) == 100 + slot * 2,
			"with no stand.png slot %d rests on ITS OWN idle frame 0" % slot)
		check(int((with_sheet[&"brave"] as PackedInt32Array)[slot]) == 900 + slot,
			"a delivered stand.png wins for slot %d" % slot)


## The rest pose is an ordinary upright pose with eight views — if it ever ended
## up in FLAT_ANIMS or VIEWLESS_POSES, resting units would lie down.
func test_stand_is_an_upright_viewed_pose() -> void:
	check(not PlaceholderSprites.anim_lies_flat(PlaceholderSprites.STAND_ANIM),
		"the rest pose stands, it does not lie")
	check(not PlaceholderSprites.anim_is_viewless(PlaceholderSprites.STAND_ANIM),
		"the rest pose has views")
	check(UnitRenderer.pose_roll(PlaceholderSprites.STAND_ANIM) == 0.0,
		"and is therefore never rolled")
	for v in range(PlaceholderSprites.VIEWS.size()):
		check(UnitRenderer.pose_slot(PlaceholderSprites.STAND_ANIM, v, true) == v,
			"the rest pose reads its view (%d), not a landing variant" % v)
	var size_m: Vector2 = SelectionManager.sprite_pick_size(PlaceholderSprites.STAND_ANIM)
	check(size_m.y > size_m.x, "the pick rectangle stays upright for the rest pose")


func test_facing_follows_movement() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(50.0, 0.0, 50.0)
	unit._sync_soa_pos()
	unit.set_path(PackedVector3Array([Vector3(54.0, 0.0, 50.0)]))
	unit.tick(TICK)
	check(unit.facing.distance_to(Vector3(1, 0, 0)) < 0.001,
		"facing points along the movement direction (+X)")
	_tick_until_idle(unit)
	check(unit.facing.distance_to(Vector3(1, 0, 0)) < 0.001,
		"facing is kept after the unit stops")
	unit.free()


func test_remaining_path_shrinks() -> void:
	var td: TerrainData = _flat_terrain()
	var unit: Unit = _make_unit(td)
	unit.position = Vector3(50.0, 0.0, 50.0)
	unit._sync_soa_pos()
	unit.set_path(PackedVector3Array([Vector3(52.0, 0.0, 50.0), Vector3(54.0, 0.0, 50.0)]))
	check(unit.get_remaining_path().size() == 2, "remaining path starts with 2 points")
	for i in range(100):
		unit.tick(TICK)
		if unit.get_remaining_path().size() < 2:
			break
	check(unit.get_remaining_path().size() == 1,
		"first path point is dropped after passing it")
	_tick_until_idle(unit)
	check(unit.get_remaining_path().is_empty(), "remaining path is empty when IDLE")
	unit.free()


func test_spatial_hash_radius_query() -> void:
	var td: TerrainData = _flat_terrain()
	var manager: UnitManager = UnitManager.new()
	manager.setup(td, null)

	var inside_a: Unit = _make_unit(td)
	inside_a.position = Vector3(50.0, 5.0, 50.0)
	inside_a._sync_soa_pos()
	var inside_b: Unit = _make_unit(td)
	inside_b.position = Vector3(53.0, 5.0, 52.0)
	inside_b._sync_soa_pos()
	var outside_near: Unit = _make_unit(td)
	outside_near.position = Vector3(56.0, 5.0, 50.0)   # 6 m away
	outside_near._sync_soa_pos()
	var outside_far: Unit = _make_unit(td)
	outside_far.position = Vector3(90.0, 5.0, 90.0)
	outside_far._sync_soa_pos()
	for unit: Unit in [inside_a, inside_b, outside_near, outside_far]:
		manager.register(unit)
	manager.tick(TICK)

	var found: Array[Unit] = manager.get_units_in_radius(Vector3(50.0, 5.0, 50.0), 5.0)
	check(inside_a in found, "radius query finds unit at the centre")
	check(inside_b in found, "radius query finds unit inside the radius")
	check(not (outside_near in found), "radius query excludes unit just outside")
	check(not (outside_far in found), "radius query excludes far-away unit")
	check(found.size() == 2, "radius query returns exactly 2 units")

	# Moving a unit updates its hash cell on the next tick.
	inside_b.position = Vector3(90.0, 5.0, 90.0)
	inside_b._sync_soa_pos()
	manager.tick(TICK)
	found = manager.get_units_in_radius(Vector3(50.0, 5.0, 50.0), 5.0)
	check(found.size() == 1, "moved unit left the radius after hash update")

	check(manager.get_units_of_tribe(0).size() == 4, "tribe query returns all units")

	for unit: Unit in [inside_a, inside_b, outside_near, outside_far]:
		unit.free()
	manager.free()


func test_move_orders_form_groups_of_six() -> void:
	var td: TerrainData = _flat_terrain()
	var tc: TribeCommands = TribeCommands.new()
	var units: Array[Unit] = []
	for i in range(12):
		var unit: Unit = _make_unit(td)
		unit.position = Vector3(30.0 + float(i), 5.0, 30.0)
		unit._sync_soa_pos()
		units.append(unit)

	var target: Vector3 = Vector3(80.0, 5.0, 80.0)
	tc.order_move(units, target)

	# Collect the assigned member targets (waypoint_queue[0] per unit).
	var targets: Array[Vector3] = []
	for unit in units:
		check(unit.waypoint_queue.size() == 1, "every unit got exactly one waypoint")
		targets.append(unit.waypoint_queue[0])
	# Group 1 packs tightly around the raw target...
	var near_target: int = 0
	var far_targets: Array[Vector3] = []
	for t in targets:
		if Vector2(t.x, t.z).distance_to(Vector2(target.x, target.z)) <= 1.2:
			near_target += 1
		else:
			far_targets.append(t)
	check(near_target == 6, "first group of 6 packs around the target (got %d)" % near_target)
	check(far_targets.size() == 6, "second group of 6 stands apart")
	# ...and group 2 packs tightly around its own centre, clearly away.
	var center: Vector3 = Vector3.ZERO
	for t in far_targets:
		center += t
	center /= float(far_targets.size())
	check(Vector2(center.x, center.z).distance_to(Vector2(target.x, target.z)) >= 1.5,
		"group centres keep visible spacing")
	var second_tight: bool = true
	for t in far_targets:
		if Vector2(t.x, t.z).distance_to(Vector2(center.x, center.z)) > 1.2:
			second_tight = false
	check(second_tight, "second group packs tightly around its centre")

	for unit in units:
		unit.free()
	tc.free()


func test_path_queue_spreads_path_requests() -> void:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var manager: UnitManager = UnitManager.new()
	manager.setup(td, nav)
	var count: int = UnitManager.PATHS_PER_TICK + 12
	var units: Array[Unit] = []
	for i in range(count):
		var unit: Unit = _make_unit(td)
		unit.nav_grid = nav
		unit.path_service = manager
		unit.position = Vector3(30.0 + float(i % 10) * 1.5, 5.0, 30.0 + float(i / 10) * 1.5)
		unit._sync_soa_pos()
		manager.register(unit)
		units.append(unit)

	for unit in units:
		unit.order_move(Vector3(90.0, 5.0, 90.0))
	var pending: int = 0
	for unit in units:
		if unit.state == Unit.State.MOVE and unit.get_remaining_path().is_empty():
			pending += 1
	check(pending == count, "all move orders wait for the path queue first")

	# One tick resolves a bounded batch (at most PATHS_PER_TICK) — never
	# everything at once.
	manager.tick(TICK)
	var resolved: int = 0
	for unit in units:
		if not unit.get_remaining_path().is_empty():
			resolved += 1
	check(resolved > 0 and resolved <= UnitManager.PATHS_PER_TICK,
		"one tick resolves a bounded batch (got %d of %d)" % [resolved, count])
	check(resolved < count, "the first tick never resolves everything")

	# A few more ticks drain the whole queue.
	for i in range(16):
		manager.tick(TICK)
	resolved = 0
	for unit in units:
		if not unit.get_remaining_path().is_empty():
			resolved += 1
	check(resolved == count, "later ticks resolve the rest")

	var before: Vector3 = units[0].position
	units[0].tick(TICK)
	check(units[0].position != before, "resolved units actually walk")

	for unit in units:
		unit.free()
	manager.free()


func test_separation_pushes_overlapping_units_apart() -> void:
	var td: TerrainData = _flat_terrain()
	var manager: UnitManager = UnitManager.new()
	manager.setup(td, null)
	var a: Unit = _make_unit(td)
	var b: Unit = _make_unit(td)
	a.position = Vector3(50.0, 5.0, 50.0)
	a._sync_soa_pos()
	b.position = Vector3(50.0, 5.0, 50.0)   # full overlap
	b._sync_soa_pos()
	manager.register(a)
	manager.register(b)

	for i in range(100):
		manager.tick(TICK)
	var dist: float = Vector2(a.position.x, a.position.z).distance_to(
		Vector2(b.position.x, b.position.z))
	check(dist >= 0.3, "overlapping units are pushed apart (dist %f)" % dist)
	check(dist <= 2.0, "separation does not fling units away")
	check_near(a.position.y, td.get_height(a.position.x, a.position.z),
		"pushed unit stays snapped to the terrain")

	a.free()
	b.free()
	manager.free()
