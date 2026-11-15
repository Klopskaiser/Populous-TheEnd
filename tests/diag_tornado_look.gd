extends SceneTree

## TORNADO LOOK — renders the twister funnel to PNG stills (NOT part of the suite).
##
## Needs a real renderer, so run it WITHOUT --headless (a window opens for a few
## seconds and closes itself):
##   godot --path . -s res://tests/diag_tornado_look.gd -- <output dir>
## Without an output dir the stills land in user://tornado_look/.
##
## What it is for: the funnel is pure shader work (shaders/tornado_funnel.gdshader,
## tornado_specks.gdshader, scripts/spells/tornado_visual.gd) and a shader error
## only shows once something is DRAWN — the headless suite never sees it. The
## stills also answer the one hard requirement on the look: WHIRLED-UP UNITS STAY
## READABLE. Each scene therefore puts airborne placeholder sprites on exactly the
## circle the riders fly on (0.8 * TornadoVortex.radius_at_height), spread around
## the axis so that some of them sit BEHIND the core — the worst case.
##
## Stills (camera like the game: pitch -55 degrees, fov 75):
##   1_vergleich_nah   old ring stack (left) next to the new funnel (right), boom 20
##   1b_neu_ganz_nah   the new funnel alone, boom 11
##   2_standard_zoom   new funnel at the game's default zoom (boom 45)
##   3_aufbau          0.25 s after the cast (the funnel rises out of the ground)
##   4_supertornado    main funnel 4.4 m / 12 m with its two satellites
##   5_aufloesung      0.3 s into the dissolve after the vortex ended

const RIDER_KINDS: Array[StringName] = [&"brave", &"warrior", &"firewarrior", &"shaman"]
const PITCH_DEG: float = 55.0

var _out_dir: String = "user://tornado_look"
var _stage: Node3D = null
var _camera: Camera3D = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	root.size = Vector2i(1600, 900)
	_build_world()
	_run()


func _run() -> void:
	var r: float = Balance.TORNADO_RADIUS

	# 1: old ring stack next to the new funnel, close up.
	_reset_stage()
	_add_old_rings(Vector3(-5.0, 0.0, 0.0), r, 8.0)
	_add_riders(Vector3(-5.0, 0.0, 0.0), r, 8.0, 10)
	_add_funnel(Vector3(5.0, 0.0, 0.0), r, 8.0)
	_add_riders(Vector3(5.0, 0.0, 0.0), r, 8.0, 10)
	_add_bystanders(Vector3(0.0, 0.0, 4.5))
	_aim(Vector3(0.0, 3.0, 0.0), 20.0)
	await _wait(2.2)
	await _shot("1_vergleich_nah")

	# 1b: the new funnel alone, as close as the game zooms in (boom 8 is the limit).
	_aim(Vector3(5.0, 3.6, 0.0), 11.0)
	await _wait(0.2)
	await _shot("1b_neu_ganz_nah")

	# 2: the same funnel at the default zoom.
	_aim(Vector3(0.0, 3.0, 0.0), 45.0)
	await _wait(0.3)
	await _shot("2_standard_zoom")

	# 3: build-up.
	_reset_stage()
	_add_funnel(Vector3.ZERO, r, 8.0)
	_add_bystanders(Vector3(3.5, 0.0, 2.0))
	_aim(Vector3(0.0, 3.0, 0.0), 20.0)
	await _wait(0.25)
	await _shot("3_aufbau")

	# 4: Supertornado with satellites.
	_reset_stage()
	var big_r: float = Balance.SUPERTORNADO_RADIUS
	var big_h: float = Balance.SUPERTORNADO_TOP_HEIGHT
	_add_funnel(Vector3.ZERO, big_r, big_h)
	_add_riders(Vector3.ZERO, big_r, big_h, 18)
	for side in [-1.0, 1.0]:
		var at: Vector3 = Vector3(side * 9.5, 0.0, 2.0)
		_add_funnel(at, r, 8.0)
		_add_riders(at, r, 8.0, 6)
	_aim(Vector3(0.0, 4.5, 0.0), 34.0)
	await _wait(2.2)
	await _shot("4_supertornado")

	# 5: dissolve.
	_reset_stage()
	# A REAL vortex this time, so the hand-over in TornadoVortex.tick is what
	# gets exercised: the funnel must outlive the vortex node and then free itself.
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.sfx_id = &""   # no audio in this script
	vortex.setup(0, Vector3(1.0, 0.0, 2.0), null, null, null)
	_stage.add_child(vortex)
	_aim(Vector3(0.0, 3.0, 0.0), 20.0)
	await _wait(1.2)
	var visual: TornadoVisual = vortex._visual
	vortex._life = 0.0
	vortex.tick(0.05)   # expiry: releases the funnel, sets done
	vortex.queue_free()   # what UnitManager._tick_projectiles does with a done one
	await _wait(0.3)
	print("funnel outlives the vortex: ",
		is_instance_valid(visual) and not is_instance_valid(vortex))
	await _shot("5_aufloesung")
	await _wait(TornadoVisual.FADE_TIME)
	print("funnel freed itself after the fade: ", not is_instance_valid(visual))

	print("Stills in ", ProjectSettings.globalize_path(_out_dir))
	quit()


# --- Scene ---------------------------------------------------------------------------

## Ground, light and sky like scenes/main.tscn (flat ambient, sun at -55 / -35).
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
	_camera.far = 2000.0
	root.add_child(_camera)
	_camera.make_current()


func _reset_stage() -> void:
	if _stage != null:
		_stage.queue_free()
	_stage = Node3D.new()
	root.add_child(_stage)


## Camera on the game's boom: `boom` metres behind `pivot` at the game's pitch.
func _aim(pivot: Vector3, boom: float) -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	_camera.look_at_from_position(
		pivot + Vector3(0.0, sin(pitch), cos(pitch)) * boom, pivot, Vector3.UP)


func _add_funnel(at: Vector3, radius: float, top_height: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.position = at
	_stage.add_child(holder)
	var visual: TornadoVisual = TornadoVisual.new()
	visual.setup(radius, top_height, at)
	holder.add_child(visual)


## The look this replaced (copied from TornadoVortex._ready as it was), for the
## side-by-side still.
func _add_old_rings(at: Vector3, radius: float, top_height: float) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.78, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var count: int = 11
	for i in range(count):
		var ring: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		var t: float = float(i) / float(count - 1)
		var r: float = lerpf(radius * 0.16, radius * TornadoVortex.TOP_WIDEN, t)
		torus.inner_radius = r - 0.22 * (radius / 2.2)
		torus.outer_radius = r
		ring.mesh = torus
		ring.material_override = mat
		ring.position = at + Vector3(0.0, lerpf(0.3, top_height, t), 0.0)
		_stage.add_child(ring)


## Airborne sprites on the riders' circle (TornadoVortex._tick_riders): evenly
## around the axis and up the height, so some are in front of the funnel, some
## beside it and some behind it.
func _add_riders(at: Vector3, radius: float, top_height: float, count: int) -> void:
	for i in range(count):
		var lift: float = (float(i) + 0.5) / float(count)
		var angle: float = float(i) * TAU * 0.381966 + 0.4   # golden angle: no rows
		var orbit: float = lerpf(radius, radius * TornadoVortex.TOP_WIDEN, lift) * 0.8
		var pos: Vector3 = at + Vector3(cos(angle) * orbit, lift * top_height,
			sin(angle) * orbit)
		_add_sprite(pos, RIDER_KINDS[i % RIDER_KINDS.size()], &"airborne")


## A few units standing next to the funnel, for scale.
func _add_bystanders(at: Vector3) -> void:
	for i in range(4):
		_add_sprite(at + Vector3(float(i) * 0.9 - 1.35, 0.0, 0.0),
			RIDER_KINDS[i % RIDER_KINDS.size()], &"stand")


## One placeholder unit sprite, sized like UnitRenderer draws it. Airborne units
## are drawn lying (rolled 90 degrees), as in the game.
func _add_sprite(pos: Vector3, kind: StringName, anim: StringName) -> void:
	var frames: Array[Image] = PlaceholderSprites.build_slot(kind, anim, 0)
	if frames.is_empty():
		return
	var img: Image = frames[0].duplicate() as Image
	var lying: bool = PlaceholderSprites.anim_lies_flat(anim)
	if lying:
		img.rotate_90(CLOCKWISE)
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.pixel_size = UnitRenderer.SPRITE_WORLD_H / float(PlaceholderSprites.H)
	var half_h: float = (UnitRenderer.SPRITE_WORLD_W if lying else UnitRenderer.SPRITE_WORLD_H) * 0.5
	sprite.position = pos + Vector3(0.0, half_h, 0.0)
	_stage.add_child(sprite)


# --- Capture -------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out_dir.path_join(shot_name + ".png"))
