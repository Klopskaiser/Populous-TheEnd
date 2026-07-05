class_name Hut extends Building

## Hut: houses population and spawns new Braves over time. Deliberate
## deviation from the original game: one hut provides room for 100 population
## (see CLAUDE.md par. 5).

const WOOD_COST: int = 20
const FOOTPRINT: Vector2i = Vector2i(2, 2)
const CAPACITY: int = 100
const SPAWN_INTERVAL: float = 10.0   # seconds per new brave

const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")

var spawn_timer: float = SPAWN_INTERVAL


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = 300
	health = 300


func display_name() -> String:
	return "Hütte"


func housing_capacity() -> int:
	return 0 if under_construction else CAPACITY


## Spawns Braves while the tribe is below its housing capacity. The timer only
## runs while there is room, so the first brave after reaching a new capacity
## takes a full interval.
func _tick_active(delta: float) -> void:
	if tribe == null or unit_manager == null:
		return
	if tribe.population() >= tribe.housing_capacity():
		spawn_timer = SPAWN_INTERVAL
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer += SPAWN_INTERVAL
		_spawn_brave()


func _spawn_brave() -> void:
	var pos: Vector3 = edge_spawn_position()
	var brave: Unit = unit_manager.spawn_unit(BRAVE_SCENE, tribe_id, pos)
	if brave != null and rally_point != Vector3.ZERO:
		brave.order_move(rally_point)


func _create_visuals() -> void:
	super._create_visuals()
	var roof: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(float(footprint.x) * 0.9, 1.6, float(footprint.y) * 0.9)
	roof.mesh = prism
	roof.material_override = _make_material(Color(0.45, 0.3, 0.15))
	roof.position.y = 0.8
	_mesh_root.add_child(roof)
	_add_flag()
