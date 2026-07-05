class_name TreeResource extends Node3D

## Wild tree with four growth stages (klein -> mittelklein -> mittelgroß ->
## groß). Wood is harvested ONE unit at a time: each harvest drops the tree a
## growth stage (a big tree takes three trips); the last unit removes it.
## Several workers may harvest the same tree at once (as many as it has wood,
## so max 3 on a big tree). Growth and reproduction are driven by the
## TreeManager. Trees do not block the NavGrid (thin obstacles).

const MAX_STAGE: int = 3
## Remaining wood per stage: klein/mittelklein = 1, mittelgroß = 2, groß = 3.
const YIELDS: Array[int] = [1, 1, 2, 3]
const STAGE_SCALES: Array[float] = [0.35, 0.55, 0.8, 1.0]
## Seconds per growth stage.
const GROWTH_TIME: float = 75.0

var stage: int = 0
var growth_timer: float = GROWTH_TIME
## Workers currently harvesting this tree; untyped entries (may be freed).
var claimers: Array = []
## Set once when the last wood is taken — guards late references while the
## node awaits queue_free.
var felled_flag: bool = false


## Wood still in the tree.
func wood_yield() -> int:
	return YIELDS[stage]


## Seconds per single harvest; bigger trees take a bit longer.
func chop_time() -> float:
	return 1.5 + 0.5 * float(stage)


## Takes one unit of wood: the tree drops a growth stage (3 wood -> stage 2
## -> stage 1); the last unit marks it felled (the TreeManager removes it).
func harvest_one() -> int:
	if felled_flag:
		return 0
	if wood_yield() > 1:
		set_stage(stage - 1)
	else:
		felled_flag = true
	return 1


# --- Claims (parallel harvesting) ---------------------------------------------

## A tree supports as many parallel harvesters as it has wood (max 3).
func can_claim() -> bool:
	_prune_claimers()
	return not felled_flag and claimers.size() < wood_yield()


func add_claimer(worker: Object) -> void:
	if not (worker in claimers):
		claimers.append(worker)


func remove_claimer(worker: Object) -> void:
	claimers.erase(worker)


func _prune_claimers() -> void:
	claimers = claimers.filter(func(w: Variant) -> bool:
		return w != null and is_instance_valid(w))


func set_stage(p_stage: int) -> void:
	stage = clampi(p_stage, 0, MAX_STAGE)
	scale = Vector3.ONE * STAGE_SCALES[stage]


## Called by the TreeManager tick; grows one stage when the timer runs out.
func grow_tick(delta: float) -> void:
	if stage >= MAX_STAGE:
		return
	growth_timer -= delta
	if growth_timer <= 0.0:
		growth_timer += GROWTH_TIME
		set_stage(stage + 1)


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
