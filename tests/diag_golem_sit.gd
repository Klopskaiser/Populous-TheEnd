extends SceneTree

## GOLEM SITZT — Standbilder vom Hinsetzen und Aufstehen eines 31-m-Golems im echten
## Renderer (NICHT Teil der Suite; 2026-11-17, erste Stufe des Sitzens).
##
## Ohne --headless aufrufen (ein Fenster oeffnet sich fuer etwa 15 s):
##   godot --path . -s res://tests/diag_golem_sit.gd -- <Ausgabeordner> [golem|demon|genesis]
##
## Seitenansicht, der Golem schaut nach rechts (+x). Rot: die Sitzflaeche (das
## Rechteck unter dem Po, auf dem der Sitzschaden liegt); gelbe Saeule: der logische
## Standpunkt des Golems (an den Fuessen, im Sitzen auf der Mitte der Sitzflaeche).
## Die Bilder "vor_aufsetzen" und "nach_aufsetzen" liegen einen Tick auseinander: die
## Figur darf dazwischen nicht springen, obwohl der Standpunkt auf den Sitz wechselt.

const SCENES: Dictionary = {
	"golem": "res://scenes/units/golem.tscn",
	"demon": "res://scenes/units/demon_golem.tscn",
	"genesis": "res://scenes/units/genesis_golem.tscn",
}

var _out: String = "user://golem_sit"
var _kind: String = "golem"
var _g: Golem = null
var _um: UnitManager = null
var _t: float = 0.0
var _phase: int = 0
var _marker: MeshInstance3D = null
var _seat_box: MeshInstance3D = null
var _shots: Array = []
var _busy: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "":
		_out = args[0]
	if args.size() > 1 and SCENES.has(args[1]):
		_kind = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0
	var nav: NavGrid = NavGrid.new(td)
	var tribes: Array[Tribe] = [Tribe.new(0), Tribe.new(1)]
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	_um = UnitManager.new()
	_um.setup(td, nav, tribes, tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, _um, wpm)
	_um.building_manager = bm
	get_root().add_child(_um)
	_um.set_physics_process(false)
	_g = _um.spawn_unit(load(SCENES[_kind]), 0, Vector3(50, 5, 64)) as Golem
	if _g is GenesisGolem:
		(_g as GenesisGolem).credit_brave(1000.0)
	while not _g.can_sit():
		_g._credit_kill()
	_g._stretch_queued = false
	_g._rise = 1.0
	_g._shown_size = _g.size_factor()   # no growth animation in the stills
	if _g._model != null:
		_g._model.scale = _g.model_scale() * _g._shown_size
	_g.facing = Vector3(1, 0, 0)
	_g.snap_heading()
	_build_stage()
	print("%s: %.1f m, Sitz %.1f m hinter den Fuessen, %.1f x %.1f m, Hinsetzen %.2f s" % [
		_kind, _g.height_m(), _g.seat_back_m(), _g.seat_half_extent().x * 2.0,
		_g.seat_half_extent().y * 2.0, _g.sit_switch_time()])


func _build_stage() -> void:
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position = Vector3(64, 5, 64)
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.55, 0.35)
	ground.material_override = gm
	get_root().add_child(ground)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	get_root().add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.7, 0.8, 0.9)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	get_root().add_child(env)
	var cam: Camera3D = Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(45, 5 + 20, 64 + 75), Vector3(45, 5 + 12, 64))
	cam.current = true
	_marker = MeshInstance3D.new()
	var col: CylinderMesh = CylinderMesh.new()
	col.top_radius = 0.4
	col.bottom_radius = 0.4
	col.height = 40.0
	_marker.mesh = col
	var mm: StandardMaterial3D = StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.9, 0.1)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mm
	get_root().add_child(_marker)
	_seat_box = MeshInstance3D.new()
	_seat_box.mesh = BoxMesh.new()
	var sm: StandardMaterial3D = StandardMaterial3D.new()
	sm.albedo_color = Color(0.9, 0.1, 0.1, 0.6)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_seat_box.material_override = sm
	_seat_box.visible = false
	get_root().add_child(_seat_box)


func _process(delta: float) -> bool:
	if _busy:
		return false
	var dt: float = minf(delta, 0.05)
	_t += dt
	_g.tick(dt)
	_marker.position = _g.position + Vector3(0, 20, 0)
	if _g._seat_center != Vector3.INF:
		_seat_box.visible = true
		_seat_box.position = _g._seat_center + Vector3(0, 0.3, 0)
		_seat_box.scale = Vector3(_g._seat_half.y * 2.0, 0.6, _g._seat_half.x * 2.0)
	else:
		_seat_box.visible = false
	match _phase:
		0:
			if _t > 1.0:
				_shot("1_steht")
				_g.sit_down()
				_phase = 1
		1:
			if _g.stance == Golem.STANCE_CROUCH and not _g.is_switching_stance():
				_shot("2_gebueckt")
				_phase = 2
			elif _g._stance_target == Golem.STANCE_SIT and _g.is_switching_stance():
				_phase = 2
		2:
			if _g._stance_target == Golem.STANCE_SIT and _g.is_switching_stance() \
					and _g._stance_switch < _g.sit_switch_time() * 0.5:
				_shot("3_setzt_sich")
				_phase = 3
		3:
			if _g._seat_center != Vector3.INF:
				_phase = 41   # the frame before the move was missed: no pair this time
			elif _g.is_switching_stance() \
					and _g._stance_switch - 2.0 * dt <= Balance.GOLEM_SIT_SEAT_LEAD:
				# The next tick moves her onto the seat (it moves once less than
				# GOLEM_SIT_SEAT_LEAD is left after the tick).
				_shot("4_vor_umsetzen")
				_phase = 4
		4:
			if _g._seat_center != Vector3.INF:
				_shot("5_nach_umsetzen")
				_phase = 41
		41:
			if _g.is_sitting() and not _g.is_switching_stance():
				_t = 0.0
				_phase = 5
		5:
			if _t > 3.0:
				_shot("6_sitzt")
				_g.stand_up()
				_phase = 6
		6:
			if _g.is_switching_stance() and _g._stance_switch < _g.sit_switch_time() * 0.5:
				_shot("7_steht_auf")
				_phase = 7
		7:
			if _g.stance == Golem.STANCE_STAND and not _g.is_sit_locked():
				_t = 0.0
				_phase = 8
		8:
			if _t > 0.5:
				_shot("8_steht_wieder")
				_phase = 9
		9:
			print("Bilder in ", ProjectSettings.globalize_path(_out))
			return true
	return false


func _shot(name: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	img.save_png(_out.path_join("%s_%s.png" % [_kind, name]))
	print("  %s: Standpunkt (%.1f, %.1f), Modell z %.2f" % [name, _g.position.x, _g.position.z,
		_g._model.position.z if _g._model != null else 0.0])
	_busy = false
