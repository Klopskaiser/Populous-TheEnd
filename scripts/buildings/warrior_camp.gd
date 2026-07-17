class_name WarriorCamp extends TrainingBuilding

## Warrior camp (Kaserne): trains braves into warriors. Cheapest and fastest
## training building (5 wood, 3 s). Placeholder mesh evokes the reference image:
## a ring/horseshoe wall around a courtyard, a tall round tower with a spire and
## a blue-violet plume, and shields on the outer wall. War/weapon theme.

const WOOD_COST: int = Balance.WARRIOR_CAMP_WOOD_COST
const FOOTPRINT: Vector2i = Balance.WARRIOR_CAMP_FOOTPRINT
const TRAINING_TIME: float = Balance.WARRIOR_CAMP_TRAINING_TIME
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/warrior.tscn")

const C_WALL: Color = Color(0.5, 0.35, 0.2)
const C_ROOF: Color = Color(0.4, 0.25, 0.12)
const C_STONE: Color = Color(0.55, 0.53, 0.5)
const C_RUNE: Color = Color(0.3, 0.35, 0.85)
const C_METAL: Color = Color(0.7, 0.72, 0.78)


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.WARRIOR_CAMP_HP
	health = max_health
	produces = WARRIOR_SCENE
	training_time = TRAINING_TIME


func display_name() -> String:
	return "Kaserne"


func asset_kind() -> StringName:
	return &"warrior_camp"


## Authored with the entrance facing south (+z); the base rotates the mesh root.
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(footprint.x)

	# Ring wall around the courtyard (flattened torus = low round rampart).
	var wall: MeshInstance3D = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = span * 0.32
	ring.outer_radius = span * 0.46
	wall.mesh = ring
	wall.material_override = _make_material(C_WALL)
	wall.scale = Vector3(1.0, 3.0, 1.0)
	wall.position.y = 1.0
	_mesh_root.add_child(wall)

	# Gate opening on the south side (dark arch + blue rune knots beside it).
	var gate: MeshInstance3D = MeshInstance3D.new()
	var gate_box: BoxMesh = BoxMesh.new()
	gate_box.size = Vector3(1.1, 1.4, 0.8)
	gate.mesh = gate_box
	gate.material_override = _make_material(Color(0.16, 0.1, 0.05))
	gate.position = Vector3(0.0, 0.7, span * 0.44)
	_mesh_root.add_child(gate)
	for sx in [-0.9, 0.9]:
		var rune: MeshInstance3D = MeshInstance3D.new()
		var rb: BoxMesh = BoxMesh.new()
		rb.size = Vector3(0.3, 1.3, 0.3)
		rune.mesh = rb
		rune.material_override = _make_material(C_RUNE)
		rune.position = Vector3(sx, 0.75, span * 0.44)
		_mesh_root.add_child(rune)

	# Tall round tower at the back with a conical spire and a plume.
	var tower: MeshInstance3D = MeshInstance3D.new()
	var tcyl: CylinderMesh = CylinderMesh.new()
	tcyl.top_radius = 0.6
	tcyl.bottom_radius = 0.75
	tcyl.height = 3.4
	tower.mesh = tcyl
	tower.material_override = _make_material(C_STONE)
	tower.position = Vector3(0.0, 1.7, -span * 0.28)
	_mesh_root.add_child(tower)

	var spire: MeshInstance3D = MeshInstance3D.new()
	var scone: CylinderMesh = CylinderMesh.new()
	scone.top_radius = 0.0
	scone.bottom_radius = 0.7
	scone.height = 1.1
	spire.mesh = scone
	spire.material_override = _make_material(C_ROOF)
	spire.position = Vector3(0.0, 3.95, -span * 0.28)
	_mesh_root.add_child(spire)

	var plume: MeshInstance3D = MeshInstance3D.new()
	var psphere: SphereMesh = SphereMesh.new()
	psphere.radius = 0.28
	psphere.height = 0.56
	plume.mesh = psphere
	plume.material_override = _make_material(Color(0.4, 0.3, 0.75))
	plume.position = Vector3(0.0, 4.7, -span * 0.28)
	_mesh_root.add_child(plume)

	# A couple of shields on the front wall.
	for sx2 in [-1.2, 1.2]:
		var shield: MeshInstance3D = MeshInstance3D.new()
		var sm: CylinderMesh = CylinderMesh.new()
		sm.top_radius = 0.35
		sm.bottom_radius = 0.35
		sm.height = 0.15
		shield.mesh = sm
		shield.material_override = _make_material(C_METAL)
		shield.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		shield.position = Vector3(sx2, 1.2, span * 0.5)
		_mesh_root.add_child(shield)

	_add_flag()
