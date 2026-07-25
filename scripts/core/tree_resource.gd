class_name TreeResource extends Node3D

## Wild/planted tree with five growth stages: stage 0 is a SAPLING (0 wood, a
## bare vertical stick planted by the forester) that cannot reproduce; stages
## 1..4 are the four grown stages (klein -> groß) yielding 1/2/3/4 wood. Wood is
## harvested ONE unit at a time: each harvest drops the tree a growth stage (a
## big tree takes four trips); the last unit removes it. Several workers may
## harvest the same tree at once (as many as it has wood, so max 4 on a big
## tree). Growth and reproduction are driven by the TreeManager. Growth is
## PROBABILISTIC: every GROWTH_ROLL_INTERVAL seconds the tree rolls once with
## growth_chance() — the mean time per stage stays GROWTH_TIME (per ground
## factor), but individual trees spread out geometrically instead of growing
## in synchronised waves. Trees do not block the NavGrid (thin obstacles).
## Fire (spells, lava) IGNITES a tree: it burns down and is destroyed
## completely, yielding no wood.
##
## Tree TYPES (Balance.TREE_TYPE_PARAMS, ground band via TerrainData.is_grass):
## STANDARD grows everywhere (the only type the forester plants); LEAF grows/
## reproduces faster on grass and slower off it; BAMBOO only lives on grass
## (pause/no sprouts elsewhere), reproduces 3x, stands denser and stops at
## stage 2 (max. 2 wood). Each type has its own model slot with a procedural
## fallback; the `on_grass` flag is cached and maintained by the TreeManager.

enum TreeType {STANDARD, LEAF, BAMBOO}

const MAX_STAGE: int = 4
## Remaining wood per stage: 0 = sapling (0), then 1/2/3/4.
const YIELDS: Array[int] = Balance.TREE_YIELDS
## MEAN seconds per growth stage (expected value of the probabilistic roll).
const GROWTH_TIME: float = Balance.TREE_GROWTH_TIME
## Seconds between growth rolls (see grow_tick / growth_chance).
const GROWTH_ROLL_INTERVAL: float = Balance.TREE_GROWTH_ROLL_INTERVAL
## How long a burning tree stays alight before it is destroyed.
const BURN_TIME: float = 1.8

var type: TreeType = TreeType.STANDARD
## Cached ground flag (grass band), set by the TreeManager on spawn/register
## and refreshed when the terrain deforms under the tree.
var on_grass: bool = true

var stage: int = 0
## Seconds until the next growth ROLL; starts at a random phase offset (see
## _init) so trees spawned in the same frame do not all roll simultaneously.
var growth_timer: float = GROWTH_ROLL_INTERVAL
## Workers currently harvesting this tree; untyped entries (may be freed).
var claimers: Array = []
## Set once when the last wood is taken (or when it burns) — guards late
## references while the node awaits queue_free.
var felled_flag: bool = false
## Burning countdown (> 0 while alight); the TreeManager destroys it at the end.
var _burn_time: float = 0.0

var _crown: MeshInstance3D = null
var _trunk_mat: StandardMaterial3D = null
var _crown_mat: StandardMaterial3D = null

## Shared procedural fallback resources (meshes/materials), built once PER TYPE
## and reused by every tree instead of 2 mesh + 2 material instances per tree.
## ignite() localises the crown material before tinting it, so a burning tree
## does not recolour the whole forest.
static var _shared_visuals: Dictionary = {}

## RNG for the growth rolls and phase offsets — static and seedable, so the
## headless tests can make growth deterministic (randomly seeded by default).
static var growth_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	growth_timer = growth_rng.randf_range(0.0, GROWTH_ROLL_INTERVAL)


func _params() -> Dictionary:
	return Balance.TREE_TYPE_PARAMS[type]


## Highest growth stage this type reaches (bamboo stops at 2 = max. 2 wood).
func max_stage() -> int:
	return int(_params().max_stage)


func _stage_scale(s: int) -> float:
	return float(_params().stage_scales[s])


## Wood still in the tree (a sapling holds none).
func wood_yield() -> int:
	return YIELDS[stage]


## Seconds per single harvest; bigger trees take a bit longer.
func chop_time() -> float:
	return 1.5 + 0.5 * float(stage)


## Takes one unit of wood: the tree drops a growth stage; the last unit marks it
## felled (the TreeManager removes it). A sapling / burning tree yields nothing.
func harvest_one() -> int:
	if felled_flag or wood_yield() <= 0:
		return 0
	if wood_yield() > 1:
		set_stage(stage - 1)
	else:
		felled_flag = true
	return 1


# --- Claims (parallel harvesting) ---------------------------------------------

## A tree supports as many parallel harvesters as it has wood (max 4); a sapling
## (0 wood) and a burning tree cannot be claimed.
func can_claim() -> bool:
	_prune_claimers()
	return not felled_flag and not is_burning() and claimers.size() < wood_yield()


func add_claimer(worker: Object) -> void:
	if not (worker in claimers):
		claimers.append(worker)


func remove_claimer(worker: Object) -> void:
	claimers.erase(worker)


func _prune_claimers() -> void:
	claimers = claimers.filter(func(w: Variant) -> bool:
		return w != null and is_instance_valid(w))


func set_stage(p_stage: int) -> void:
	stage = clampi(p_stage, 0, max_stage())
	scale = Vector3.ONE * _stage_scale(stage)
	# The sapling (stage 0) is a bare stick — no crown yet.
	if _crown != null:
		_crown.visible = stage >= 1


## Called by the TreeManager tick. Growth is PROBABILISTIC: every
## GROWTH_ROLL_INTERVAL seconds the tree rolls growth_chance() once. The mean
## time per stage is exactly GROWTH_TIME / ground factor, but the individual
## stage times follow a geometric distribution — trees planted together no
## longer grow in synchronised waves. Factor 0 (bamboo off grass) pauses the
## roll clock entirely; a terrain deformation takes effect on the next tick.
## Saplings grow like any other tree — they just have one extra stage.
func grow_tick(delta: float) -> void:
	if stage >= max_stage():
		return
	var chance: float = growth_chance()
	if chance <= 0.0:
		return
	growth_timer -= delta
	while growth_timer <= 0.0:
		growth_timer += GROWTH_ROLL_INTERVAL
		if growth_rng.randf() < chance:
			set_stage(stage + 1)
			if stage >= max_stage():
				return


## Probability to advance one stage per roll: roll interval x ground factor /
## GROWTH_TIME — chosen so the EXPECTED stage time stays GROWTH_TIME / factor
## (the pre-roll growth rate is preserved exactly).
func growth_chance() -> float:
	var f: float = float(_params().growth_grass if on_grass else _params().growth_off)
	return minf(GROWTH_ROLL_INTERVAL * f / GROWTH_TIME, 1.0)


# --- Burning (fire spells / lava) ---------------------------------------------

func is_burning() -> bool:
	return _burn_time > 0.0


## Flame size for the shared StatusFxRenderer billboard; scale.y already
## carries growth stage x burn shrink, so the flame shrinks with the tree.
func burn_fx_scale() -> float:
	return maxf(2.2 * scale.y, 0.5)


## Flame anchor at the (shrinking) crown centre.
func burn_fx_height() -> float:
	return maxf(1.9 * scale.y, 0.3)


## Sets the tree alight (fireball, firestorm, lightning, lava). It stops being
## harvestable at once (claimers drop), plays a short burn and is then destroyed
## by the TreeManager (no wood). Re-igniting an already burning tree does nothing.
func ignite() -> void:
	if felled_flag or is_burning():
		return
	_burn_time = BURN_TIME
	claimers.clear()
	if is_inside_tree():
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null:
			audio.play_sfx(&"tree_burning", position, 200)
	if _crown_mat != null:
		# The crown material is SHARED between all trees of this type — localise
		# it before tinting, otherwise the whole forest turns ember-coloured.
		_crown_mat = _crown_mat.duplicate() as StandardMaterial3D
		if _crown != null:
			_crown.material_override = _crown_mat
		_crown_mat.albedo_color = Color(0.55, 0.2, 0.08)
		_crown_mat.emission_enabled = true
		_crown_mat.emission = Color(1.0, 0.45, 0.08)
		_crown_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL


## Advances the burn; returns true once the tree is spent (ready to remove).
## Driven by the TreeManager tick.
func burn_tick(delta: float) -> bool:
	if _burn_time <= 0.0:
		return false
	_burn_time -= delta
	# Shrink and flicker while burning down.
	var t: float = clampf(_burn_time / BURN_TIME, 0.0, 1.0)
	scale = Vector3.ONE * _stage_scale(stage) * maxf(t, 0.05)
	if _crown_mat != null:
		_crown_mat.emission_energy_multiplier = 1.5 + randf() * 1.5
	if _burn_time <= 0.0:
		felled_flag = true
		return true
	return false


func _ready() -> void:
	_create_visuals()
	_create_click_body()
	set_stage(stage)   # apply crown visibility now that the mesh exists


## User-provided model per type (assets/models/trees/tree.glb / tree_leaf.glb /
## tree_bamboo.glb) when present, otherwise a procedural fallback: STANDARD =
## trunk + cone crown, LEAF = trunk + sphere crown (lighter green), BAMBOO =
## thin tall stalk + small leaf tuft. Growth stages scale the whole node either
## way; the burn flicker/crown-hiding only applies to the procedural crown (the
## glb still shrinks while burning — _crown/_crown_mat stay null-guarded).
## Fallback meshes/materials are shared statics per type (see _shared_visuals).
func _create_visuals() -> void:
	var model: Node3D = AssetLibrary.instantiate_model(String(_params().model))
	if model != null:
		add_child(model)
		return
	var vis: Dictionary = _fallback_visuals(type)
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.mesh = vis.trunk_mesh
	_trunk_mat = vis.trunk_mat
	trunk.material_override = _trunk_mat
	trunk.position.y = vis.trunk_y
	add_child(trunk)

	_crown = MeshInstance3D.new()
	_crown.mesh = vis.crown_mesh
	_crown_mat = vis.crown_mat   # shared — ignite() localises before tinting
	_crown.material_override = _crown_mat
	_crown.position.y = vis.crown_y
	add_child(_crown)


## Builds (once) and returns the shared fallback resources for a type.
static func _fallback_visuals(t: TreeType) -> Dictionary:
	if _shared_visuals.has(t):
		return _shared_visuals[t]
	var vis: Dictionary = {}
	match t:
		TreeType.BAMBOO:
			# Thin tall yellow-green stalk with a small leaf-tuft cone on top.
			var stalk: CylinderMesh = CylinderMesh.new()
			stalk.top_radius = 0.05
			stalk.bottom_radius = 0.08
			stalk.height = 2.6
			var stalk_mat: StandardMaterial3D = StandardMaterial3D.new()
			stalk_mat.albedo_color = Color(0.55, 0.62, 0.24)
			var tuft: CylinderMesh = CylinderMesh.new()
			tuft.top_radius = 0.0
			tuft.bottom_radius = 0.35
			tuft.height = 0.6
			var tuft_mat: StandardMaterial3D = StandardMaterial3D.new()
			tuft_mat.albedo_color = Color(0.35, 0.55, 0.2)
			vis = { "trunk_mesh": stalk, "trunk_mat": stalk_mat, "trunk_y": 1.3,
				"crown_mesh": tuft, "crown_mat": tuft_mat, "crown_y": 2.8 }
		TreeType.LEAF:
			# Standard trunk with a round, lighter-green sphere crown.
			var trunk: CylinderMesh = CylinderMesh.new()
			trunk.top_radius = 0.12
			trunk.bottom_radius = 0.16
			trunk.height = 1.0
			var trunk_mat: StandardMaterial3D = StandardMaterial3D.new()
			trunk_mat.albedo_color = Color(0.4, 0.27, 0.15)
			var ball: SphereMesh = SphereMesh.new()
			ball.radius = 0.9
			ball.height = 1.8
			var ball_mat: StandardMaterial3D = StandardMaterial3D.new()
			ball_mat.albedo_color = Color(0.3, 0.55, 0.2)
			vis = { "trunk_mesh": trunk, "trunk_mat": trunk_mat, "trunk_y": 0.5,
				"crown_mesh": ball, "crown_mat": ball_mat, "crown_y": 2.0 }
		_:
			# STANDARD: trunk + cone crown (unchanged look).
			var trunk_s: CylinderMesh = CylinderMesh.new()
			trunk_s.top_radius = 0.12
			trunk_s.bottom_radius = 0.16
			trunk_s.height = 1.0
			var trunk_mat_s: StandardMaterial3D = StandardMaterial3D.new()
			trunk_mat_s.albedo_color = Color(0.4, 0.27, 0.15)
			var cone: CylinderMesh = CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.8
			cone.height = 1.8
			var cone_mat: StandardMaterial3D = StandardMaterial3D.new()
			cone_mat.albedo_color = Color(0.15, 0.4, 0.16)
			vis = { "trunk_mesh": trunk_s, "trunk_mat": trunk_mat_s, "trunk_y": 0.5,
				"crown_mesh": cone, "crown_mat": cone_mat, "crown_y": 1.9 }
	_shared_visuals[t] = vis
	return vis


## StaticBody3D on layer 3 (value 4) so right-clicks can target the tree.
func _create_click_body() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("tree_resource", self)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.2, 2.8, 1.2)
	shape.shape = box
	shape.position.y = 1.4
	body.add_child(shape)
	add_child(body)
