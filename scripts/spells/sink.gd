class_name SinkSpell extends Spell

## "Absinken": the landbridge's counterpart — lowers the terrain around the
## target point by up to DEPTH metres with a SOFT smoothstep falloff to the
## rim (much gentler edges than the flatten spell), gradually over DURATION.
## On land it shaves hills and mountains; near the coast the ground sinks
## below the sea line and floods — the terrain-integrity rules then apply:
## followers on flooded ground drown instantly, mostly-flooded buildings
## slide into the water, and foundations torn past the break threshold burst
## (as with every terrain-morphing spell). Never digs below the existing sea
## floor (FLOOR_LEVEL clamp).

const RADIUS: float = 6.0
const DEPTH: float = 3.0
const DURATION: float = 1.5
## Sea-floor level the sink never digs below.
const FLOOR_LEVEL: float = 0.5


func _init() -> void:
	id = &"sink"
	display_name_de = "Absinken"
	charge_cost = 60.0
	max_charges = 3
	cast_range = 10.0


func execute(_tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var plan: Dictionary = sink_targets(ctx.terrain_data, Vector2(target.x, target.z))
	if (plan.indices as PackedInt32Array).is_empty():
		return false   # nothing above the sea floor: charge kept
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(ctx, plan, DURATION)
	ctx.unit_manager.register_projectile(morph)
	return true


## Lowering height map: full DEPTH at the centre, smoothstep falloff to zero
## at the rim, clamped so nothing dips below the sea floor.
static func sink_targets(td: TerrainData, center: Vector2) -> Dictionary:
	var min_vx: int = clampi(int(floor((center.x - RADIUS) / TerrainData.CELL_SIZE)), 0, TerrainData.VERTS - 1)
	var max_vx: int = clampi(int(ceil((center.x + RADIUS) / TerrainData.CELL_SIZE)), 0, TerrainData.VERTS - 1)
	var min_vz: int = clampi(int(floor((center.y - RADIUS) / TerrainData.CELL_SIZE)), 0, TerrainData.VERTS - 1)
	var max_vz: int = clampi(int(ceil((center.y + RADIUS) / TerrainData.CELL_SIZE)), 0, TerrainData.VERTS - 1)

	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	var changed_min: Vector2i = Vector2i(TerrainData.VERTS, TerrainData.VERTS)
	var changed_max: Vector2i = Vector2i(-1, -1)
	for vz in range(min_vz, max_vz + 1):
		for vx in range(min_vx, max_vx + 1):
			var p: Vector2 = Vector2(float(vx), float(vz)) * TerrainData.CELL_SIZE
			var dist: float = p.distance_to(center)
			if dist > RADIUS:
				continue
			var t: float = clampf((RADIUS - dist) / RADIUS, 0.0, 1.0)
			var falloff: float = t * t * (3.0 - 2.0 * t)
			var idx: int = vz * TerrainData.VERTS + vx
			var current: float = td.heights[idx]
			var nh: float = maxf(current - DEPTH * falloff, FLOOR_LEVEL)
			if current - nh <= 0.01:
				continue   # already at/below the sea floor
			indices.append(idx)
			targets.append(nh)
			changed_min = Vector2i(mini(changed_min.x, vx), mini(changed_min.y, vz))
			changed_max = Vector2i(maxi(changed_max.x, vx), maxi(changed_max.y, vz))

	var rect: Rect2i = Rect2i()
	if changed_max.x >= 0:
		var cmin: Vector2i = (changed_min - Vector2i.ONE).clamp(Vector2i.ZERO,
			Vector2i(TerrainData.SIZE - 1, TerrainData.SIZE - 1))
		var cmax: Vector2i = changed_max.clamp(Vector2i.ZERO,
			Vector2i(TerrainData.SIZE - 1, TerrainData.SIZE - 1))
		rect = Rect2i(cmin, cmax - cmin + Vector2i.ONE)
	return {"indices": indices, "targets": targets, "rect": rect}
