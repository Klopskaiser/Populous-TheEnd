class_name FlattenSpell extends Spell

## "Ebene": levels a SQUARE area around the target point onto the target
## point's exact elevation. Hard edges — no falloff, cliffs form along the
## square's rim — and FAST (morph over DURATION 0.5 s). Units on the square
## are flung around depending on the local height change: surging ground
## launches them into an arc, dropping ground lets them fall and tumble
## (fall damage scales with the drop); both end in the normal momentum roll.
## No downward clamp: a target point below the sea line floods the square.
## The terrain-integrity rules apply as with every terrain spell — buildings
## caught on the new cliff edge burst apart, flooded followers drown.

const HALF_EXTENT: float = 4.5      # square side 9 m
const DURATION: float = 0.5
## Height change (metres) below which a unit just rides the morph.
const FLING_THRESHOLD: float = 0.5
const FLING_OUT: float = 3.0        # horizontal launch away from the centre
const DROP_OUT: float = 2.0


func _init() -> void:
	id = &"flatten"
	display_name_de = "Ebene"
	charge_cost = 90.0
	max_charges = 3
	cast_range = 10.0


func execute(_tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var td: TerrainData = ctx.terrain_data
	var level: float = td.get_height(target.x, target.z)
	var plan: Dictionary = flatten_targets(td, Vector2(target.x, target.z), level)
	if (plan.indices as PackedInt32Array).is_empty():
		return false   # already flat: nothing to level, charge kept
	_fling_units(target, level, ctx)
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(ctx, plan, DURATION)
	ctx.unit_manager.register_projectile(morph)
	return true


## Square height map: every vertex inside the square goes EXACTLY to `level`
## (hard edge — vertices outside stay untouched, forming cliffs at the rim).
static func flatten_targets(td: TerrainData, center: Vector2, level: float) -> Dictionary:
	var min_vx: int = clampi(int(ceil((center.x - HALF_EXTENT) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var max_vx: int = clampi(int(floor((center.x + HALF_EXTENT) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var min_vz: int = clampi(int(ceil((center.y - HALF_EXTENT) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var max_vz: int = clampi(int(floor((center.y + HALF_EXTENT) / TerrainData.CELL_SIZE)), 0, td.verts - 1)

	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	for vz in range(min_vz, max_vz + 1):
		for vx in range(min_vx, max_vx + 1):
			var idx: int = vz * td.verts + vx
			if absf(td.heights[idx] - level) <= 0.01:
				continue
			indices.append(idx)
			targets.append(level)

	var rect: Rect2i = Rect2i()
	if not indices.is_empty():
		var cmin: Vector2i = Vector2i(clampi(min_vx - 1, 0, td.size - 1),
			clampi(min_vz - 1, 0, td.size - 1))
		var cmax: Vector2i = Vector2i(clampi(max_vx, 0, td.size - 1),
			clampi(max_vz, 0, td.size - 1))
		rect = Rect2i(cmin, cmax - cmin + Vector2i.ONE)
	return {"indices": indices, "targets": targets, "rect": rect}


## The fast morph accelerates everyone standing on the square (tribe-blind —
## it is the ground itself moving): rising ground launches, dropping ground
## drops with fall damage scaling with the depth. Airborne units keep flying.
func _fling_units(target: Vector3, level: float, ctx: SpellContext) -> void:
	var td: TerrainData = ctx.terrain_data
	for u in ctx.unit_manager.get_units_in_radius(target, HALF_EXTENT * 1.5):
		if u.state == Unit.State.DEAD or u.state == Unit.State.THROWN:
			continue
		if absf(u.position.x - target.x) > HALF_EXTENT \
				or absf(u.position.z - target.z) > HALF_EXTENT:
			continue   # circle query overshoots the square's corners
		var delta: float = level - td.get_height(u.position.x, u.position.z)
		if absf(delta) < FLING_THRESHOLD:
			continue
		var away: Vector3 = Vector3(u.position.x - target.x, 0.0, u.position.z - target.z)
		if away.length_squared() < 0.000001:
			away = Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		away = away.normalized()
		if delta > 0.0:
			# Ground surges up underneath: launched into an arc.
			u.throw_airborne(away * FLING_OUT
				+ Vector3.UP * clampf(3.0 + delta * 1.5, 3.0, 8.0))
		else:
			# Ground drops away: they fall after it and tumble on impact.
			u.throw_airborne(away * DROP_OUT + Vector3.UP * 1.5,
				int(clampf(-delta * 4.0, 0.0, 20.0)))
