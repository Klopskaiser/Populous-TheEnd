class_name EarthquakeSpell extends Spell

## "Erdbeben": area terrain upheaval around the target point. Every vertex in
## the radius shifts by a deterministic random delta (seeded from the target
## cell, falloff to the rim), gradually over DURATION (TerrainMorph).
## Buildings in the radius take +2 destruction stages (construction sites die
## outright — existing fragile rule); on top of that the terrain-integrity
## rules apply (foundation break, flooding). Enemy units take light damage
## and a mini roll away from the epicentre. Water clamp: quake bumps never
## push the sea floor up (no useless underwater humps); LOWERING below the
## sea line is allowed and floods land — tactical terrain destruction.

const RADIUS: float = 7.0
const AMPLITUDE: float = 1.5       # max vertex shift (metres, +/-)
const DURATION: float = 2.0
const STAGES: int = 2
const UNIT_DAMAGE: int = 15        # 1/4 brave life


func _init() -> void:
	id = &"earthquake"
	display_name_de = "Erdbeben"
	charge_cost = 80.0
	max_charges = 2
	cast_range = 10.0


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var plan: Dictionary = upheaval_targets(ctx.terrain_data,
		Vector2(target.x, target.z))
	if (plan.indices as PackedInt32Array).is_empty():
		return false
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(ctx, plan, DURATION)
	ctx.unit_manager.register_projectile(morph)
	_hit_buildings(tribe, target, ctx)
	_hit_units(tribe, target, ctx)
	return true


## Deterministic random vertex deltas (RNG seeded from the target cell, drawn
## in scan order) with a smoothstep falloff to the rim — WITHOUT touching the
## heightmap (the morph interpolates toward it).
static func upheaval_targets(td: TerrainData, center: Vector2) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_cell: Vector2i = Vector2i(int(floor(center.x)), int(floor(center.y)))
	rng.seed = seed_cell.x * 73856093 + seed_cell.y * 19349663
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
			var delta: float = rng.randf_range(-AMPLITUDE, AMPLITUDE) * falloff
			var idx: int = vz * TerrainData.VERTS + vx
			var current: float = td.heights[idx]
			# Water clamp: never lift the sea floor (lowering stays allowed).
			if delta > 0.0 and current <= TerrainData.SEA_LEVEL:
				continue
			if absf(delta) <= 0.01:
				continue
			indices.append(idx)
			targets.append(current + delta)
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


## Enemy buildings whose centre lies in the radius take +2 stages.
func _hit_buildings(tribe: Tribe, target: Vector3, ctx: SpellContext) -> void:
	if ctx.building_manager == null:
		return
	var flat: Vector2 = Vector2(target.x, target.z)
	for b in ctx.building_manager.buildings.duplicate():
		if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == tribe.id:
			continue
		var c: Vector3 = b.center_world()
		if Vector2(c.x, c.z).distance_to(flat) <= RADIUS:
			b.apply_destruction_stages(STAGES)


## Enemy units in the radius: light damage plus a mini roll away from the
## epicentre (attacker = shaman for retaliation/kill credit).
func _hit_units(tribe: Tribe, target: Vector3, ctx: SpellContext) -> void:
	var caster: Unit = tribe.shaman if tribe != null else null
	var attacker = caster if (caster != null and is_instance_valid(caster)) else null
	for u in ctx.unit_manager.get_units_in_radius(target, RADIUS):
		if u.state == Unit.State.DEAD or u.tribe_id == tribe.id:
			continue
		u.take_damage(UNIT_DAMAGE, attacker)
		if u.state == Unit.State.DEAD:
			continue
		var away: Vector3 = Vector3(u.position.x - target.x, 0.0, u.position.z - target.z)
		if away.length_squared() < 0.000001:
			away = Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		u.start_roll(away.normalized())
