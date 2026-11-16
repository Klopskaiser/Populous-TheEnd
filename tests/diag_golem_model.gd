extends SceneTree

## GOLEM MODEL — renders assets/models/units/golem.glb in fixed poses (NOT part of
## the suite).
##
## Needs a real renderer, so run it WITHOUT --headless (a window opens for a few
## seconds and closes itself):
##   godot --path . -s res://tests/diag_golem_model.gd -- <output dir>
## Without an output dir the stills land in user://golem_model/.
##
## The model and its clips come from the neighbouring project
## (D:\game\gymnastikschuh\golem_export.mjs); after re-exporting run
## `--headless --import` once, then this script. It prints what Godot made of the
## file (height, nodes, clips) and writes five stills: every pose of POSES once
## from the game camera (pitch -55 degrees, "spiel_N") and once straight from the
## side (orthographic, the figure looks to the right, "seite_N"), four poses per
## still in the order of POSES, plus one close-up ("nah").
##
## To follow one movement frame by frame pass a second argument, e.g.
##   ... -- <output dir> kick:0.3,kick:0.4,kick:0.5,kick:0.6
## — then only side-view film strips of exactly these poses are written.
##
## Another model (the demon golem) and its build: third argument = the file under
## assets/models/units/, fourth = how much WIDER than tall the game shows it
## (golem 1.11, demon golem 1.39 — DemonGolem.model_scale), e.g.
##   ... -- <output dir> "" golem_demon.glb 1.39
##
## The "Flag" mesh gets a tribe-coloured material like Golem._refresh_flag_color
## does, so the stills also show how much tribe colour is visible.

const MODEL: String = "res://assets/models/units/golem.glb"
## [clip, time in seconds]
const POSES: Array = [
	[&"idle", 0.0], [&"walk", 0.25], [&"kick", 0.3], [&"kick", 0.5],
	[&"slam", 0.45], [&"slam", 0.8], [&"death", 0.7], [&"death", 1.4],
]
const PER_SHEET: int = 4
const SPACING: float = 4.4
const PITCH_DEG: float = 55.0
const TRIBE_COLOR: Color = Color(0.85, 0.15, 0.12)

var _out_dir: String = "user://golem_model"
## Optional second argument "clip:time,clip:time,...": see _strip.
var _strip_spec: String = ""
## Optional third and fourth argument: the model file and its width factor.
var _model_path: String = MODEL
var _wide: float = 1.0
var _stage: Node3D = null
var _camera: Camera3D = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_strip_spec = args[1]
	if args.size() > 2 and args[2] != "":
		_model_path = args[2] if args[2].begins_with("res://") else "res://assets/models/units/" + args[2]
	if args.size() > 3 and args[3].is_valid_float():
		_wide = float(args[3])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_build_world()
	_run()


## Film strip instead of the standard sheets: side view of the poses named in the
## second argument, six per still ("streifen_1.png", ...).
func _strip(scene: PackedScene) -> void:
	var poses: Array = []
	for part in _strip_spec.split(","):
		var kv: PackedStringArray = part.split(":")
		poses.append([StringName(kv[0]), float(kv[1])])
	var sheet: int = 0
	var first: int = 0
	while first < poses.size():
		sheet += 1
		var row: Array = poses.slice(first, first + 6)
		first += 6
		_place(scene, row, Vector3(0.0, 0.0, 3.7))
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 12.5
		var pivot: Vector3 = Vector3(0.0, 2.6, 3.7 * 2.5 + 0.5)
		_camera.look_at_from_position(pivot + Vector3(-40.0, 0.0, 0.0), pivot, Vector3.UP)
		await _settle()
		await _shot("streifen_%d" % sheet)


func _run() -> void:
	await process_frame   # the root is only inside the tree from the first frame on
	var scene: PackedScene = load(_model_path) as PackedScene
	if scene == null:
		push_error("golem.glb is not imported — run --headless --import first")
		quit(1)
		return
	await _report(scene)
	if _strip_spec != "":
		await _strip(scene)
		print("Stills in ", ProjectSettings.globalize_path(_out_dir))
		quit()
		return
	var sheet: int = 0
	var first: int = 0
	while first < POSES.size():
		sheet += 1
		var poses: Array = POSES.slice(first, first + PER_SHEET)
		first += PER_SHEET
		# Game camera: the figures stand side by side and look at the camera.
		_place(scene, poses, Vector3(SPACING, 0.0, 0.0))
		var span: float = SPACING * float(poses.size() - 1)
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		var pitch: float = deg_to_rad(PITCH_DEG)
		var pivot: Vector3 = Vector3(span * 0.5, 1.6, 0.0)
		_camera.look_at_from_position(pivot + Vector3(0.0, sin(pitch), cos(pitch)) * 13.0,
			pivot, Vector3.UP)
		await _settle()
		await _shot("spiel_%d" % sheet)
		# Side view: the figures stand in a row along z and look to the right.
		_place(scene, poses, Vector3(0.0, 0.0, SPACING))
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 10.0
		pivot = Vector3(0.0, 2.6, span * 0.5 + 0.6)
		_camera.look_at_from_position(pivot + Vector3(-40.0, 0.0, 0.0), pivot, Vector3.UP)
		await _settle()
		await _shot("seite_%d" % sheet)
	# Close-up: front quarter, back quarter and the slam from the front quarter.
	_place(scene, [[&"idle", 0.0], [&"idle", 0.0], [&"slam", 0.8], [&"kick", 0.5]], Vector3(3.6, 0.0, 0.0))
	var turns: Array[float] = [0.6, 3.7, 0.9, -0.9]
	for i in range(_stage.get_child_count()):
		(_stage.get_child(i) as Node3D).rotation.y = turns[i]
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 40.0
	_camera.look_at_from_position(Vector3(5.4, 3.6, 13.5), Vector3(5.4, 1.9, 0.0), Vector3.UP)
	await _settle()
	await _shot("nah")
	print("Stills in ", ProjectSettings.globalize_path(_out_dir))
	quit()


## What Godot made of the file: size, mesh nodes, clips.
func _report(scene: PackedScene) -> void:
	var model: Node3D = scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var lo: float = INF
	var hi: float = -INF
	var names: PackedStringArray = PackedStringArray()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
		names.append("%s (%d surfaces)" % [mi.name, mi.mesh.get_surface_count()])
	print("meshes: ", ", ".join(names))
	print("rest height: %.2f m (bottom %.3f, top %.3f)" % [hi - lo, lo, hi])
	print("Flag found: ", model.find_child("Flag", true, false) is MeshInstance3D)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("bones: ", skeleton.get_bone_count())
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for clip in player.get_animation_list():
		print("clip %s: %.2f s" % [clip, player.get_animation(clip).length])
	model.queue_free()


func _place(scene: PackedScene, poses: Array, step: Vector3) -> void:
	if _stage != null:
		_stage.queue_free()
	_stage = Node3D.new()
	root.add_child(_stage)
	for i in range(poses.size()):
		var model: Node3D = scene.instantiate() as Node3D
		model.position = step * float(i)
		model.scale = Vector3(_wide, 1.0, _wide)
		_stage.add_child(model)
		var flag: MeshInstance3D = model.find_child("Flag", true, false) as MeshInstance3D
		if flag != null:
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = TRIBE_COLOR
			mat.roughness = 1.0
			mat.emission_enabled = true
			mat.emission = TRIBE_COLOR
			mat.emission_energy_multiplier = 0.6
			flag.material_override = mat
		var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.play(poses[i][0])
		player.seek(float(poses[i][1]), true)
		player.pause()


## Ground, light and sky like scenes/main.tscn.
func _build_world() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.75
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	root.add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.46, 0.22)
	mat.roughness = 1.0
	ground.material_override = mat
	root.add_child(ground)
	_camera = Camera3D.new()
	_camera.far = 2000.0
	root.add_child(_camera)
	_camera.make_current()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out_dir.path_join(shot_name + ".png"))
