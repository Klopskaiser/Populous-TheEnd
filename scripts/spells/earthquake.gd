class_name EarthquakeSpell extends Spell

## "Erdbeben": the ground BREAKS along a visible fault line through the
## target point (orientation seeded from the target cell — deterministic).
## One side of the fault drops, the other piles up slightly, leaving a sharp
## scarp edge; the break forms gradually over DURATION (TerrainMorph) and
## short-lived lava runs down the fresh scarp and vanishes quickly (no
## scorch). Buildings in the radius take +2 destruction stages (construction
## sites die outright — existing fragile rule); on top of that the
## terrain-integrity rules apply (foundation break, flooding). Enemy units
## take light damage and a mini roll away from the epicentre. Water clamp:
## the sea floor is never lifted; LOWERING below the sea line is allowed and
## floods land — tactical terrain destruction.

const RADIUS: float = 7.0
const DROP: float = 2.2            # subsidence at the fault (drop side)
const LIFT: float = 0.8            # pile-up at the fault (rise side)
const DURATION: float = 2.0
const STAGES: int = 2
const UNIT_DAMAGE: int = 15        # 1/4 brave life
## Fault lava: short streams down the scarp that disappear quickly.
const FAULT_LAVA_RANGE: float = 3.5
const FAULT_LAVA_LIFETIME: float = 3.5
const FAULT_LAVA_MOLTEN: float = 3.0


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
	_spawn_fault_lava(target, plan, ctx)
	_hit_buildings(tribe, target, ctx)
	_hit_units(tribe, target, ctx)
	return true


## Fault height map: vertices on the drop side sink (deepest right at the
## fault line, easing off away from it), the rise side piles up slightly —
## adjacent vertices across the line end up far apart: a visible scarp. The
## whole effect fades toward the radius rim. Deterministic (fault
## orientation seeded from the target cell); the heightmap is NOT touched
## (the morph interpolates toward the plan). Extra keys "fault"/"normal"
## (Vector2) describe the line for the lava spawner.
static func upheaval_targets(td: TerrainData, center: Vector2) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed_cell: Vector2i = Vector2i(int(floor(center.x)), int(floor(center.y)))
	rng.seed = seed_cell.x * 73856093 + seed_cell.y * 19349663
	var angle: float = rng.randf() * TAU
	var fault: Vector2 = Vector2(cos(angle), sin(angle))
	var normal: Vector2 = Vector2(-fault.y, fault.x)

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
			var rim: float = t * t * (3.0 - 2.0 * t)   # fade toward the rim
			var side: float = (p - center).dot(normal)
			var delta: float
			if side < 0.0:
				delta = -DROP * rim * clampf(1.0 - absf(side) / RADIUS, 0.0, 1.0)
			else:
				delta = LIFT * rim * clampf(1.0 - side / (RADIUS * 0.6), 0.0, 1.0)
			var idx: int = vz * TerrainData.VERTS + vx
			var current: float = td.heights[idx]
			# Water clamp: never lift the sea floor (lowering stays allowed).
			if delta > 0.0 and current <= TerrainData.SEA_LEVEL:
				continue
			if absf(delta) <= 0.05:
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
	return {"indices": indices, "targets": targets, "rect": rect,
		"fault": fault, "normal": normal}


## Short-lived lava spilling over the fresh scarp toward the dropped side,
## spawned at a few points along the fault line.
func _spawn_fault_lava(target: Vector3, plan: Dictionary, ctx: SpellContext) -> void:
	var fault: Vector2 = plan.fault
	var normal: Vector2 = plan.normal
	var downhill: Vector3 = Vector3(-normal.x, 0.0, -normal.y)   # drop side
	for offset in [-3.0, 0.0, 3.0]:
		var at: Vector3 = Vector3(target.x + fault.x * offset, 0.0,
			target.z + fault.y * offset)
		at.y = ctx.terrain_data.get_height(at.x, at.z)
		var flow: LavaFlow = LavaFlow.new()
		flow.setup(at, downhill, ctx.unit_manager, ctx.terrain_data,
			FAULT_LAVA_RANGE, FAULT_LAVA_LIFETIME, FAULT_LAVA_MOLTEN, false)
		ctx.unit_manager.register_projectile(flow)


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
