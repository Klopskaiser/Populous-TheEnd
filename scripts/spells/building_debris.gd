class_name BuildingDebris extends Node3D

## Burst visual for a building whose foundation broke (terrain-integrity
## rule): the model "flies apart" as a handful of box fragments on ballistic
## arcs that tumble, hit the ground and linger briefly. Pure visual — the
## building itself is already destroyed. Ticked via the UnitManager
## projectile list; visuals are built in _ready only (headless-safe).

const PIECE_COUNT: int = 10
const LIFETIME: float = 2.5
const GRAVITY: float = 14.0
const LAUNCH_SPEED: float = 4.5
const LAUNCH_UP: float = 6.0

var done: bool = false
var terrain_data: TerrainData = null

## Per piece: {offset: Vector3 (local), velocity: Vector3, spin: Vector3}.
var _pieces: Array[Dictionary] = []
var _piece_nodes: Array[MeshInstance3D] = []
var _life: float = LIFETIME
var _extent: float = 2.0


## Deterministic fragment fan-out from the building centre; `extent` scales
## launch offsets/speeds with the footprint size.
func setup(at: Vector3, extent: float, p_terrain_data: TerrainData) -> void:
	position = at
	terrain_data = p_terrain_data
	_extent = maxf(extent, 1.0)
	for i in range(PIECE_COUNT):
		var angle: float = TAU * float(i) / float(PIECE_COUNT) + 0.5
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		_pieces.append({
			"offset": out * _extent * 0.3 + Vector3(0.0, 0.8 + 0.2 * float(i % 3), 0.0),
			"velocity": out * (LAUNCH_SPEED + 0.4 * float(i % 4)) \
				+ Vector3.UP * (LAUNCH_UP - 0.5 * float(i % 3)),
			"spin": Vector3(1.7, 2.3, 0.9) * (1.0 + 0.2 * float(i % 5)),
		})


func tick(delta: float) -> void:
	if done:
		return
	_life -= delta
	if _life <= 0.0:
		done = true
		return
	var ground_base: float = 0.0
	for i in range(_pieces.size()):
		var p: Dictionary = _pieces[i]
		var vel: Vector3 = p.velocity
		var off: Vector3 = p.offset
		vel.y -= GRAVITY * delta
		off += vel * delta
		var world: Vector3 = position + Vector3(off.x, 0.0, off.z)
		if terrain_data != null:
			ground_base = terrain_data.get_height(world.x, world.z) - position.y
		if off.y <= ground_base + 0.15 and vel.y < 0.0:
			off.y = ground_base + 0.15
			vel = Vector3.ZERO   # piece has landed and lies still
		p.velocity = vel
		p.offset = off
		if i < _piece_nodes.size():
			_piece_nodes[i].position = off
			if vel != Vector3.ZERO:
				_piece_nodes[i].rotation += p.spin * delta


func _ready() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.33, 0.2)
	mat.roughness = 1.0
	for i in range(_pieces.size()):
		var piece: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var s: float = 0.35 + 0.2 * float(i % 3)
		box.size = Vector3(s * 1.4, s, s)
		piece.mesh = box
		piece.material_override = mat
		piece.position = _pieces[i].offset
		add_child(piece)
		_piece_nodes.append(piece)
