class_name FirewarriorCamp extends TrainingBuilding

## Fire temple (Feuertempel): trains braves into firewarriors (10 wood, 4 s).
## Placeholder mesh evokes the reference image: a round central hut with a wide
## conical reed roof, a dark round entrance, and two blazing fire bowls out
## front. Fire theme.

const WOOD_COST: int = 10
const FOOTPRINT: Vector2i = Vector2i(4, 4)
const TRAINING_TIME: float = 4.0
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")

const C_WALL: Color = Color(0.32, 0.4, 0.7)
const C_ROOF: Color = Color(0.42, 0.26, 0.12)
const C_RUNE: Color = Color(0.4, 0.55, 0.95)


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = 320
	health = 320
	produces = FIREWARRIOR_SCENE
	training_time = TRAINING_TIME


func display_name() -> String:
	return "Feuertempel"


func _create_visuals() -> void:
	super._create_visuals()
	var span: float = float(footprint.x)

	# Round central hut (blue-painted fur walls).
	var hutbody: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = span * 0.34
	cyl.bottom_radius = span * 0.36
	cyl.height = 1.7
	hutbody.mesh = cyl
	hutbody.material_override = _make_material(C_WALL)
	hutbody.position.y = 0.85
	_mesh_root.add_child(hutbody)

	# Wide conical reed roof.
	var roof: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = span * 0.5
	cone.height = 1.6
	roof.mesh = cone
	roof.material_override = _make_material(C_ROOF)
	roof.position.y = 2.5
	_mesh_root.add_child(roof)

	# Dark round entrance on the south side + blue rune.
	var door: MeshInstance3D = MeshInstance3D.new()
	var db: BoxMesh = BoxMesh.new()
	db.size = Vector3(0.8, 1.1, 0.4)
	door.mesh = db
	door.material_override = _make_material(Color(0.1, 0.12, 0.2))
	door.position = Vector3(0.0, 0.55, span * 0.34)
	_mesh_root.add_child(door)
	var rune: MeshInstance3D = MeshInstance3D.new()
	var rb: BoxMesh = BoxMesh.new()
	rb.size = Vector3(0.6, 0.3, 0.2)
	rune.mesh = rb
	rune.material_override = _make_material(C_RUNE)
	rune.position = Vector3(0.0, 1.3, span * 0.35)
	_mesh_root.add_child(rune)

	# Two blazing fire bowls out front (dark stand + glowing flame).
	for sx in [-span * 0.42, span * 0.42]:
		var stand: MeshInstance3D = MeshInstance3D.new()
		var sc: CylinderMesh = CylinderMesh.new()
		sc.top_radius = 0.22
		sc.bottom_radius = 0.16
		sc.height = 0.8
		stand.mesh = sc
		stand.material_override = _make_material(Color(0.3, 0.2, 0.1))
		stand.position = Vector3(sx, 0.4, span * 0.5)
		_mesh_root.add_child(stand)
		var flame: MeshInstance3D = MeshInstance3D.new()
		var fc: CylinderMesh = CylinderMesh.new()
		fc.top_radius = 0.0
		fc.bottom_radius = 0.3
		fc.height = 0.7
		flame.mesh = fc
		var fmat: StandardMaterial3D = StandardMaterial3D.new()
		fmat.albedo_color = Color(1.0, 0.55, 0.15)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.45, 0.1)
		fmat.emission_energy_multiplier = 1.5
		flame.material_override = fmat
		flame.position = Vector3(sx, 1.05, span * 0.5)
		_mesh_root.add_child(flame)

	_add_flag()
