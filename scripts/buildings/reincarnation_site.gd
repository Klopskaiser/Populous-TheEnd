class_name ReincarnationSite extends Building

## Reincarnation Site: prayer place for Braves (they count as praying_braves
## for the mana bonus while nearby) and the shaman's respawn location. Exactly
## one per tribe, pre-placed at match start. While the tribe's shaman is dead,
## the site counts down respawn_timer and then spawns exactly one new shaman
## at its edge. No site (destroyed) or a damaged site (not usable) -> no
## respawn: losing it is a real risk.

const WOOD_COST: int = 0
const FOOTPRINT: Vector2i = Balance.REINCARNATION_SITE_FOOTPRINT
## Radius around the centre in which a brave counts as praying.
const PRAY_RADIUS: float = 5.0
## Seconds between the shaman's death and her reincarnation.
const RESPAWN_TIME: float = Balance.SHAMAN_RESPAWN_TIME

const SHAMAN_SCENE: PackedScene = preload("res://scenes/units/shaman.tscn")

var respawn_timer: float = 0.0
## True while a respawn countdown is running (shaman dead).
var respawn_pending: bool = false


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.REINCARNATION_SITE_HP
	health = max_health


func display_name() -> String:
	return "Reinkarnationsplatz"


## The reincarnation circle cannot be attacked by ground units (melee storm /
## firewarrior fire) — only spells and catapults can damage it.
func is_assailable_by_units() -> bool:
	return false


## Remaining respawn wait for UI countdowns; -1 while the shaman lives.
func respawn_remaining() -> float:
	return respawn_timer if respawn_pending else -1.0


## Runs only while the site is usable (Building.tick gates on is_usable) —
## a wrecked or destroyed site cannot reincarnate the shaman.
func _tick_active(delta: float) -> void:
	if tribe == null or unit_manager == null:
		return
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
