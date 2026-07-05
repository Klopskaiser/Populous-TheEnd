class_name TreeResource extends Node3D

## Wild tree: the only physical resource source. Braves chop it via harvest();
## when it is empty it emits `depleted` and the TreeManager deregisters it.
## Trees do not block the NavGrid (thin obstacles), so no cells are reserved.

signal depleted(tree: TreeResource)

var wood_remaining: int = 40


## Takes up to `amount` wood; returns how much was actually taken. Emits
## `depleted` once when the tree runs out. Callers must not touch the tree
## after a depleting harvest (the manager may free it).
func harvest(amount: int) -> int:
	if wood_remaining <= 0:
		return 0
	var taken: int = mini(amount, wood_remaining)
	wood_remaining -= taken
	if wood_remaining <= 0:
		depleted.emit(self)
	return taken


func _ready() -> void:
	_create_visuals()
	_create_click_body()


func _create_visuals() -> void:
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	trunk.mesh = cyl
	var trunk_mat: StandardMaterial3D = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.27, 0.15)
	trunk.material_override = trunk_mat
	trunk.position.y = 0.5
	add_child(trunk)

	var crown: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 1.8
	crown.mesh = cone
	var crown_mat: StandardMaterial3D = StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.15, 0.4, 0.16)
	crown.material_override = crown_mat
	crown.position.y = 1.9
	add_child(crown)


## StaticBody3D on layer 3 (value 4) so right-clicks can target the tree.
func _create_click_body() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("tree_resource", self)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.2, 2.8, 1.2)
	shape.shape = box
	shape.position.y = 1.4
	body.add_child(shape)
	add_child(body)
