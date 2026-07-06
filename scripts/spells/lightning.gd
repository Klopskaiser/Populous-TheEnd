class_name LightningSpell extends Spell

## "Blitz": strikes the target point. An enemy BUILDING there takes +2
## destruction stages; otherwise the nearest enemy unit around the point takes
## 4x a brave's life (240) and its adjacent units are knocked into a short
## roll (longer only on a slope, via the normal fall-line rolling). No target
## at all -> the cast fails and the charge is kept.

const UNIT_DAMAGE: int = 240        # 4x brave life
const TARGET_RADIUS: float = 3.0    # victim search radius around the click
const NEIGHBOR_RADIUS: float = 1.5  # adjacent units start rolling
const BUILDING_STAGES: int = 2
## The white beam is visible this long.
const BEAM_TIME: float = 0.35


func _init() -> void:
	id = &"lightning"
	display_name_de = "Blitz"
	charge_cost = 60.0
	max_charges = 4
	cast_range = 10.0


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or tribe == null:
		return false
	var building: Building = _building_at(tribe, target, ctx)
	if building != null:
		building.apply_destruction_stages(BUILDING_STAGES)
		_spawn_beam(building.center_world(), ctx)
		return true
	var victim: Unit = _nearest_enemy(tribe, target, ctx)
	if victim == null:
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

	func _ready() -> void:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.35
		cyl.bottom_radius = 0.12
		cyl.height = 30.0
		mesh.mesh = cyl
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 1.0, 0.9)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat
		mesh.position.y = 15.0
		add_child(mesh)
