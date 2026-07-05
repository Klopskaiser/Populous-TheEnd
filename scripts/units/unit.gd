class_name Unit extends Node3D

## Base class for all units (Brave, Warrior, Firewarrior, Preacher, Shaman).
##
## No physics body: movement walks the NavGrid path via move_toward on the XZ
## plane, Y is snapped from TerrainData every tick. Core logic lives in
## tick(delta) (called from _physics_process) so tests can drive it manually
## with artificial deltas, outside the scene tree. Uses local `position`
## (units are direct children of UnitManager at the origin, so local == global
## and it also works outside the tree).

## Later phases fill in the behaviour for GATHER/PRAY/BUILD/ATTACK/TRAIN/
## PANIC/CAST/THROWN.
enum State {IDLE, MOVE, GATHER, PRAY, BUILD, ATTACK, TRAIN, PANIC, CAST, THROWN, DEAD}

signal died(unit: Unit)
signal state_changed(unit: Unit, new_state: State)

const TRIBE_COLORS: Array[Color] = [
	Color(0.35, 0.55, 1.0),   # 0 = player (blue)
	Color(1.0, 0.3, 0.25),    # 1 = AI (red)
	Color(1.0, 0.9, 0.35),
	Color(0.4, 0.9, 0.45),
]

const ARRIVE_EPS: float = 0.05       # metres: waypoint counts as reached
const SPRITE_PIXEL_SIZE: float = 0.06

var tribe_id: int = 0
var max_health: int = 100
var health: int = 100
var speed: float = 4.0
var state: State = State.IDLE
var waypoint_queue: Array[Vector3] = []
var patrol: bool = false

## Injected by UnitManager.spawn_unit() (or directly by tests).
var terrain_data: TerrainData = null
var nav_grid: NavGrid = null

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _sprite: AnimatedSprite3D = null
var _selection_ring: MeshInstance3D = null


## Silhouette key for PlaceholderSprites; overridden by subclasses.
func unit_kind() -> StringName:
	return &"unit"


func _ready() -> void:
	_sprite = get_node_or_null("Sprite") as AnimatedSprite3D
	if _sprite != null:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sprite.pixel_size = SPRITE_PIXEL_SIZE
		# Feet at the node origin.
		_sprite.position.y = PlaceholderSprites.H * SPRITE_PIXEL_SIZE * 0.5
		_sprite.modulate = TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()]
		if _sprite.sprite_frames == null:
			_sprite.sprite_frames = PlaceholderSprites.make_frames(unit_kind())
		_update_animation()


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Core logic (testable without scene tree) ---------------------------------

func tick(delta: float) -> void:
	match state:
		State.MOVE:
			_tick_move(delta)
		_:
			pass


func _tick_move(delta: float) -> void:
	if _path_index >= _path.size():
		_on_path_finished()
		return
	var target: Vector3 = _path[_path_index]
	var flat_pos: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(target.x, target.z)
	var next: Vector2 = flat_pos.move_toward(flat_target, speed * delta)
	position.x = next.x
	position.z = next.y
	_snap_to_ground()
	if next.distance_to(flat_target) <= ARRIVE_EPS:
		_path_index += 1


func _snap_to_ground() -> void:
	if terrain_data != null:
		position.y = terrain_data.get_height(position.x, position.z)


func _on_path_finished() -> void:
	if waypoint_queue.is_empty():
		_set_state(State.IDLE)
		return
	if patrol:
		# Rotate the queue: the reached waypoint goes to the back.
		waypoint_queue.append(waypoint_queue.pop_front())
		_start_path_to(waypoint_queue[0])
	else:
		waypoint_queue.pop_front()
		if waypoint_queue.is_empty():
			_set_state(State.IDLE)
		else:
			_start_path_to(waypoint_queue[0])


# --- Orders --------------------------------------------------------------------

## Move order. queue_up appends the target as an additional waypoint
## (Shift+right-click), otherwise the current route is replaced.
func order_move(target: Vector3, queue_up: bool = false) -> void:
	if not queue_up:
		waypoint_queue.clear()
		waypoint_queue.append(target)
		_start_path_to(target)
		return
	waypoint_queue.append(target)
	if state != State.MOVE:
		_start_path_to(waypoint_queue[0])


func _start_path_to(target: Vector3) -> void:
	var path: PackedVector3Array
	if nav_grid != null:
		path = nav_grid.find_path(position, target)
	else:
		path = PackedVector3Array([target])
	if path.is_empty():
		# Unreachable: drop the waypoint and stop.
		if not waypoint_queue.is_empty():
			waypoint_queue.pop_front()
		_set_state(State.IDLE)
		return
	set_path(path)


## Directly injects a path (used by tests and by order handling).
func set_path(path: PackedVector3Array) -> void:
	_path = path
	_path_index = 0
	if _path.is_empty():
		_set_state(State.IDLE)
	else:
		_set_state(State.MOVE)


# --- Damage (scaffold; combat comes in phase 4) --------------------------------

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0:
		health = 0
		_set_state(State.DEAD)
		died.emit(self)


# --- State & visuals -------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(self, new_state)
	_update_animation()


func _update_animation() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var anim: StringName
	match state:
		State.MOVE, State.PANIC:
			anim = &"walk"
		State.ATTACK:
			anim = &"attack"
		State.CAST:
			anim = &"cast"
		_:
			anim = &"idle"
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)


## Shows/hides the selection ring (created lazily, in-game only).
func set_selected(selected: bool) -> void:
	if selected and _selection_ring == null and is_inside_tree():
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.45
		torus.outer_radius = 0.6
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.albedo_color = Color(1.0, 0.95, 0.3)
		torus.material = mat
		_selection_ring.mesh = torus
		_selection_ring.position.y = 0.15
		add_child(_selection_ring)
	if _selection_ring != null:
		_selection_ring.visible = selected
