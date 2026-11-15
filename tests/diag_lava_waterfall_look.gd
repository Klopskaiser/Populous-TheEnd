extends SceneTree

## LAVA AND WATERFALL LOOK — renders both effects to PNG stills (NOT part of the suite).
##
## Needs a real renderer, so run it WITHOUT --headless (a window opens for a few
## seconds and closes itself):
##   godot --path . -s res://tests/diag_lava_waterfall_look.gd -- <output dir>
## Without an output dir the stills land in user://lava_waterfall_look/.
##
## Why: both are shader work (shaders/lava.gdshader, shaders/waterfall.gdshader)
## and a shader error only shows once something is DRAWN — the headless suite
## never sees it. The stills also answer the two user reports of 2026-11-15:
##   lava      - "the terrain clips through the lava sheet" (volcano). The scene
##               pours a LavaSurge over a cone with ridges and bumps, on the real
##               terrain mesh, so any rock poking through would show.
##   waterfall - "not really visible". The island map's rim, once from outside
##               the disc and once from the game camera inside it.
##
## Stills (camera like the game: pitch -55 degrees, fov 75):
##   lava_1_fliessend   the sheet while it advances (hot front)
##   lava_2_erkaltend   the same sheet late, cooling to crust and scorch
##   wasserfall_1_aussen   the rim from outside the disc
##   wasserfall_2_innen    the rim from the game camera, looking outward

const PITCH_DEG: float = 55.0
const SEED: int = 7

var _out_dir: String = "user://lava_waterfall_look"
var _camera: Camera3D = null
var _keep: Array = []   # managers that are not nodes in the tree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.75
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.far = 2000.0
	root.add_child(_camera)
	_camera.make_current()
	_run()


func _run() -> void:
	await process_frame
	await _lava()
	await _waterfall()
	print("Stills in ", ProjectSettings.globalize_path(_out_dir))
	quit()


## A cone with a rim ridge and scattered bumps, the real terrain mesh on it, and
## one LavaSurge poured from the top.
func _lava() -> void:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	for vz in range(48, 81):
		for vx in range(48, 81):
			var d: float = Vector2(float(vx) - 64.0, float(vz) - 64.0).length()
			var h: float = maxf(5.0, 13.0 - 0.75 * d)
			# Ridges and bumps: exactly what a coarse lava mesh would cut through.
			h += 0.45 * sin(float(vx) * 1.9) * cos(float(vz) * 1.7) * clampf(d / 3.0, 0.0, 1.0)
			td.set_vertex_height(vx, vz, h)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	root.add_child(terrain)
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, tribes, tm, wpm)
	_keep = [nav, tribes, tm, wpm, um]
	var surge: LavaSurge = LavaSurge.new()
	surge.setup(Vector3(64, td.get_height(64.0, 64.0), 64), um, td, 9.5)
	surge.lifetime = 14.0
	# The mesh is built by hand instead of through _ready (which plays a sound).
	var holder: Node3D = Node3D.new()
	holder.position = surge.position
	root.add_child(holder)
	surge._mesh = MeshInstance3D.new()
	surge._mesh.mesh = ImmediateMesh.new()
	surge._mesh.material_override = LavaCommon.make_material()
	holder.add_child(surge._mesh)
	for i in range(34):
		surge.tick(0.1)
	surge._rebuild_mesh()
	_aim(Vector3(64.0, 8.0, 65.0), 24.0)
	await _wait(0.4)
	await _shot("lava_1_fliessend")
	for i in range(60):
		surge.tick(0.1)
	surge._rebuild_mesh()
	await _wait(0.3)
	await _shot("lava_2_erkaltend")
	holder.queue_free()
	terrain.queue_free()
	surge.free()
	await process_frame


## The island map: its rim is under water all the way round.
func _waterfall() -> void:
	var td: TerrainData = MapGenerator.create_terrain("island", SEED)
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	root.add_child(terrain)
	var c: float = td.disc_center()
	var r: float = td.rim_radius()
	# From outside the disc: the pivot sits on the southern rim, a little below
	# the waterline, and the camera hangs out in space looking back at it.
	_aim(Vector3(c, TerrainData.SEA_LEVEL - 6.0, c + r), 42.0)
	await _wait(0.5)
	await _shot("wasserfall_1_aussen")
	# The game camera: inside the disc, looking over the northern rim.
	_aim(Vector3(c, TerrainData.SEA_LEVEL, c - r + 6.0), 38.0)
	await _wait(0.4)
	await _shot("wasserfall_2_innen")
	terrain.queue_free()


# --- Camera & capture ----------------------------------------------------------------

## Camera on the game's boom: `boom` metres behind `pivot` at the game's pitch.
func _aim(pivot: Vector3, boom: float) -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	_camera.look_at_from_position(
		pivot + Vector3(0.0, sin(pitch), cos(pitch)) * boom, pivot, Vector3.UP)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(shot_name + ".png"))
