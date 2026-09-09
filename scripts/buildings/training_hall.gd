class_name TrainingHall extends TrainingBuilding

## Training hall (Ausbildungshalle): trains braves into technicians. Cheap
## (10 wood, 4x4) but by far the slowest training building (10 s) — the
## technician's value sits in the vehicle bonuses he unlocks, not in numbers on
## the unit, so the throughput is the price.
##
## Placeholder mesh: a low workshop hall with a saddle roof, a wide gate on the
## south side, a chimney and a leaning workbench with a cart wheel — workshop
## theme, unmistakable next to the barracks (round tower), the temple and the
## fire temple.

const WOOD_COST: int = Balance.TRAINING_HALL_WOOD_COST
const FOOTPRINT: Vector2i = Balance.TRAINING_HALL_FOOTPRINT
const TRAINING_TIME: float = Balance.TRAINING_HALL_TRAINING_TIME
const TECHNICIAN_SCENE: PackedScene = preload("res://scenes/units/technician.tscn")

const C_WALL: Color = Color(0.52, 0.38, 0.24)
const C_ROOF: Color = Color(0.34, 0.28, 0.22)
const C_STONE: Color = Color(0.55, 0.53, 0.5)
const C_METAL: Color = Color(0.68, 0.7, 0.75)
const C_WOOD: Color = Color(0.42, 0.29, 0.16)


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.TRAINING_HALL_HP
	health = max_health
	produces = TECHNICIAN_SCENE
	training_time = TRAINING_TIME


func display_name() -> String:
	return "Ausbildungshalle"


func asset_kind() -> StringName:
	return &"training_hall"


## Authored with the entrance facing south (+z); the base rotates the mesh root.
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(footprint.x)

	# Hall body: a plain low box, wider than tall.
	var body: MeshInstance3D = MeshInstance3D.new()
	var bbox: BoxMesh = BoxMesh.new()
	bbox.size = Vector3(span * 0.8, 1.9, span * 0.72)
	body.mesh = bbox
	body.material_override = _make_material(C_WALL)
	body.position.y = 0.95
	_mesh_root.add_child(body)

	# Saddle roof: two flat boxes tilted against each other.
	for side in [-1.0, 1.0]:
		var pitch: MeshInstance3D = MeshInstance3D.new()
		var pbox: BoxMesh = BoxMesh.new()
		pbox.size = Vector3(span * 0.46, 0.16, span * 0.78)
		pitch.mesh = pbox
		pitch.material_override = _make_material(C_ROOF)
		pitch.rotation = Vector3(0.0, 0.0, side * -0.5)
		pitch.position = Vector3(side * span * 0.2, 2.3, 0.0)
		_mesh_root.add_child(pitch)

	# Wide workshop gate on the south face.
	var gate: MeshInstance3D = MeshInstance3D.new()
	var gbox: BoxMesh = BoxMesh.new()
	gbox.size = Vector3(span * 0.4, 1.4, 0.25)
	gate.mesh = gbox
	gate.material_override = _make_material(Color(0.16, 0.1, 0.05))
	gate.position = Vector3(0.0, 0.7, span * 0.36)
	_mesh_root.add_child(gate)

	# Chimney over the forge, back left.
	var chimney: MeshInstance3D = MeshInstance3D.new()
	var ccyl: CylinderMesh = CylinderMesh.new()
	ccyl.top_radius = 0.22
	ccyl.bottom_radius = 0.26
	ccyl.height = 1.6
	chimney.mesh = ccyl
	chimney.material_override = _make_material(C_STONE)
	chimney.position = Vector3(-span * 0.22, 2.7, -span * 0.2)
	_mesh_root.add_child(chimney)

	# Cart wheel leaning against the east wall — the workshop tell.
	var wheel: MeshInstance3D = MeshInstance3D.new()
	var wcyl: CylinderMesh = CylinderMesh.new()
	wcyl.top_radius = 0.55
	wcyl.bottom_radius = 0.55
	wcyl.height = 0.14
	wheel.mesh = wcyl
	wheel.material_override = _make_material(C_WOOD)
	wheel.rotation = Vector3(0.0, 0.0, PI * 0.5)
	wheel.position = Vector3(span * 0.42, 0.6, span * 0.1)
	_mesh_root.add_child(wheel)

	# Workbench with a bright metal top, west side.
	var bench: MeshInstance3D = MeshInstance3D.new()
	var nbox: BoxMesh = BoxMesh.new()
	nbox.size = Vector3(0.5, 0.12, span * 0.4)
	bench.mesh = nbox
	bench.material_override = _make_material(C_METAL)
	bench.position = Vector3(-span * 0.44, 0.9, 0.0)
	_mesh_root.add_child(bench)

	_add_flag()
