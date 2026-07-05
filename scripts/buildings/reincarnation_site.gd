class_name ReincarnationSite extends Building

## Reincarnation Site: prayer place for Braves (they count as praying_braves
## for the mana bonus while nearby) and — from phase 5 on — the shaman's
## respawn location. Exactly one per tribe, pre-placed at match start.

const WOOD_COST: int = 0
const FOOTPRINT: Vector2i = Vector2i(3, 3)
## Radius around the centre in which a brave counts as praying.
const PRAY_RADIUS: float = 5.0


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = 500
	health = 500


func display_name() -> String:
	return "Reinkarnationsplatz"


func _create_visuals() -> void:
	super._create_visuals()
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
