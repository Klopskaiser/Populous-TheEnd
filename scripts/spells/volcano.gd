class_name VolcanoSpell extends Spell

## "Vulkan": raises a PERMANENT mountain with a real CRATER (phase 10k) over
## DURATION, then a VolcanoZone burns everything around it for its lifetime (lava
## knows no friends: OWN units burn too, documented design). The mountain stays
## after the zone despawns.
##
## SHAPE (10k, replaces the pointed smoothstep cone): the highest ring is the
## crater RIM at VOLCANO_RIM_FRACTION of the radius; inside it the ground dips
## VOLCANO_CRATER_DEPTH lower — that hollow is where the lava wells up before it
## spills over the rim. Once it has spilled, fill_crater_targets() pulls the
## hollow up to rim height, leaving a small round summit plateau.

const RADIUS: float = Balance.VOLCANO_RADIUS
const PEAK: float = 6.0
const DURATION: float = 3.0
## Radius of the crater rim (the highest ring) and of the later summit plateau.
const RIM_RADIUS: float = Balance.VOLCANO_RADIUS * Balance.VOLCANO_RIM_FRACTION
const CRATER_DEPTH: float = Balance.VOLCANO_CRATER_DEPTH


func _init() -> void:
	id = &"volcano"
	display_name_de = "Vulkan"
	charge_cost = Balance.SPELL_VOLCANO_CHARGE_COST
	max_charges = Balance.SPELL_VOLCANO_MAX_CHARGES
	cast_range = Balance.SPELL_VOLCANO_CAST_RANGE
	effect_delay = Balance.SPELL_EFFECT_DELAY_LATE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var plan: Dictionary = cone_targets(ctx.terrain_data, Vector2(target.x, target.z))
	if (plan.indices as PackedInt32Array).is_empty():
		return false
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(ctx, plan, DURATION)
	morph.sfx_id = id
	ctx.unit_manager.register_projectile(morph)
	var zone: VolcanoZone = VolcanoZone.new()
	zone.setup(tribe.id, target, ctx.unit_manager, ctx.terrain_data,
		ctx.building_manager)
	ctx.unit_manager.register_projectile(zone)
	return true


## Second morph, applied when the lava spills over the rim: pulls the hollow up
## to RIM height so the summit ends as a small round PLATEAU (user spec). Same
## shape as cone_targets, only the inner circle and only upward.
static func fill_crater_targets(td: TerrainData, center: Vector2,
		base: float) -> Dictionary:
	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	var changed_min: Vector2i = Vector2i(td.verts, td.verts)
	var changed_max: Vector2i = Vector2i(-1, -1)
	var rim_height: float = base + PEAK
	var lo_x: int = clampi(int(floor((center.x - RIM_RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var hi_x: int = clampi(int(ceil((center.x + RIM_RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var lo_z: int = clampi(int(floor((center.y - RIM_RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	var hi_z: int = clampi(int(ceil((center.y + RIM_RADIUS) / TerrainData.CELL_SIZE)), 0, td.verts - 1)
	for vz in range(lo_z, hi_z + 1):
		for vx in range(lo_x, hi_x + 1):
			var p: Vector2 = Vector2(float(vx), float(vz)) * TerrainData.CELL_SIZE
			if p.distance_to(center) > RIM_RADIUS:
				continue
			var idx: int = vz * td.verts + vx
			var current: float = td.heights[idx]
			if rim_height - current <= 0.01:
				continue          # already at or above rim level
			indices.append(idx)
			targets.append(rim_height)
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


## Height of the crater profile at distance `d` from the centre, relative to the
## base ground. Pure and static so the shape is testable without a scene:
##
##   d = RADIUS      -> 0            (the foot, untouched)
##   d = RIM_RADIUS  -> PEAK         (the rim, the highest point)
##   d = 0           -> PEAK - DEPTH (the hollow the lava wells up in)
static func crater_profile(d: float) -> float:
	var flank: float = clampf((RADIUS - d) / maxf(RADIUS - RIM_RADIUS, 0.001), 0.0, 1.0)
	var bowl: float = clampf((RIM_RADIUS - d) / maxf(RIM_RADIUS, 0.001), 0.0, 1.0)
	return PEAK * (flank * flank * (3.0 - 2.0 * flank)) 		- CRATER_DEPTH * (bowl * bowl * (3.0 - 2.0 * bowl))


## Crater height map — raises only (maxf with the existing terrain), so a volcano
## on a slope never digs the mountain side away.
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
			var profile: float = base + crater_profile(dist)
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
