class_name Scaffold extends Node3D

## Construction scaffold (user spec 2026-11-23): replaces the old "building grows
## out of the ground" while a site is being built. It is sized to the building
## (footprint + height of its model) and has THREE height tiers, shown one after
## another as the build progresses (Building.construction_visual_stage).
##
## The model is replaceable: assets/models/buildings/<kind>_scaffold.glb (one
## building kind) or assets/models/buildings/scaffold.glb (all kinds). Such a
## model is authored for a 1 x 1 m ground square and 1 m height around the
## origin, entrance south (+Z), and has three child nodes named Tier1, Tier2 and
## Tier3; it is scaled onto the building's size. Without a file the scaffold is
## built procedurally (poles, ledgers, planks and braces per tier).

const TIERS: int = 3
## The frame stands this far outside the footprint (metres).
const MARGIN: float = 0.35
## Max distance between two poles along an edge (metres).
const POLE_SPACING: float = 2.2
const POLE_THICK: float = 0.12
const LEDGER_THICK: float = 0.08
const BRACE_THICK: float = 0.07
const PLANK_WIDTH: float = 0.35
const PLANK_THICK: float = 0.05
const WOOD: Color = Color(0.45, 0.31, 0.18)
const PLANK: Color = Color(0.62, 0.5, 0.33)

## Tier nodes, bottom first (Tier1..Tier3).
var tiers: Array[Node3D] = []
## Outer size of the frame (x/z) and its total height.
var size: Vector3 = Vector3.ONE
var shown_tiers: int = -1

static var _material: StandardMaterial3D = null


## Builds a scaffold for a footprint of `footprint` cells and a building of
## `height` metres. `kind` selects an optional asset model (see the class note).
static func create(footprint: Vector2i, height: float, kind: StringName = &"") -> Scaffold:
	var s: Scaffold = Scaffold.new()
	s.name = "Scaffold"
	s.size = Vector3(float(footprint.x) * TerrainData.CELL_SIZE + 2.0 * MARGIN,
		maxf(height, 1.5), float(footprint.y) * TerrainData.CELL_SIZE + 2.0 * MARGIN)
	if not s._try_asset_model(kind):
		s._build_procedural()
	s.set_tiers(0)
	return s


## Shows the lowest `count` tiers (0 = none, 3 = all).
func set_tiers(count: int) -> void:
	count = clampi(count, 0, TIERS)
	if count == shown_tiers:
		return
	shown_tiers = count
	for i in range(tiers.size()):
		tiers[i].visible = i < count


func _try_asset_model(kind: StringName) -> bool:
	var model: Node3D = null
	if kind != &"":
		model = AssetLibrary.instantiate_model("models/buildings/%s_scaffold.glb" % kind)
	if model == null:
		model = AssetLibrary.instantiate_model("models/buildings/scaffold.glb")
	if model == null:
		return false
	var found: Array[Node3D] = []
	for i in range(TIERS):
		var tier: Node3D = model.find_child("Tier%d" % (i + 1), true, false) as Node3D
		if tier == null:
			model.free()
			push_warning("Geruestmodell ohne Tier%d - es wird das eingebaute Geruest benutzt" % (i + 1))
			return false
		found.append(tier)
	model.scale = size
	add_child(model)
	tiers = found
	return true


func _build_procedural() -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var tier_h: float = size.y / float(TIERS)
	var corners: Array[Vector2] = [Vector2(-hx, -hz), Vector2(hx, -hz),
		Vector2(hx, hz), Vector2(-hx, hz)]
	for t in range(TIERS):
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y0: float = tier_h * float(t)
		var y1: float = tier_h * float(t + 1)
		for e in range(4):
			var a: Vector2 = corners[e]
			var b: Vector2 = corners[(e + 1) % 4]
			var edge: Vector2 = b - a
			var length: float = edge.length()
			var dir: Vector2 = edge / length
			var segments: int = maxi(1, int(ceil(length / POLE_SPACING)))
			# Poles (the corner pole is drawn by the edge that starts there).
			for k in range(segments):
				var p: Vector2 = a + dir * (length * float(k) / float(segments))
				_add_box(st, Transform3D(Basis(), Vector3(p.x, (y0 + y1) * 0.5, p.y)),
					Vector3(POLE_THICK, y1 - y0 + LEDGER_THICK, POLE_THICK), WOOD)
			var mid: Vector2 = (a + b) * 0.5
			var yaw: float = atan2(-dir.y, dir.x)
			var along: Basis = Basis(Vector3.UP, yaw)
			# Ledger along the edge at the top of the tier, a lighter one halfway.
			_add_box(st, Transform3D(along, Vector3(mid.x, y1, mid.y)),
				Vector3(length, LEDGER_THICK, LEDGER_THICK), WOOD)
			_add_box(st, Transform3D(along, Vector3(mid.x, (y0 + y1) * 0.5, mid.y)),
				Vector3(length, LEDGER_THICK * 0.7, LEDGER_THICK * 0.7), WOOD)
			# Planks: a walkway on the inside of the frame at the top of the tier.
			var inward: Vector2 = Vector2(-dir.y, dir.x)
			if inward.dot(-mid) < 0.0:
				inward = -inward
			var deck: Vector2 = mid + inward * (PLANK_WIDTH * 0.5)
			_add_box(st, Transform3D(along, Vector3(deck.x, y1 + LEDGER_THICK * 0.5
				+ PLANK_THICK * 0.5, deck.y)),
				Vector3(length - PLANK_WIDTH, PLANK_THICK, PLANK_WIDTH), PLANK)
			# One diagonal brace per edge and tier, alternating direction.
			var rise: float = y1 - y0
			var run: float = length / float(segments)
			var slope: float = atan2(rise, run)
			if (t + e) % 2 == 1:
				slope = -slope
			var brace_basis: Basis = along * Basis(Vector3.BACK, slope)
			var brace_c: Vector2 = a + dir * (run * 0.5)
			_add_box(st, Transform3D(brace_basis, Vector3(brace_c.x, (y0 + y1) * 0.5, brace_c.y)),
				Vector3(sqrt(run * run + rise * rise), BRACE_THICK, BRACE_THICK), WOOD)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Tier%d" % (t + 1)
		mi.mesh = st.commit()
		mi.material_override = _shared_material()
		add_child(mi)
		tiers.append(mi)


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true   # WOOD/PLANK are authored in sRGB
		_material.roughness = 1.0
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material


## Appends a box of `box_size` centred on `xform.origin`, oriented by its basis,
## with flat per-face normals.
static func _add_box(st: SurfaceTool, xform: Transform3D, box_size: Vector3, color: Color) -> void:
	var h: Vector3 = box_size * 0.5
	# Each face: normal + its 4 corners (counter-clockwise seen from outside).
	var faces: Array = [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
	]
	for f in faces:
		var n: Vector3 = (xform.basis * (f[0] as Vector3)).normalized()
		var q: Array = f[1]
		var p: Array[Vector3] = []
		for v in q:
			p.append(xform * (v as Vector3))
		# Godot's front faces are clockwise: emit the quad reversed.
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(color)
			st.set_normal(n)
			st.add_vertex(p[idx])
