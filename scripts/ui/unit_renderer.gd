class_name UnitRenderer extends MultiMeshInstance3D

## Renders ALL units through one MultiMesh (one draw call) instead of one
## AnimatedSprite3D node per unit — 4000 sprites were 4000 draw calls plus
## 4000 per-frame node updates. Billboarding happens in the vertex shader;
## the animation frame is selected via per-instance custom data (atlas UV
## offset) and the tribe colour via the per-instance colour.
##
## Per frame: the camera is fetched ONCE; frame/view updates run in
## VISUAL_SLICES staggered slices; transforms are only rewritten for units
## whose position actually changed (standing units cost one comparison).

## Sized for the phase-8 target: 4 tribes x 1500 hard cap, plus corpses that
## linger a few seconds before expiring.
const MAX_UNITS: int = 8192
const VISUAL_SLICES: int = 3
## On-screen quad size in metres — constant regardless of the frame resolution
## in the atlas (16x24 placeholders at the historical 0.06 m/px, or real art).
const SPRITE_WORLD_W: float = 0.96
const SPRITE_WORLD_H: float = 1.44
## Diameter of the hardcoded circular blob shadow under every unit and its
## lift above the ground (z-fighting guard). Real shadow casting is OFF for
## units (phase 8 shadow rework): thousands of billboarded alpha-discard quads
## went through all shadow cascades before.
const BLOB_SIZE: float = 0.7
const BLOB_Y: float = 0.04
const BLOB_COLOR: Color = Color(0.0, 0.0, 0.0, 0.4)
## Kinds baked into the atlas.
const KINDS: Array[StringName] = [&"brave", &"warrior", &"firewarrior", &"preacher", &"shaman"]
## Sprite Y offset while airborne selects the arms-up jump frame.
const HOP_FRAME_THRESHOLD: float = 0.12
## Small extra depth nudge toward the camera (metres) so a sprite standing on
## a step/next to a foundation lip is not z-fought / buried by the ground.
const DEPTH_BIAS: float = 0.35
## Multiplier on each row's true world elevation when computing depth. 1.0 =
## physically correct (head sits at its real depth): a unit in front of a
## building is fully visible, a unit behind it is occluded, with no overshoot.
## Values >1 pull heads further toward the camera but make them poke through
## roofs/walls when the unit is actually behind — so keep this at 1.0.
const ELEVATION_GAIN: float = 1.0
## How far the body axis of the LYING poses (PlaceholderSprites.FLAT_ANIMS) is
## dropped below the unit's ground point, in metres along screen up. Without it
## the axis would float at half the quad width (0.48 m) above the ground. The
## only tuning knob of the roll — also read by the SelectionManager so the pick
## rectangle stays on the body. Keep below ~0.45 m: deeper and the corpse reads
## as having slid toward the camera, and its contact edge approaches the depth
## threshold where the ground in front of it takes over.
const LIE_DROP_M: float = 0.3
## Screen roll of the flat poses, in the encoding the shader expects: -1 =
## clockwise (head to the RIGHT), +1 = counter-clockwise. ONE direction, not a
## per-view table: every flat pose is viewless, and which side of the body you
## SEE is carried by the artwork (the corpse has two variants,
## PlaceholderSprites.VIEWLESS_POSES), not by the direction of the rotation.
## Both signs are proper rotations (determinant +1), never a mirror — the eight
## views of the upright poses tell left from right (shield vs. sword side).
const LIE_ROLL: float = -1.0
## Status icons (stars, panic, flame) sit at head height of a STANDING figure;
## over a unit that lies flat they would float about a metre above it. This
## factor pulls them down onto the body.
const LIE_HEIGHT_FRAC: float = 0.4

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
// L8 mask gating the tribe-colour multiply per pixel (white = full tint).
uniform sampler2D tint_mask : filter_nearest;
uniform vec2 frame_uv;
uniform float depth_bias;
uniform float elevation_gain;
// Geometry of the 90-degree screen roll for the lying poses (dead, airborne):
// x = quad half height (the pivot on the body axis), y = quad half width,
// z = drop of the body axis below the unit's ground point. A uniform instead
// of literals so the numbers live in ONE place (SPRITE_WORLD_H/W, LIE_DROP_M).
uniform vec3 lie_geom;

varying vec4 tint;
varying vec2 uv_offset;

void vertex() {
	tint = COLOR;
	uv_offset = INSTANCE_CUSTOM.xy;
	// The lying poses (dead, airborne) are AUTHORED UPRIGHT in the portrait-
	// shaped atlas cell and rolled 90 degrees here, so the long cell axis
	// (1.44 m) becomes the body's LENGTH instead of its 0.96 m width — a corpse
	// painted lying down was only 0.96 m long and read as a toy.
	// INSTANCE_CUSTOM.z: 0 = upright, +1 = counter-clockwise (head left),
	// -1 = clockwise (head right). Both are proper rotations (determinant +1),
	// never a MIRROR: the eight views tell left from right (shield vs. sword
	// side), so a flip would swap the unit's handedness.
	float roll = INSTANCE_CUSTOM.z;
	float keep = 1.0 - abs(roll);                        // = cos(roll * 90 deg)
	vec2 pivot = vec2(VERTEX.x, VERTEX.y - lie_geom.x);  // pivot on the body axis
	vec3 v = vec3(
		keep * pivot.x - roll * pivot.y,
		roll * pivot.x + keep * pivot.y
			+ mix(lie_geom.x, lie_geom.y - lie_geom.z, abs(roll)),
		VERTEX.z);
	// Camera-facing (spherical) billboard: the quad axes follow the camera so
	// the sprite never foreshortens. This is used for the on-screen SHAPE.
	mat4 mv = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec4 vp = mv * vec4(v, 1.0);
	vec4 clip = PROJECTION_MATRIX * vp;

	// A spherical billboard puts the whole quad at ONE depth (the unit's ground
	// point), so the head is drawn too far back and nearby elevated geometry
	// (building roofs, flattened-terrain lips) wrongly occludes it. Instead
	// derive the DEPTH as if the sprite stood vertically in the world: raise
	// each row by its true world height (v.y along world up) plus a small bias
	// toward the camera. Only the depth changes; x/y keep the spherical
	// projection, so there is no shear or screen shift.
	// max(): a ROLLED pose hangs lie_geom.z BELOW the ground point, and a
	// negative height would push those rows AWAY from the camera — the flat
	// ground in front of the corpse would then bury its contact edge (at the
	// 55 degree camera pitch, everything below -0.23 m). A lying body is at
	// ground level anyway, so clamping is also the physically right answer.
	// No-op for upright sprites: their VERTEX.y is never negative.
	vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec4 vp_depth = vp;
	vp_depth.z += up_view.z * max(v.y, 0.0) * elevation_gain + depth_bias;
	vec4 clip_depth = PROJECTION_MATRIX * vp_depth;

	POSITION = clip;
	POSITION.z = clip_depth.z / clip_depth.w * clip.w;
}

void fragment() {
	vec4 tex = texture(atlas, uv_offset + UV * frame_uv);
	if (tex.a < 0.5) {
		discard;
	}
	// Corpse fade: screen-door (ordered dither) on the instance alpha keeps the
	// opaque pipeline — real alpha blending would drag every unit sprite into
	// the transparent pass and its sorting problems.
	if (tint.a < 1.0) {
		float threshold = fract(52.9829189 *
			fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (tint.a < threshold) {
			discard;
		}
	}
	float m = texture(tint_mask, uv_offset + UV * frame_uv).r;
	ALBEDO = tex.rgb * mix(vec3(1.0), tint.rgb, m);
}
"""

var _units: Array[Unit] = []
var _multimesh: MultiMesh = null
var _uvs: PackedVector2Array = PackedVector2Array()
var _table: Dictionary = {}
var _visual_phase: int = 0
## Blob-shadow MultiMesh, slot-synchronous with _multimesh (same indices).
var _blob_multimesh: MultiMesh = null

## Shared radial blob texture (also used by the siege engine's blob quad).
static var _blob_texture: ImageTexture = null


## White circle with a soft radial alpha falloff; tinted via albedo_color.
static func blob_texture() -> ImageTexture:
	if _blob_texture == null:
		var s: int = 32
		var img: Image = Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
		var half: float = float(s) * 0.5
		for y in range(s):
			for x in range(s):
				var d: float = Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
				var a: float = clampf(1.0 - smoothstep(0.55, 1.0, d), 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		_blob_texture = ImageTexture.create_from_image(img)
	return _blob_texture


## Flat ground quad with the blob texture (unshaded, alpha, casts nothing).
static func make_blob_mesh(size: Vector2, color: Color = BLOB_COLOR) -> PlaneMesh:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = size
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = blob_texture()
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	plane.material = mat
	return plane


## Screen roll of a pose: LIE_ROLL for the flat ones, 0 for every upright one.
## Pure function so it can be asserted headless.
static func pose_roll(base: StringName) -> float:
	return LIE_ROLL if PlaceholderSprites.anim_lies_flat(base) else 0.0


## Which of the eight entries of an animation's atlas row a unit reads. For a
## normal pose that is its VIEW; a viewless pose has no views, so the entries
## carry its VARIANTS instead (PlaceholderSprites.VIEWLESS_POSES) and the unit's
## landing picks one — the corpse on its back or on its belly. Poses with a
## single variant always read entry 0.
static func pose_slot(base: StringName, view: int, face_down: bool) -> int:
	if not PlaceholderSprites.anim_is_viewless(base):
		return view
	return 1 if face_down and PlaceholderSprites.slot_count(base) > 1 else 0


func _ready() -> void:
	var atlas: Dictionary = UnitSpriteLibrary.build_atlas(KINDS)
	_uvs = atlas.uvs
	_table = atlas.table

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SPRITE_WORLD_W, SPRITE_WORLD_H)
	# Feet at the instance origin.
	quad.center_offset = Vector3(0.0, SPRITE_WORLD_H * 0.5, 0.0)
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", atlas.texture)
	material.set_shader_parameter("tint_mask", atlas.mask_texture)
	material.set_shader_parameter("frame_uv", atlas.frame_uv)
	material.set_shader_parameter("depth_bias", DEPTH_BIAS)
	material.set_shader_parameter("elevation_gain", ELEVATION_GAIN)
	material.set_shader_parameter("lie_geom", Vector3(
		SPRITE_WORLD_H * 0.5, SPRITE_WORLD_W * 0.5, LIE_DROP_M))
	quad.material = material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_UNITS
	_multimesh.visible_instance_count = 0
	multimesh = _multimesh
	# Units never enter the shadow pass (phase 8): the shader's shadows_disabled
	# only stops RECEIVING — casting is this node flag, and thousands of
	# billboarded discard quads across all cascades were pure waste.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Hardcoded circular blob shadows instead, one flat quad per unit through a
	# second MultiMesh with the SAME slot indices.
	_blob_multimesh = MultiMesh.new()
	_blob_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_blob_multimesh.mesh = make_blob_mesh(Vector2(BLOB_SIZE, BLOB_SIZE))
	_blob_multimesh.instance_count = MAX_UNITS
	_blob_multimesh.visible_instance_count = 0
	var blobs: MultiMeshInstance3D = MultiMeshInstance3D.new()
	blobs.name = "BlobShadows"
	blobs.multimesh = _blob_multimesh
	blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blobs)


# --- Registration ------------------------------------------------------------------

func register_unit(unit: Unit) -> void:
	if unit._render_index >= 0:
		return
	if _units.size() >= MAX_UNITS:
		push_warning("UnitRenderer: capacity of %d units reached" % MAX_UNITS)
		return
	unit._render_index = _units.size()
	unit._render_kind = unit.unit_kind()
	unit._render_pos = Vector3.INF
	unit._render_frame = -1
	unit._blob_hidden = false
	_units.append(unit)
	_multimesh.set_instance_color(unit._render_index,
		Unit.TRIBE_COLORS[unit.tribe_id % Unit.TRIBE_COLORS.size()])
	# Freshly taken slots are RECYCLED (swap-remove below) and still carry their
	# predecessor's custom data. The transform is written immediately, the frame
	# only once the slice rotation reaches this index (up to VISUAL_SLICES frames
	# later) — without this seed a new unit would flash up as the previous
	# owner's frame, and with the roll flag as a tipped-over corpse.
	var per_base: Dictionary = _table.get(unit._render_kind, _table[KINDS[0]])
	var idle_uv: Vector2 = _uvs[int((per_base[&"idle"][0] as Array)[0])]
	_multimesh.set_instance_custom_data(unit._render_index,
		Color(idle_uv.x, idle_uv.y, 0.0, 0.0))
	_multimesh.visible_instance_count = _units.size()
	_blob_multimesh.visible_instance_count = _units.size()


## Swap-remove: the last slot's unit moves into the freed slot; its data is
## rewritten (colour now, transform/frame invalidated for the next pass).
func unregister_unit(unit: Unit) -> void:
	var index: int = unit._render_index
	if index < 0 or index >= _units.size():
		return
	var last: int = _units.size() - 1
	var moved: Unit = _units[last]
	_units[index] = moved
	_units.remove_at(last)
	unit._render_index = -1
	if moved != unit:
		moved._render_index = index
		moved._render_pos = Vector3.INF
		moved._render_frame = -1
		moved._blob_hidden = false   # re-hidden by the frame pass if DEAD
		_multimesh.set_instance_color(index,
			Unit.TRIBE_COLORS[moved.tribe_id % Unit.TRIBE_COLORS.size()])
	_multimesh.visible_instance_count = _units.size()
	_blob_multimesh.visible_instance_count = _units.size()


## Re-applies the tribe colour of a unit's instance (after a preacher
## conversion switched its tribe).
func update_unit_color(unit: Unit) -> void:
	if unit._render_index < 0:
		return
	_multimesh.set_instance_color(unit._render_index,
		Unit.TRIBE_COLORS[unit.tribe_id % Unit.TRIBE_COLORS.size()])


# --- Per-frame update -------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _units.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var basis: Basis = camera.global_transform.basis
	var cam_forward: Vector3 = -basis.z
	var cam_right: Vector3 = basis.x
	var hop_offset: float = absf(sin(float(Time.get_ticks_msec()) * 0.012)) * 0.35
	var now_ms: int = Time.get_ticks_msec()

	# Animation frames/views, staggered over VISUAL_SLICES frames.
	for i in range(_visual_phase, _units.size(), VISUAL_SLICES):
		_update_frame(_units[i], cam_forward, cam_right, hop_offset, now_ms)
	_visual_phase = (_visual_phase + 1) % VISUAL_SLICES

	# Transforms every frame, but only for units that actually moved. The blob
	# shadow follows on the ground point (no hop offset); corpses hide theirs
	# in the frame pass.
	for i in range(_units.size()):
		var unit: Unit = _units[i]
		var pos: Vector3 = unit.position
		if unit.hop_visual:
			pos.y += hop_offset
		if unit.state == Unit.State.DEAD:
			pos.y -= unit.corpse_sink_depth()
		if pos != unit._render_pos:
			unit._render_pos = pos
			_multimesh.set_instance_transform(unit._render_index,
				Transform3D(Basis.IDENTITY, pos))
			if unit.state != Unit.State.DEAD:
				_blob_multimesh.set_instance_transform(unit._render_index,
					Transform3D(Basis.IDENTITY, Vector3(
						unit.position.x, unit.position.y + BLOB_Y, unit.position.z)))


func _update_frame(unit: Unit, cam_forward: Vector3, cam_right: Vector3,
		hop_offset: float, now_ms: int) -> void:
	# Corpses keep their full colour and sink into the ground instead of
	# fading (the transform pass applies corpse_sink_depth()); only the blob
	# shadow is dropped here.
	if unit.state == Unit.State.DEAD and not unit._blob_hidden:
		unit._blob_hidden = true   # a lying corpse casts no blob
		_blob_multimesh.set_instance_transform(unit._render_index,
			Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	var view: int = Unit.view_index(unit.facing, cam_forward, cam_right)
	var per_base: Dictionary = _table.get(unit._render_kind, _table[KINDS[0]])
	var base: StringName = unit.anim_base_name
	var views: Array = per_base.get(base, per_base[&"idle"])
	var info: Array = views[pose_slot(base, view, unit.lies_face_down)]   # [start, count, fps]
	var frame: int
	if unit.hop_visual and base == &"jump":
		# Frame-driven by the hop phase: arms up in the air, down on landing.
		frame = 1 if hop_offset > HOP_FRAME_THRESHOLD else 0
	else:
		frame = int(float(now_ms - unit.anim_start_ms) * 0.001 * float(info[2])) % int(info[1])
	var global_frame: int = int(info[0]) + frame
	if global_frame == unit._render_frame:
		return
	unit._render_frame = global_frame
	var uv: Vector2 = _uvs[global_frame]
	# The roll flag travels with the UV: every (animation, slot) owns its own
	# disjoint atlas slots, so a change of pose, facing or landing always changes
	# global_frame too — the early return above can never leave it stale.
	# Deliberately behind that return, so this runs on real frame changes only
	# and not for every unit every frame.
	_multimesh.set_instance_custom_data(
		unit._render_index, Color(uv.x, uv.y, pose_roll(base), 0.0))
