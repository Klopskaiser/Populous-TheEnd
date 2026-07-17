class_name FirewarriorCamp extends TrainingBuilding

## Fire temple (Feuertempel): trains braves into firewarriors (20 wood, 4 s).
## Phase 7i: a much larger, POLYGONAL fortress (8x8 footprint) — a big octagonal
## keep with a stepped octagonal roof, a dark gate and four blazing fire bowls at
## the corners. Fire theme.

const WOOD_COST: int = Balance.FIREWARRIOR_CAMP_WOOD_COST
const FOOTPRINT: Vector2i = Vector2i(8, 8)
const TRAINING_TIME: float = Balance.FIREWARRIOR_CAMP_TRAINING_TIME
const FIREWARRIOR_SCENE: PackedScene = preload("res://scenes/units/firewarrior.tscn")

## Low radial segment count -> visibly polygonal (octagonal) placeholder body.
const SIDES: int = 8

const C_WALL: Color = Color(0.32, 0.4, 0.7)
const C_ROOF: Color = Color(0.42, 0.26, 0.12)
const C_RUNE: Color = Color(0.4, 0.55, 0.95)


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.FIREWARRIOR_CAMP_HP
	health = max_health
	produces = FIREWARRIOR_SCENE
	training_time = TRAINING_TIME


func display_name() -> String:
	return "Feuertempel"


func asset_kind() -> StringName:
	return &"firewarrior_camp"


func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(footprint.x)   # 8

	# Big octagonal keep (blue-painted fur walls), tall.
	var hutbody: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.radial_segments = SIDES
	cyl.top_radius = span * 0.40
	cyl.bottom_radius = span * 0.44
	cyl.height = 3.2
	hutbody.mesh = cyl
	hutbody.material_override = _make_material(C_WALL)
	hutbody.position.y = 1.6
	_mesh_root.add_child(hutbody)

	# Lower stepped octagonal skirt for bulk.
	var skirt: MeshInstance3D = MeshInstance3D.new()
	var scyl: CylinderMesh = CylinderMesh.new()
	scyl.radial_segments = SIDES
	scyl.top_radius = span * 0.46
	scyl.bottom_radius = span * 0.5
	scyl.height = 1.2
	skirt.mesh = scyl
	skirt.material_override = _make_material(C_WALL.darkened(0.15))
	skirt.position.y = 0.6
	_mesh_root.add_child(skirt)

	# Octagonal (polygonal) reed roof — overlaps the keep but with a modest eave.
	var roof: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.radial_segments = SIDES
	cone.top_radius = 0.0
	cone.bottom_radius = span * 0.46
	cone.height = 2.6
	roof.mesh = cone
	roof.material_override = _make_material(C_ROOF)
	roof.position.y = 4.6
	_mesh_root.add_child(roof)

	# Dark gate on the south side + blue rune.
	var door: MeshInstance3D = MeshInstance3D.new()
	var db: BoxMesh = BoxMesh.new()
	db.size = Vector3(1.4, 2.0, 0.5)
	door.mesh = db
	door.material_override = _make_material(Color(0.1, 0.12, 0.2))
	door.position = Vector3(0.0, 1.0, span * 0.42)
	_mesh_root.add_child(door)
	var rune: MeshInstance3D = MeshInstance3D.new()
	var rb: BoxMesh = BoxMesh.new()
	rb.size = Vector3(0.9, 0.5, 0.25)
	rune.mesh = rb
	rune.material_override = _make_material(C_RUNE)
	rune.position = Vector3(0.0, 2.4, span * 0.43)
	_mesh_root.add_child(rune)

	# Four blazing fire bowls at the corners (dark stand + glowing flame).
	var q: float = span * 0.42
	for corner in [Vector2(-q, q), Vector2(q, q), Vector2(-q, -q), Vector2(q, -q)]:
		var stand: MeshInstance3D = MeshInstance3D.new()
		var sc: CylinderMesh = CylinderMesh.new()
		sc.top_radius = 0.28
		sc.bottom_radius = 0.2
		sc.height = 1.0
		stand.mesh = sc
		stand.material_override = _make_material(Color(0.3, 0.2, 0.1))
		stand.position = Vector3(corner.x, 0.5, corner.y)
		_mesh_root.add_child(stand)
		var flame: MeshInstance3D = MeshInstance3D.new()
		var fc: CylinderMesh = CylinderMesh.new()
		fc.top_radius = 0.0
		fc.bottom_radius = 0.38
		fc.height = 0.9
		flame.mesh = fc
		var fmat: StandardMaterial3D = StandardMaterial3D.new()
		fmat.albedo_color = Color(1.0, 0.55, 0.15)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.45, 0.1)
		fmat.emission_energy_multiplier = 1.5
		flame.material_override = fmat
		flame.position = Vector3(corner.x, 1.25, corner.y)
		_mesh_root.add_child(flame)

	_add_flag()
