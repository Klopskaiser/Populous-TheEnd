extends SceneTree

## CONSTRUCTION LOOK — renders the construction stages to PNG stills (NOT part of
## the suite). User spec 2026-11-23: a site with no wood built in shows only a
## white ground plan with an arrow at the door; from the first built-in wood a
## scaffold stands (three height tiers); in the last build stage the finished
## building stands inside it.
##
## Needs a real renderer, so run it WITHOUT --headless:
##   godot --path . -s res://tests/diag_construction_look.gd -- <output dir>
## Without an output dir the stills land in user://construction_look/.
##
## Stills (camera like the game: pitch -55 degrees):
##   bau_1_huetten      six huts: plot, tier 1, tier 2, tier 3, last stage, finished
##   bau_2_feuertempel  the same for the 8x8 fire temple
##   bau_3_grundriss    close-up of bare plots on uneven ground (door S / E / N)
##   bau_4_geruest      close-up of scaffold tiers 1-3 on a workshop row

const PITCH_DEG: float = 55.0
const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const FW_SCENE: PackedScene = preload("res://scenes/buildings/firewarrior_camp.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
## build_progress per column: plot, tier 1, tier 2, tier 3, last stage, finished.
const STAGES: Array[float] = [0.0, 0.1, 0.35, 0.6, 0.85, 1.0]

var _out_dir: String = "user://construction_look"
var _camera: Camera3D = null
var _keep: Array = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.6, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.7
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.far = 2000.0
	root.add_child(_camera)
	_camera.make_current()
	_run()


func _run() -> void:
	await process_frame
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			# Gentle bumps: a bare plot must lie on the ground, not float above it.
			td.set_vertex_height(vx, vz, 5.0 + 0.35 * sin(float(vx) * 0.7) * cos(float(vz) * 0.55))
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], null, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	root.add_child(bm)
	bm.set_physics_process(false)
	_keep = [nav, tribe, wpm, um]
	# Row A: huts. Row B: fire temples. Row C: bare plots, doors S / E / N.
	# Row D: workshops, scaffold tiers 1-3.
	for i in range(STAGES.size()):
		_staged(bm, HUT_SCENE, tribe, Vector2i(20 + i * 7, 20), 0, STAGES[i])
		_staged(bm, FW_SCENE, tribe, Vector2i(20 + i * 12, 34), 0, STAGES[i])
	_staged(bm, HUT_SCENE, tribe, Vector2i(30, 60), 0, 0.0)
	_staged(bm, CAMP_SCENE, tribe, Vector2i(38, 60), 1, 0.0)
	_staged(bm, HUT_SCENE, tribe, Vector2i(46, 60), 2, 0.0)
	for i in range(3):
		_staged(bm, WORKSHOP_SCENE, tribe, Vector2i(30 + i * 11, 76), 0, STAGES[i + 1])
	var terrain: Terrain = Terrain.new()
	terrain.build(td)
	root.add_child(terrain)
	_aim(Vector3(39.0, 5.0, 18.0), 26.0)
	await _wait(0.5)
	await _shot("bau_1_huetten")
	_aim(Vector3(54.0, 5.0, 38.0), 52.0)
	await _wait(0.3)
	await _shot("bau_2_feuertempel")
	_aim(Vector3(40.0, 5.0, 62.0), 18.0)
	await _wait(0.3)
	await _shot("bau_3_grundriss")
	_aim(Vector3(45.0, 5.0, 78.0), 24.0)
	await _wait(0.3)
	await _shot("bau_4_geruest")
	print("Stills in ", ProjectSettings.globalize_path(_out_dir))
	quit()


## Places a site and puts it at `progress` (0 = bare plot, 1 = finished).
func _staged(bm: BuildingManager, scene: PackedScene, tribe: Tribe, cell: Vector2i,
		orientation: int, progress: float) -> void:
	var b: Building = bm.place(scene, tribe, cell, orientation, false)
	if progress <= 0.0:
		return
	for c in b._flatten_remaining.keys():
		b.work_flatten(c, 100.0)
	b._flush_deformation()
	b.wood_delivered = b.wood_cost
	if progress >= 1.0:
		b.finish_construction()
		return
	b.add_build_progress(progress)


func _aim(pivot: Vector3, boom: float) -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	_camera.look_at_from_position(
		pivot + Vector3(0.0, sin(pitch), cos(pitch)) * boom, pivot, Vector3.UP)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(shot_name + ".png"))
