class_name Temple extends TrainingBuilding

## Temple (Tempel): trains braves into preachers (15 wood, 5 s — longest).
## Phase 7i: twice the footprint (6x6). Placeholder mesh evokes the reference
## image: a domed clay hut with a wide round reed roof, a blue-gold conical
## finial on top, and a small arched porch. Holy/peaceful theme.

const WOOD_COST: int = Balance.TEMPLE_WOOD_COST
const FOOTPRINT: Vector2i = Vector2i(6, 6)
const TRAINING_TIME: float = Balance.TEMPLE_TRAINING_TIME
const PREACHER_SCENE: PackedScene = preload("res://scenes/units/preacher.tscn")

const C_WALL: Color = Color(0.82, 0.78, 0.68)
const C_ROOF: Color = Color(0.45, 0.28, 0.13)
const C_GOLD: Color = Color(0.85, 0.68, 0.3)
const C_BLUE: Color = Color(0.35, 0.4, 0.85)


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.TEMPLE_HP
	health = max_health
	produces = PREACHER_SCENE
	training_time = TRAINING_TIME


func display_name() -> String:
	return "Tempel"


func asset_kind() -> StringName:
	return &"temple"


func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(footprint.x)

	# Domed clay hut (light plaster dome).
	var dome: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = span * 0.36
	sphere.height = span * 0.5
	dome.mesh = sphere
	dome.material_override = _make_material(C_WALL)
	dome.position.y = 0.9
	_mesh_root.add_child(dome)

	# Round reed roof over the dome — overlaps the dome but no longer far past it.
	var roof: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = span * 0.1
	cone.bottom_radius = span * 0.42
	cone.height = 1.1
	roof.mesh = cone
	roof.material_override = _make_material(C_ROOF)
	roof.position.y = 2.0
	_mesh_root.add_child(roof)

	# Blue-gold conical finial on top.
	var finial_base: MeshInstance3D = MeshInstance3D.new()
	var fb: CylinderMesh = CylinderMesh.new()
	fb.top_radius = 0.2
	fb.bottom_radius = 0.28
	fb.height = 0.4
	finial_base.mesh = fb
	finial_base.material_override = _make_material(C_BLUE)
	finial_base.position.y = 2.75
	_mesh_root.add_child(finial_base)
	var finial: MeshInstance3D = MeshInstance3D.new()
	var fc: CylinderMesh = CylinderMesh.new()
	fc.top_radius = 0.0
	fc.bottom_radius = 0.24
	fc.height = 0.7
	finial.mesh = fc
	finial.material_override = _make_material(C_GOLD)
	finial.position.y = 3.3
	_mesh_root.add_child(finial)

	# Small arched porch on the south side + blue figure glyph.
	var porch: MeshInstance3D = MeshInstance3D.new()
	var pb: BoxMesh = BoxMesh.new()
	pb.size = Vector3(1.0, 1.2, 0.6)
	porch.mesh = pb
	porch.material_override = _make_material(C_WALL)
	porch.position = Vector3(0.0, 0.6, span * 0.4)
	_mesh_root.add_child(porch)
	var glyph: MeshInstance3D = MeshInstance3D.new()
	var gb: BoxMesh = BoxMesh.new()
	gb.size = Vector3(0.4, 0.7, 0.15)
	glyph.mesh = gb
	glyph.material_override = _make_material(C_BLUE)
	glyph.position = Vector3(0.0, 0.7, span * 0.42)
	_mesh_root.add_child(glyph)

	_add_flag()
