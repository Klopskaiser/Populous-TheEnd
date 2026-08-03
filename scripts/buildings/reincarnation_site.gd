class_name ReincarnationSite extends Building

## Reincarnation Site: the shaman's respawn location (praying was dropped as
## a feature in phase 10c). Exactly one per tribe, pre-placed at match start. While the tribe's shaman is dead,
## the site counts down respawn_timer and then spawns exactly one new shaman
## at its edge. No site (destroyed) or a damaged site (not usable) -> no
## respawn: losing it is a real risk.

const WOOD_COST: int = 0
const FOOTPRINT: Vector2i = Balance.REINCARNATION_SITE_FOOTPRINT
## Seconds between the shaman's death and her reincarnation.
const RESPAWN_TIME: float = Balance.SHAMAN_RESPAWN_TIME

const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")

var respawn_timer: float = 0.0
## True while a respawn countdown is running (shaman dead).
var respawn_pending: bool = false
## Latch for the self-destruction (10d): the circle only gives itself up once it
## has actually SEEN a follower. Without it a site placed before the tribe's
## braves exist (match setup order) would sink on its very first tick.
var _saw_followers: bool = false


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.REINCARNATION_SITE_HP
	health = max_health


func display_name() -> String:
	return "Reinkarnationsplatz"


## The reincarnation circle cannot be attacked by ground units (melee storm /
## firewarrior fire).
func is_assailable_by_units() -> bool:
	return false


# --- Invulnerability (phase 10d) ---------------------------------------------
# The circle takes NO damage at all any more: not from units, spells, catapults,
# lava or terrain deformation (SpellContext.check_terrain_integrity skips it).
# It only ever disappears through its own self-destruction below — that makes the
# defeat chain "last follower dies -> circle sinks -> shaman dies -> tribe out"
# the single way a tribe can be eliminated, instead of a lucky volcano roll.

func take_damage(_amount: int, _source: int = DMG_GENERIC) -> void:
	pass


func apply_destruction_stages(_count: int) -> void:
	pass


func add_lava_contact(_seconds: float) -> void:
	pass


## True once the tribe has no living follower left — the shaman herself does not
## count. The circle then gives itself up (see _tick_active): with nobody left to
## rebuild, keeping the tribe's lifeline alive would only stall the match.
func _tribe_has_no_followers() -> bool:
	if tribe == null:
		return false
	for unit in tribe.units:
		if not is_instance_valid(unit) or unit.state == Unit.State.DEAD:
			continue
		if unit == tribe.shaman:
			continue
		return false
	return true


## Remaining respawn wait for UI countdowns; -1 while the shaman lives.
func respawn_remaining() -> float:
	return respawn_timer if respawn_pending else -1.0


## Runs only while the site is usable (Building.tick gates on is_usable) —
## a destroyed site cannot reincarnate the shaman. Since 10d the circle is
## invulnerable, so "not usable" only ever means "gone".
func _tick_active(delta: float) -> void:
	if tribe == null or unit_manager == null:
		return
	# Self-destruction (10d): no followers left -> the circle sinks like any other
	# wreck. There is no way back — a destroyed site never reincarnates again.
	if _tribe_has_no_followers():
		if _saw_followers:
			destroy()
			return
	else:
		_saw_followers = true
	var shaman: Unit = tribe.shaman
	if shaman != null and is_instance_valid(shaman) and shaman.state != Unit.State.DEAD:
		respawn_pending = false   # never a second shaman
		return
	if not respawn_pending:
		respawn_pending = true
		respawn_timer = RESPAWN_TIME
		return
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn_pending = false
		unit_manager.spawn_unit(SHAMAN_SCENE, tribe_id, edge_spawn_position())


func asset_kind() -> StringName:
	return &"reincarnation_site"


func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.4
	ring.mesh = torus
	ring.material_override = _make_material(Color(0.92, 0.9, 0.85))
	ring.position.y = 0.15
	ring.scale = Vector3(1.0, 0.4, 1.0)
	_mesh_root.add_child(ring)
	var stone: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.4
	cyl.height = 1.2
	stone.mesh = cyl
	stone.material_override = _make_material(Color(0.85, 0.82, 0.75))
	stone.position.y = 0.6
	_mesh_root.add_child(stone)
	_add_flag()
