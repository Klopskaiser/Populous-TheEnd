class_name LightningSpell extends Spell

## "Blitz": strikes the target point. An enemy BUILDING there takes +2
## destruction stages; otherwise the nearest enemy unit around the point takes
## 4x a brave's life (240) and its adjacent units are knocked into a short
## roll (longer only on a slope, via the normal fall-line rolling). No target
## at all -> the cast fails and the charge is kept.

const UNIT_DAMAGE: int = Balance.LIGHTNING_UNIT_DAMAGE
const TARGET_RADIUS: float = 3.0    # victim search radius around the click
const NEIGHBOR_RADIUS: float = 1.5  # adjacent units start rolling
const BUILDING_STAGES: int = Balance.LIGHTNING_BUILDING_STAGES
## The white beam is visible this long.
const BEAM_TIME: float = 0.35


func _init() -> void:
	id = &"lightning"
	display_name_de = "Blitz"
	charge_cost = Balance.SPELL_LIGHTNING_CHARGE_COST
	max_charges = Balance.SPELL_LIGHTNING_MAX_CHARGES
	cast_range = Balance.SPELL_LIGHTNING_CAST_RANGE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or tribe == null:
		return false
	# Lightning also sets trees and wood piles at the strike point alight
	# (phase 7d) — independent of hitting a unit or building.
	var burned: int = 0
	if ctx.tree_manager != null:
		burned += ctx.tree_manager.ignite_in_radius(target, TARGET_RADIUS)
	if ctx.wood_pile_manager != null:
		burned += ctx.wood_pile_manager.ignite_in_radius(target, TARGET_RADIUS)
	var building: Building = _building_at(tribe, target, ctx)
	if building != null:
		building.apply_destruction_stages(BUILDING_STAGES)
		_spawn_beam(building.center_world(), ctx)
		return true
	# Enemy AIRSHIP over the strike point: the bolt kills it instantly (user
	# spec) — it takes priority over a ground victim under its shadow. The
	# radius query is flat, so the shadow position matches.
	var ship: Airship = _airship_at(tribe, target, ctx)
	if ship != null:
		_spawn_beam(ship.position, ctx)
		ship.explode()
		return true
	# Enemy ground DEVICE (catapult / fire ram) at the point: direct damage is a
	# no-op on a vehicle, so the bolt sets it alight (it burns out and sinks).
	var vehicle: CrewedVehicle = _vehicle_at(tribe, target, ctx)
	if vehicle != null:
		_spawn_beam(vehicle.position, ctx)
		vehicle.ignite(vehicle.position)
		return true
	var victim: Unit = _nearest_enemy(tribe, target, ctx)
	if victim == null:
		# No unit/building, but the bolt still torched flammables -> a hit.
		if burned > 0:
			_spawn_beam(target, ctx)
			return true
		return false
	var caster = tribe.shaman if is_instance_valid(tribe.shaman) else null
	_spawn_beam(victim.position, ctx)
	# Adjacent units first (the victim's position may deregister on death).
	if ctx.unit_manager != null:
		for u in ctx.unit_manager.get_units_in_radius(victim.position, NEIGHBOR_RADIUS):
			if u == victim or u.state == Unit.State.DEAD or u.tribe_id == tribe.id:
				continue
			var away: Vector3 = Vector3(u.position.x - victim.position.x, 0.0,
				u.position.z - victim.position.z)
			u.start_roll(away)
	victim.take_damage(UNIT_DAMAGE, caster)
	return true


## Enemy building whose footprint (slightly grown — the terrain click lands
## next to the walls) contains the target point.
func _building_at(tribe: Tribe, target: Vector3, ctx: SpellContext) -> Building:
	if ctx.building_manager == null:
		return null
	var cell: Vector2i = Vector2i(
		int(floor(target.x / TerrainData.CELL_SIZE)),
		int(floor(target.z / TerrainData.CELL_SIZE)))
	for b in ctx.building_manager.buildings:
		if not is_instance_valid(b) or b.tribe_id == tribe.id or b.health <= 0:
			continue
		if b.footprint_rect().grow(1).has_point(cell):
			return b
	return null


## Nearest enemy airship whose shadow lies within the strike radius.
func _airship_at(tribe: Tribe, target: Vector3, ctx: SpellContext) -> Airship:
	if ctx.unit_manager == null:
		return null
	var best: Airship = null
	var best_d: float = TARGET_RADIUS
	for u in ctx.unit_manager.get_units_in_radius(target, TARGET_RADIUS):
		if not (u is Airship) or u.state == Unit.State.DEAD or u.tribe_id == tribe.id:
			continue
		var d: float = Vector2(u.position.x - target.x, u.position.z - target.z).length()
		if d <= best_d:
			best_d = d
			best = u
	return best


## Nearest enemy ground device (crewed vehicle that is NOT an airship — those
## are handled by _airship_at) whose position lies within the strike radius.
func _vehicle_at(tribe: Tribe, target: Vector3, ctx: SpellContext) -> CrewedVehicle:
	if ctx.unit_manager == null:
		return null
	var best: CrewedVehicle = null
	var best_d: float = TARGET_RADIUS
	for u in ctx.unit_manager.get_units_in_radius(target, TARGET_RADIUS):
		if not (u is CrewedVehicle) or u is Airship or u.state == Unit.State.DEAD \
				or u.tribe_id == tribe.id:
			continue
		var d: float = Vector2(u.position.x - target.x, u.position.z - target.z).length()
		if d <= best_d:
			best_d = d
			best = u
	return best


func _nearest_enemy(tribe: Tribe, target: Vector3, ctx: SpellContext) -> Unit:
	if ctx.unit_manager == null:
		return null
	var best: Unit = null
	var best_d: float = INF
	for u in ctx.unit_manager.get_units_in_radius(target, TARGET_RADIUS):
		if u.state == Unit.State.DEAD or u.tribe_id == tribe.id:
			continue
		var d: float = Vector2(u.position.x - target.x, u.position.z - target.z).length()
		if d < best_d:
			best_d = d
			best = u
	return best


## Short-lived white beam column (visual only; created in _ready, so headless
## tests never build meshes).
func _spawn_beam(at: Vector3, ctx: SpellContext) -> void:
	if ctx.unit_manager == null:
		return
	var beam: LightningBeam = LightningBeam.new()
	beam.position = at
	beam.lifetime = BEAM_TIME
	ctx.unit_manager.register_projectile(beam)


class LightningBeam extends Node3D:
	var done: bool = false
	var lifetime: float = 0.35

	func tick(delta: float) -> void:
		lifetime -= delta
		if lifetime <= 0.0:
			done = true

	## Jagged bolt: a polyline from high above down to the strike point with
	## lateral jitter per joint; every segment is a thin bright cylinder.
	func _ready() -> void:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 1.0, 0.9)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var steps: int = 7
		var points: Array[Vector3] = []
		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			var y: float = lerpf(26.0, 0.0, t)
			# The strike point itself stays exact; every joint above zigzags.
			var jitter: float = 0.0 if i == steps else 1.2
			points.append(Vector3(
				randf_range(-jitter, jitter), y, randf_range(-jitter, jitter)))
		for i in range(points.size() - 1):
			_add_segment(points[i], points[i + 1], mat)

	func _add_segment(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
		var seg: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.09
		cyl.bottom_radius = 0.09
		cyl.height = a.distance_to(b)
		seg.mesh = cyl
		seg.material_override = mat
		add_child(seg)
		seg.position = (a + b) * 0.5
		# Align the cylinder's Y axis with the segment direction.
		var dir: Vector3 = (b - a).normalized()
		var axis: Vector3 = Vector3.UP.cross(dir)
		if axis.length_squared() > 0.000001:
			seg.rotate(axis.normalized(), Vector3.UP.angle_to(dir))
