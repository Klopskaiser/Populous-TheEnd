class_name VolcanoSpell extends Spell

## "Vulkan": raises a PERMANENT mountain cone (+PEAK metres at the tip,
## smoothstep profile — the mid slope is intentionally too steep to walk)
## gradually over DURATION, then a VolcanoZone burns everything around it for
## its lifetime (lava knows no friends: OWN units burn too, documented
## design). The mountain stays after the zone despawns.

const RADIUS: float = 5.0
const PEAK: float = 6.0
const DURATION: float = 3.0


func _init() -> void:
	id = &"volcano"
	display_name_de = "Vulkan"
	charge_cost = 180.0
	max_charges = 1
	cast_range = 12.0


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var plan: Dictionary = cone_targets(ctx.terrain_data, Vector2(target.x, target.z))
	if (plan.indices as PackedInt32Array).is_empty():
		return false
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(ctx, plan, DURATION)
	ctx.unit_manager.register_projectile(morph)
	var zone: VolcanoZone = VolcanoZone.new()
	zone.setup(tribe.id, target, ctx.unit_manager, ctx.terrain_data,
		ctx.building_manager)
	ctx.unit_manager.register_projectile(zone)
	return true


## Cone height map: smoothstep bump peaking PEAK metres above the current
## centre ground — raises only (maxf with the existing terrain).
static func cone_targets(td: TerrainData, center: Vector2) -> Dictionary:
	var base: float = td.get_height(center.x, center.y)
	var min_vx: int = clampi(int(floor((center.x - RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var max_vx: int = clampi(int(ceil((center.x + RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var min_vz: int = clampi(int(floor((center.y - RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var max_vz: int = clampi(int(ceil((center.y + RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)

	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	var changed_min: Vector2i = Vector2i(td.verts, td.verts)
	var changed_max: Vector2i = Vector2i(-1, -1)
	for vz in range(min_vz, max_vz + 1):
		for vx in range(min_vx, max_vx + 1):
			var p: Vector2 = Vector2(float(vx), float(vz)) * TerrainData.CELL_SIZE
			var dist: float = p.distance_to(center)
			if dist > RADIUS:
				continue
			var s: float = clampf((RADIUS - dist) / RADIUS, 0.0, 1.0)
			var profile: float = base + PEAK * s * s * (3.0 - 2.0 * s)
			var idx: int = vz * td.verts + vx
			var current: float = td.heights[idx]
			var nh: float = maxf(current, profile)
			if absf(nh - current) <= 0.01:
				continue
			indices.append(idx)
			targets.append(nh)
			changed_min = Vector2i(mini(changed_min.x, vx), mini(changed_min.y, vz))
			changed_max = Vector2i(maxi(changed_max.x, vx), maxi(changed_max.y, vz))

	var rect: Rect2i = Rect2i()
	if changed_max.x >= 0:
		var cmin: Vector2i = (changed_min - Vector2i.ONE).clamp(Vector2i.ZERO,
			Vector2i(td.size - 1, td.size - 1))
		var cmax: Vector2i = changed_max.clamp(Vector2i.ZERO,
			Vector2i(td.size - 1, td.size - 1))
		rect = Rect2i(cmin, cmax - cmin + Vector2i.ONE)
	return {"indices": indices, "targets": targets, "rect": rect}
