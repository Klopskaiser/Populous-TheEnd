class_name WoodPile extends Node3D

## Wood pile lying on the ground (there is no wood storage building): braves
## drop chopped wood here, construction sites absorb nearby piles. Holds up to
## MAX_AMOUNT wood; empty piles are removed by the WoodPileManager.

const MAX_AMOUNT: int = 5

## Local positions of the stacked log boxes (one per wood unit).
const LOG_OFFSETS: Array[Vector3] = [
	Vector3(-0.2, 0.15, -0.2), Vector3(0.2, 0.15, -0.2),
	Vector3(-0.2, 0.15, 0.2), Vector3(0.2, 0.15, 0.2),
	Vector3(0.0, 0.45, 0.0),
]

var amount: int = 0


func space_left() -> int:
	return MAX_AMOUNT - amount


func set_amount(value: int) -> void:
	amount = clampi(value, 0, MAX_AMOUNT)
	_update_visual()


func _ready() -> void:
	_update_visual()


## One small log box per wood unit, stacked 2x2 + top.
func _update_visual() -> void:
	if not is_inside_tree():
		return
	var stack: Node3D = get_node_or_null("Stack") as Node3D
	if stack != null:
		stack.free()
	stack = Node3D.new()
	stack.name = "Stack"
	add_child(stack)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.34, 0.18)
	for i in range(amount):
		var log_box: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.55, 0.28, 0.28)
		log_box.mesh = box
		log_box.material_override = mat
		log_box.position = LOG_OFFSETS[i]
		stack.add_child(log_box)
