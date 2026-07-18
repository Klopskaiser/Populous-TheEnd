class_name BuildingDamageBurst extends Node3D

## Short burst of fragments that fall off a building when it reaches a new
## destruction stage ("bits of texture flake off"). Pure visual, ticked via the
## UnitManager projectile list; visuals are built in _ready only (headless-safe).
## Uses an optional flake texture (assets/textures/fx/building_flake.png,
## alpha-cutout billboards); falls back to small tinted box fragments.

const PIECE_COUNT: int = 8
const LIFETIME: float = 1.2
const GRAVITY: float = 14.0
const LAUNCH_SPEED: float = 2.4
const LAUNCH_UP: float = 3.2

var done: bool = false
var terrain_data: TerrainData = null

## Per piece: {offset: Vector3 (local), velocity: Vector3, spin: Vector3}.
var _pieces: Array[Dictionary] = []
var _piece_nodes: Array[MeshInstance3D] = []
var _life: float = LIFETIME
var _extent: float = 2.0
var _tint: Color = Color(0.5, 0.4, 0.28)


## Deterministic fan-out from the building centre near its upper edge; `extent`
## scales launch offsets/speeds with the footprint size.
func setup(at: Vector3, extent: float, p_terrain_data: TerrainData, tint: Color) -> void:
	position = at
	terrain_data = p_terrain_data
	_extent = maxf(extent, 1.0)
	_tint = tint
	for i in range(PIECE_COUNT):
		var angle: float = TAU * float(i) / float(PIECE_COUNT) + 0.35
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		_pieces.append({
			"offset": out * _extent * 0.45 + Vector3(0.0, 1.6 + 0.4 * float(i % 3), 0.0),
			"velocity": out * (LAUNCH_SPEED + 0.3 * float(i % 4)) \
				+ Vector3.UP * (LAUNCH_UP - 0.4 * float(i % 3)),
			"spin": Vector3(2.1, 1.4, 1.8) * (1.0 + 0.2 * float(i % 5)),
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
		if off.y <= ground_base + 0.1 and vel.y < 0.0:
			off.y = ground_base + 0.1
			vel = Vector3.ZERO   # piece has landed and lies still
		p.velocity = vel
		p.offset = off
		if i < _piece_nodes.size():
			_piece_nodes[i].position = off
			if vel != Vector3.ZERO:
				_piece_nodes[i].rotation += p.spin * delta


func _ready() -> void:
	var flake: Texture2D = AssetLibrary.texture("textures/fx/building_flake.png")
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.roughness = 1.0
	if flake != null:
		mat.albedo_texture = flake
		mat.albedo_color = _tint
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		mat.albedo_color = _tint
	for i in range(_pieces.size()):
		var piece: MeshInstance3D = MeshInstance3D.new()
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s: float = 0.22 + 0.12 * float(i % 3)
		if flake != null:
			var quad: QuadMesh = QuadMesh.new()
			quad.size = Vector2(s * 1.6, s * 1.6)
			piece.mesh = quad
		else:
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(s * 1.3, s, s)
			piece.mesh = box
		piece.material_override = mat
		piece.position = _pieces[i].offset
		add_child(piece)
		_piece_nodes.append(piece)
