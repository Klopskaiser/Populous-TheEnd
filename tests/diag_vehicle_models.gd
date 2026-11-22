extends SceneTree

## VEHICLE MODELS — renders the catapult and the fire ram with their moving parts
## (NOT part of the suite).
##
## Needs a real renderer, so run it WITHOUT --headless (a window opens for a few
## seconds and closes itself):
##   godot --path . -s res://tests/diag_vehicle_models.gd -- <output dir>
## Without an output dir the stills land in user://vehicle_models/.
##
## The models come from tools/fahrzeuge/fahrzeuge_bauen.py (see LIESMICH.md
## there); after rebuilding run `--headless --import` once, then this script.
## It instantiates the REAL unit scenes, so what moves here is what moves in the
## game: SiegeEngine._tick_visual swings "Arm" / hides "Stone" / turns "Winch",
## CrewedVehicle._spin_wheels rolls every "Wheel*".
##
## Stills:
##   1_spiel          both vehicles from the game camera (pitch -55 degrees), a
##                    1.44 m post next to them for scale (height of a unit sprite)
##   2_nah            the same, close and flat
##   3_wurf           the throwing arm 0 / 0.06 / 0.12 / 0.2 / 0.6 / 0.9 s after the shot
##   4_raeder_katapult, 5_raeder_ramme   0 / 0.15 / 0.3 / 0.45 m driven
##   6_flug           the stone as the projectile: one shot at seven ages along its arc
## messwerte.txt: the wheels found (radius, side) and their angle after 1 m
## forward and after a quarter turn on the spot — next to the expected values.

const SIEGE_SCENE: PackedScene = preload("res://scenes/units/siege_engine.tscn")
const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")
const TRIBE_COLOR: Color = Color(0.85, 0.15, 0.12)
const ARM_TIMES: Array[float] = [0.0, 0.06, 0.12, 0.2, 0.6, 0.9]
const DRIVEN: Array[float] = [0.0, 0.15, 0.3, 0.45]
const SHOT_AGES: Array[float] = [0.05, 0.1, 0.15, 0.25, 0.4, 0.6, 0.85]

var _out_dir: String = "user://vehicle_models"
var _stage: Node3D = null
var _camera: Camera3D = null
var _report: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	root.size = Vector2i(1600, 900)
	_build_world()
	_run()


func _run() -> void:
	# Before the first frame the tree does not send _ready yet: a vehicle added
	# now would build its model only after this script had posed it.
	await process_frame
	# 1 + 2: both vehicles at rest.
	_reset_stage()
	_add(SIEGE_SCENE, Vector3(-1.6, 0.0, 0.0), Vector3(0.6, 0.0, 1.0))
	_add(FIRE_RAM_SCENE, Vector3(1.6, 0.0, 0.0), Vector3(0.6, 0.0, 1.0))
	_add_post(Vector3(0.0, 0.0, 0.3))
	_aim(Vector3(0.0, 0.5, 0.0), 6.5, 55.0)
	await _wait(0.4)
	await _shot("1_spiel")
	_aim(Vector3(0.0, 0.6, 0.0), 4.6, 22.0)
	await _wait(0.1)
	await _shot("2_nah")

	# 3: the shot, frame by frame (side view, the catapults look to the right).
	_reset_stage()
	for i in range(ARM_TIMES.size()):
		var engine: SiegeEngine = _add(SIEGE_SCENE,
			Vector3((float(i) - 2.5) * 3.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)) as SiegeEngine
		if ARM_TIMES[i] > 0.0:
			engine._arm_time = ARM_TIMES[i] - 0.001
			engine._tick_visual(0.001)
	_aim(Vector3(0.0, 0.9, 0.0), 11.5, 14.0)
	await _wait(0.1)
	await _shot("3_wurf")

	# 4 + 5: rolling wheels.
	for pair in [[SIEGE_SCENE, "4_raeder_katapult"], [FIRE_RAM_SCENE, "5_raeder_ramme"]]:
		_reset_stage()
		for i in range(DRIVEN.size()):
			var at: Vector3 = Vector3((float(i) - 1.5) * 3.0, 0.0, 0.0)
			var vehicle: CrewedVehicle = _add(pair[0], at - Vector3(DRIVEN[i], 0.0, 0.0),
				Vector3(1.0, 0.0, 0.0))
			_drive(vehicle, Vector3(DRIVEN[i], 0.0, 0.0))
		_aim(Vector3(0.0, 0.5, 0.0), 8.0, 12.0)
		await _wait(0.1)
		await _shot(pair[1])

	# 6: the stone as the projectile — one catapult, the same shot at six ages
	# (the arm is shown as it stands 0.2 s after the shot).
	_reset_stage()
	var shooter: SiegeEngine = _add(SIEGE_SCENE, Vector3(-5.5, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0)) as SiegeEngine
	for age in SHOT_AGES:
		var shot: SiegeShot = SiegeShot.new()
		shot.setup(0, shooter.position, Vector3(6.5, 0.0, 0.0), shooter, null, null, null)
		shooter._dress_shot(shot)
		_stage.add_child(shot)
		var steps: int = int(round(age * 60.0))
		for i in range(steps):
			shot.tick(1.0 / 60.0)
		_report.append("Stein %.2f s nach dem Schuss: sichtbar %s, Bahn (%.2f %.2f), Stein (%.2f %.2f)" % [
			age, str(shot._ball.visible), shot.position.x, shot.position.y,
			shot._ball.global_position.x, shot._ball.global_position.y])
	shooter._arm_time = 0.2 - 0.001
	shooter._tick_visual(0.001)
	_aim(Vector3(0.0, 3.2, 0.0), 21.0, 6.0)
	await _wait(0.1)
	await _shot("6_flug")

	# Numbers: what the wheels did.
	for pair in [[SIEGE_SCENE, "Katapult"], [FIRE_RAM_SCENE, "Feuerramme"]]:
		_reset_stage()
		var vehicle: CrewedVehicle = _add(pair[0], Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
		_report.append("%s: %d Raeder" % [pair[1], vehicle._wheels.size()])
		_drive(vehicle, Vector3(0.0, 0.0, 1.0))
		for i in range(vehicle._wheels.size()):
			_report.append("  %-9s Radius %.3f m, Seite %+.3f m, nach 1 m vorwaerts %+.3f rad (erwartet %+.3f)" % [
				vehicle._wheels[i].name, vehicle._wheel_radius[i], vehicle._wheel_side[i],
				vehicle._wheels[i].rotation.x, wrapf(1.0 / vehicle._wheel_radius[i], -PI, PI)])
		for i in range(vehicle._wheels.size()):
			vehicle._wheels[i].rotation.x = 0.0
		_turn(vehicle, PI * 0.5)
		for i in range(vehicle._wheels.size()):
			_report.append("  %-9s nach Vierteldrehung auf der Stelle %+.3f rad (erwartet %+.3f)" % [
				vehicle._wheels[i].name, vehicle._wheels[i].rotation.x,
				wrapf(-PI * 0.5 * vehicle._wheel_side[i] / vehicle._wheel_radius[i], -PI, PI)])
	var file: FileAccess = FileAccess.open(_out_dir.path_join("messwerte.txt"), FileAccess.WRITE)
	file.store_string("\n".join(_report) + "\n")
	file.close()
	print("\n".join(_report))
	quit()


## A real unit scene on the stage, looking along `heading`, flag in tribe colour.
func _add(scene: PackedScene, at: Vector3, heading: Vector3) -> CrewedVehicle:
	var vehicle: CrewedVehicle = scene.instantiate() as CrewedVehicle
	vehicle.position = at
	_stage.add_child(vehicle)
	_face(vehicle, heading.normalized())
	vehicle._tick_visual(0.0)
	if vehicle._flag_mesh != null:
		vehicle._flag_mesh.material_override = vehicle._mat(TRIBE_COLOR)
	return vehicle


func _face(vehicle: CrewedVehicle, heading: Vector3) -> void:
	vehicle.facing = heading
	if vehicle is FireRam:
		(vehicle as FireRam)._heading = heading


## Moves the vehicle by `way` in small steps, as the unit tick would.
func _drive(vehicle: CrewedVehicle, way: Vector3) -> void:
	var steps: int = maxi(1, int(ceil(way.length() / 0.05)))
	for i in range(steps):
		vehicle.position += way / float(steps)
		vehicle._tick_visual(0.016)


func _turn(vehicle: CrewedVehicle, angle: float) -> void:
	var start: float = vehicle.rotation.y
	for i in range(1, 19):
		var yaw: float = start + angle * float(i) / 18.0
		_face(vehicle, Vector3(sin(yaw), 0.0, cos(yaw)))
		vehicle._tick_visual(0.016)


func _add_post(at: Vector3) -> void:
	var post: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.5, 1.44, 0.05)
	post.mesh = box
	post.position = at + Vector3(0.0, 0.72, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.85, 0.6)
	post.material_override = mat
	_stage.add_child(post)


func _reset_stage() -> void:
	if _stage != null:
		_stage.queue_free()
	_stage = Node3D.new()
	root.add_child(_stage)


func _build_world() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.09)
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
	plane.size = Vector2(120.0, 120.0)
	ground.mesh = plane
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.46, 0.22)
	mat.roughness = 1.0
	ground.material_override = mat
	root.add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.make_current()


func _aim(pivot: Vector3, boom: float, pitch_deg: float) -> void:
	var pitch: float = deg_to_rad(pitch_deg)
	_camera.look_at_from_position(
		pivot + Vector3(0.0, sin(pitch), cos(pitch)) * boom, pivot, Vector3.UP)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out_dir.path_join(shot_name + ".png"))
