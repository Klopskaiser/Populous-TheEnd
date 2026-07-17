class_name TreeResource extends Node3D

## Wild/planted tree with five growth stages: stage 0 is a SAPLING (0 wood, a
## bare vertical stick planted by the forester) that cannot reproduce; stages
## 1..4 are the four grown stages (klein -> groß) yielding 1/2/3/4 wood. Wood is
## harvested ONE unit at a time: each harvest drops the tree a growth stage (a
## big tree takes four trips); the last unit removes it. Several workers may
## harvest the same tree at once (as many as it has wood, so max 4 on a big
## tree). Growth and reproduction are driven by the TreeManager. Growth happens
## at RANDOM intervals around GROWTH_TIME (the average is unchanged). Trees do
## not block the NavGrid (thin obstacles). Fire (spells, lava) IGNITES a tree:
## it burns down and is destroyed completely, yielding no wood.

const MAX_STAGE: int = 4
## Remaining wood per stage: 0 = sapling (0), then 1/2/3/4.
const YIELDS: Array[int] = [0, 1, 2, 3, 4]
## Stage 0 is a small stick; stages 1..4 scale up like before.
const STAGE_SCALES: Array[float] = [0.28, 0.35, 0.55, 0.8, 1.0]
## Average seconds per growth stage; the actual per-stage interval is randomised
## around this mean (see _next_growth_time).
const GROWTH_TIME: float = 75.0
## Spread factor for the randomised growth interval (mean stays GROWTH_TIME).
const GROWTH_SPREAD: float = 0.5
## How long a burning tree stays alight before it is destroyed.
const BURN_TIME: float = 1.8

var stage: int = 0
var growth_timer: float = GROWTH_TIME
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
	stage = clampi(p_stage, 0, MAX_STAGE)
	scale = Vector3.ONE * STAGE_SCALES[stage]
	# The sapling (stage 0) is a bare stick — no crown yet.
	if _crown != null:
		_crown.visible = stage >= 1


## Called by the TreeManager tick; grows one stage when the (randomised) timer
## runs out. Saplings grow like any other tree — they just have one extra stage.
func grow_tick(delta: float) -> void:
	if stage >= MAX_STAGE:
		return
	growth_timer -= delta
	if growth_timer <= 0.0:
		growth_timer += _next_growth_time()
		set_stage(stage + 1)


## Randomised interval around the mean GROWTH_TIME (uniform, so the average
## growth rate is unchanged from the old fixed cadence).
func _next_growth_time() -> float:
	return GROWTH_TIME * (1.0 + randf_range(-GROWTH_SPREAD, GROWTH_SPREAD))


# --- Burning (fire spells / lava) ---------------------------------------------

func is_burning() -> bool:
	return _burn_time > 0.0


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
	scale = Vector3.ONE * STAGE_SCALES[stage] * maxf(t, 0.05)
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


## User-provided model (assets/models/trees/tree.glb) when present, otherwise
## the procedural trunk+cone. Growth stages scale the whole node either way;
## the burn flicker/crown-hiding only applies to the procedural crown (the glb
## still shrinks while burning — _crown/_crown_mat stay null-guarded).
func _create_visuals() -> void:
	var model: Node3D = AssetLibrary.instantiate_model("models/trees/tree.glb")
	if model != null:
		add_child(model)
		return
	var trunk: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	trunk.mesh = cyl
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.4, 0.27, 0.15)
	trunk.material_override = _trunk_mat
	trunk.position.y = 0.5
	add_child(trunk)

	_crown = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 1.8
	_crown.mesh = cone
	_crown_mat = StandardMaterial3D.new()
	_crown_mat.albedo_color = Color(0.15, 0.4, 0.16)
	_crown.material_override = _crown_mat
	_crown.position.y = 1.9
	add_child(_crown)


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
