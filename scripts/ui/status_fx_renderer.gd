class_name StatusFxRenderer extends Node3D

## Persistent status-effect overlays on units — PANIC (red exclamation mark)
## and BURNING (flames on the body) — one MultiMesh per effect (one draw call
## each), following the StarsRenderer pattern. The icon shows exactly as long
## as the state lasts. Display priority: BURNING suppresses all other status
## icons (burning units are implicitly panicking anyway). Crit damage
## (INJURED, below 25 % health) is drawn as the classic circling stars by the
## StarsRenderer — here it only drives its loop sound.
##
## Icons are procedural placeholders, replaceable per effect via
## assets/textures/effects/<panic|burning|injured>.png — a single image or a
## horizontal strip of square frames (frame count = width / height).
##
## Audio: while a unit is in a state, a positional loop
## (assets/audio/sfx/unit_<effect>_loop.ogg) plays via AudioManager.start_loop
## — concurrency-capped and owner-tracked there. Loop ownership is diffed via
## a per-unit bitmask; units that leave the world (e.g. enter a training
## building) are caught by a frame stamp so no loop lingers.

const MAX_PER_EFFECT: int = 256
const FRAME_TIME: float = 0.15

const FX_PANIC: int = 1
const FX_BURNING: int = 2
const FX_INJURED: int = 4

var _unit_manager: UnitManager = null
var _audio: Node = null
## Per effect: {bit, loop_name, height, mm (MultiMesh), material, textures}.
var _effects: Array[Dictionary] = []
## Units currently owning at least one effect: unit -> mask (for cleanup).
var _tracked: Dictionary = {}
var _frame_timer: float = 0.0
var _frame: int = 0
var _tick: int = 0


func setup(p_unit_manager: UnitManager) -> void:
	_unit_manager = p_unit_manager


func _ready() -> void:
	_audio = get_node_or_null("/root/AudioManager")
	# The flame sits on the upper body and is nudged toward the camera so the
	# unit's own billboard (same world position) cannot hide it while standing.
	_effects = [
		_make_effect(FX_PANIC, &"panic", 1.95, Vector2(0.45, 0.6)),
		_make_effect(FX_BURNING, &"burning", 1.25, Vector2(1.1, 1.3), 0.35),
		_make_effect(FX_INJURED, &"injured", 1.55, Vector2(0.8, 0.4)),
	]


func _make_effect(bit: int, fx_name: StringName, height: float, size: Vector2,
		toward_cam: float = 0.0) -> Dictionary:
	var textures: Array[Texture2D] = _load_textures(fx_name)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Alpha scissor keeps the quads in the opaque pass (no sorting issues).
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = textures[0]
	quad.material = material
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = MAX_PER_EFFECT
	multimesh.visible_instance_count = 0
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Fx_%s" % fx_name
	mmi.multimesh = multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return {
		"bit": bit,
		"loop_name": StringName("unit_%s_loop" % fx_name),
		"height": height,
		"toward_cam": toward_cam,
		"mm": multimesh,
		"material": material,
		"textures": textures,
	}


## Asset texture (single image or horizontal strip of square frames) when
## present, otherwise the procedural placeholder frames.
func _load_textures(fx_name: StringName) -> Array[Texture2D]:
	var img: Image = AssetLibrary.image("textures/effects/%s.png" % fx_name)
	if img != null:
		var frames: Array[Texture2D] = []
		var fh: int = img.get_height()
		var count: int = maxi(img.get_width() / maxi(fh, 1), 1)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		for i in range(count):
			var frame: Image = Image.create(fh, fh, false, Image.FORMAT_RGBA8)
			frame.blit_rect(img, Rect2i(i * fh, 0, fh, fh), Vector2i.ZERO)
			frames.append(ImageTexture.create_from_image(frame))
		return frames
	match fx_name:
		&"panic":
			return [_panic_frame(0), _panic_frame(1)]
		&"burning":
			return [_burning_frame(0), _burning_frame(1), _burning_frame(2)]
		_:
			return [_injured_frame(0), _injured_frame(1)]


func _process(delta: float) -> void:
	if _unit_manager == null or _effects.is_empty():
		return
	_tick += 1
	_frame_timer += delta
	if _frame_timer >= FRAME_TIME:
		_frame_timer = 0.0
		_frame += 1
		for e in _effects:
			var textures: Array[Texture2D] = e.textures
			if textures.size() > 1:
				(e.material as StandardMaterial3D).albedo_texture = \
					textures[_frame % textures.size()]
	var camera: Camera3D = get_viewport().get_camera_3d()
	# Along the camera's up axis the icons sit above the billboard sprite's
	# head at every pitch (same reasoning as the StarsRenderer).
	var up: Vector3 = camera.global_transform.basis.y if camera != null \
		else Vector3.UP
	# Toward the viewer (camera looks along -Z): used to pull body-level icons
	# like the flame in front of the unit's own billboard.
	var toward: Vector3 = camera.global_transform.basis.z if camera != null \
		else Vector3.ZERO
	var counts: Array[int] = [0, 0, 0]
	for unit in _unit_manager.units:
		var mask: int = 0
		if unit.state != Unit.State.DEAD:
			if unit.state == Unit.State.PANIC:
				mask |= FX_PANIC
			if unit.is_burning():
				mask |= FX_BURNING
			# Badly hurt: sprite units only (the siege engine's 1 HP is a
			# "never targetable" convention, not damage).
			if unit.renders_as_sprite() \
					and unit.health <= int(float(unit.max_health) * Unit.BADLY_HURT_FRAC):
				mask |= FX_INJURED
		if mask != unit._status_fx_mask:
			_sync_loops(unit, unit._status_fx_mask, mask)
			unit._status_fx_mask = mask
			if mask == 0:
				_tracked.erase(unit)
			else:
				_tracked[unit] = mask
		if mask == 0:
			continue
		unit._status_fx_seen = _tick
		# Display priority (user spec): BURNING overrides every other status
		# icon; crit damage (INJURED) is drawn as circling stars by the
		# StarsRenderer, never here. Loop sounds above follow the FULL mask.
		var visual_mask: int = mask & ~FX_INJURED
		if visual_mask & FX_BURNING:
			visual_mask = FX_BURNING
		for i in range(_effects.size()):
			var e: Dictionary = _effects[i]
			if visual_mask & int(e.bit) and counts[i] < MAX_PER_EFFECT:
				(e.mm as MultiMesh).set_instance_transform(counts[i],
					Transform3D(Basis.IDENTITY, unit.position
						+ up * float(e.height) + toward * float(e.toward_cam)))
				counts[i] += 1
	for i in range(_effects.size()):
		(_effects[i].mm as MultiMesh).visible_instance_count = counts[i]
	_cleanup_departed()


## Units that left the world (unregistered but kept alive, e.g. training or
## garrison) are no longer iterated above — their frame stamp goes stale and
## their loops must stop. Freed units are cleaned by the AudioManager itself.
func _cleanup_departed() -> void:
	if _tracked.is_empty():
		return
	var stale: Array = []
	for unit in _tracked:
		if not is_instance_valid(unit) or unit._status_fx_seen != _tick:
			stale.append(unit)
	for unit in stale:
		if is_instance_valid(unit):
			_sync_loops(unit, _tracked[unit], 0)
			unit._status_fx_mask = 0
		_tracked.erase(unit)


func _sync_loops(unit: Unit, old_mask: int, new_mask: int) -> void:
	if _audio == null:
		return
	var changed: int = old_mask ^ new_mask
	for e in _effects:
		if changed & int(e.bit):
			if new_mask & int(e.bit):
				_audio.start_loop(e.loop_name, unit)
			else:
				_audio.stop_loop(e.loop_name, unit)


# --- Procedural placeholder icons ------------------------------------------------------

const C_PANIC: Color = Color(0.95, 0.15, 0.1)
const C_FLAME: Color = Color(1.0, 0.45, 0.05)
const C_FLAME_CORE: Color = Color(1.0, 0.85, 0.25)
const C_BLOOD: Color = Color(0.8, 0.08, 0.08)


## Red exclamation mark, wobbling one pixel between the two frames.
static func _panic_frame(phase: int) -> ImageTexture:
	var img: Image = Image.create_empty(12, 16, false, Image.FORMAT_RGBA8)
	var x: int = 5 + (phase % 2)
	img.fill_rect(Rect2i(x - 1, 1, 3, 9), C_PANIC)
	img.fill_rect(Rect2i(x - 1, 12, 3, 3), C_PANIC)
	img.fill_rect(Rect2i(x, 2, 1, 7), Color(1.0, 0.5, 0.4))
	return ImageTexture.create_from_image(img)


## Small flame: orange body, yellow core, tip flickering per frame.
static func _burning_frame(phase: int) -> ImageTexture:
	var img: Image = Image.create_empty(14, 18, false, Image.FORMAT_RGBA8)
	# Body: stacked, narrowing rows.
	img.fill_rect(Rect2i(3, 10, 8, 6), C_FLAME)
	img.fill_rect(Rect2i(4, 6, 6, 4), C_FLAME)
	img.fill_rect(Rect2i(5, 3, 4, 3), C_FLAME)
	# Flickering tip wanders with the phase.
	var tip_x: int = [6, 4, 8][phase % 3]
	img.fill_rect(Rect2i(tip_x, 1, 2, 2), C_FLAME)
	# Hot core.
	img.fill_rect(Rect2i(5, 11, 4, 4), C_FLAME_CORE)
	img.fill_rect(Rect2i(6, 8, 2, 3), C_FLAME_CORE)
	return ImageTexture.create_from_image(img)


## Red drops beside the head, alternating positions between the frames.
static func _injured_frame(phase: int) -> ImageTexture:
	var img: Image = Image.create_empty(24, 12, false, Image.FORMAT_RGBA8)
	var offsets: Array = [[2, 2], [10, 5], [19, 3]] if phase % 2 == 0 \
		else [[4, 5], [12, 2], [17, 6]]
	for o in offsets:
		var x: int = o[0]
		var y: int = o[1]
		img.fill_rect(Rect2i(x + 1, y, 1, 1), C_BLOOD)
		img.fill_rect(Rect2i(x, y + 1, 3, 2), C_BLOOD)
		img.fill_rect(Rect2i(x + 1, y + 3, 1, 1), C_BLOOD)
	return ImageTexture.create_from_image(img)
