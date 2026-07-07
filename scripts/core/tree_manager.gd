class_name TreeManager extends Node

## Registry for wild trees (child of Main). Drives growth and reproduction,
## answers nearest-tree queries and handles claiming/felling for workers.
##
## Reproduction: every REPRO_INTERVAL a few random trees are sampled; the
## spawn chance per parent scales super-linearly with the number of nearby
## trees (dense woods seed faster than isolated trees). Overgrowth is kept in
## check by a local density limit, a global tree cap and the minimum spacing.

const TREE_SCENE: PackedScene = preload("res://scenes/tree_resource.tscn")

## Minimum cell distance between two trees.
const MIN_SPACING: int = 2
## Hard global limit (raised for phase 7d so several foresters do not starve
## each other; natural reproduction shares the same cap unobtrusively).
const MAX_TREES: int = 400
const REPRO_INTERVAL: float = 5.0
const REPRO_BASE_CHANCE: float = 0.004
## Neighbourhood radius (cells, Chebyshev) for density/chance.
const NEIGHBOR_RADIUS: int = 8
## No reproduction when a parent already has this many neighbours.
const DENSITY_LIMIT: int = 6
## New trees sprout 2..5 cells away from their parent.
const SPROUT_MIN: int = 2
const SPROUT_MAX: int = 5

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null

var trees: Array[TreeResource] = []
var _occupied: Dictionary[Vector2i, TreeResource] = {}
var _tree_cells: Dictionary[TreeResource, Vector2i] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _repro_timer: float = REPRO_INTERVAL


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	# Burning trees are destroyed when they finish burning; the rest grow.
	# Snapshot so removing a spent tree mid-loop does not skip entries.
	for tree in trees.duplicate():
		if not is_instance_valid(tree):
			continue
		if tree.is_burning():
			if tree.burn_tick(delta):
				_remove_tree(tree)
			continue
		tree.grow_tick(delta)
	_repro_timer -= delta
	if _repro_timer <= 0.0:
		_repro_timer += REPRO_INTERVAL
		_reproduce()


# --- Initial distribution ------------------------------------------------------

## Deterministic start distribution; start trees get random grown stages
## (new trees later always sprout small).
func spawn_trees(count: int, p_seed: int) -> void:
	if nav_grid == null:
		return
	_rng.seed = p_seed
	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 60:
		attempts += 1
		var c: Vector2i = Vector2i(
			_rng.randi_range(0, terrain_data.size - 1),
			_rng.randi_range(0, terrain_data.size - 1))
		if not nav_grid.is_cell_walkable(c):
			continue
		if _too_close(c):
			continue
		spawn_tree(c, _rng.randi_range(1, TreeResource.MAX_STAGE))
		placed += 1
	if placed < count:
		push_warning("Only %d of %d trees spawned" % [placed, count])


func spawn_tree(c: Vector2i, stage: int = 0) -> TreeResource:
	var tree: TreeResource = TREE_SCENE.instantiate() as TreeResource
	tree.set_stage(stage)
	tree.position = nav_grid.cell_to_world(c)
	add_child(tree)
	register(tree, c)
	return tree


## Registers a tree (also used directly by tests with standalone nodes).
func register(tree: TreeResource, c: Vector2i = Vector2i(-1, -1)) -> void:
	if tree in trees:
		return
	trees.append(tree)
	if c.x >= 0:
		_occupied[c] = tree
		_tree_cells[tree] = c


func has_tree_at(c: Vector2i) -> bool:
	return _occupied.has(c)


# --- Reproduction ----------------------------------------------------------------

func _reproduce() -> void:
	if trees.is_empty() or trees.size() >= MAX_TREES:
		return
	var samples: int = mini(12, trees.size())
	for i in range(samples):
		if trees.size() >= MAX_TREES:
			return
		var parent: TreeResource = trees[_rng.randi_range(0, trees.size() - 1)]
		# Saplings (stage 0) and burning trees do not reproduce.
		if parent.stage <= 0 or parent.is_burning():
			continue
		var parent_cell: Vector2i = _tree_cells.get(parent, Vector2i(-1, -1))
		if parent_cell.x < 0:
			continue
		var neighbors: int = _neighbor_count(parent_cell)
		if neighbors > DENSITY_LIMIT:
			continue
		# Super-linear in the neighbour count: woods seed faster than the sum
		# of their individual trees would.
		var chance: float = clampf(
			REPRO_BASE_CHANCE * pow(float(maxi(neighbors, 1)), 1.5), 0.0, 0.2)
		if _rng.randf() > chance:
			continue
		_sprout_near(parent_cell)


func _neighbor_count(c: Vector2i) -> int:
	var count: int = 0
	for dz in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
		for dx in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue
			if _occupied.has(c + Vector2i(dx, dz)):
				count += 1
	return count


func _sprout_near(parent_cell: Vector2i) -> void:
	for attempt in range(8):
		var offset: Vector2i = Vector2i(
			_rng.randi_range(-SPROUT_MAX, SPROUT_MAX),
			_rng.randi_range(-SPROUT_MAX, SPROUT_MAX))
		if absi(offset.x) < SPROUT_MIN and absi(offset.y) < SPROUT_MIN:
			continue
		var c: Vector2i = parent_cell + offset
		if nav_grid == null or not nav_grid.is_cell_walkable(c):
			continue
		if _too_close(c):
			continue
		# Natural sprouts start as a small grown tree (stage 1) — the sapling
		# stage 0 is reserved for forester plantings.
		spawn_tree(c, 1)
		return


func _too_close(c: Vector2i) -> bool:
	for dz in range(-MIN_SPACING, MIN_SPACING + 1):
		for dx in range(-MIN_SPACING, MIN_SPACING + 1):
			if _occupied.has(c + Vector2i(dx, dz)):
				return true
	return false


# --- Queries & claiming -------------------------------------------------------------

## Nearest standing tree (XZ distance); ignores claims. Null if none.
func nearest_tree(pos: Vector3) -> TreeResource:
	return _nearest(pos, INF, false)


## Nearest tree within radius that still has a free harvest slot (a tree
## supports as many parallel harvesters as it has wood, max 3); claims a slot
## for the claimer.
func claim_nearest_tree(pos: Vector3, radius: float, claimer: Object) -> TreeResource:
	var tree: TreeResource = _nearest(pos, radius, true)
	if tree != null:
		tree.add_claimer(claimer)
	return tree


func release_claim(tree: TreeResource, claimer: Object) -> void:
	if is_instance_valid(tree):
		tree.remove_claimer(claimer)


func _nearest(pos: Vector3, radius: float, claimable_only: bool) -> TreeResource:
	var best: TreeResource = null
	var best_dist: float = radius * radius
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for tree in trees:
		if not is_instance_valid(tree) or tree.felled_flag:
			continue
		if claimable_only and not tree.can_claim():
			continue
		var d: float = Vector2(tree.position.x, tree.position.z).distance_squared_to(flat)
		if d < best_dist:
			best_dist = d
			best = tree
	return best


## Takes one unit of wood from the tree (the tree drops a growth stage). When
## the last unit is taken the tree is deregistered and freed. Callers must
## re-validate their reference right after this call.
func harvest_tree(tree: TreeResource) -> int:
	if tree == null or not is_instance_valid(tree) or tree.felled_flag:
		return 0
	var wood: int = tree.harvest_one()
	if tree.felled_flag:
		_remove_tree(tree)
	return wood


## Deregisters a tree (registry, cell index) and frees the node. Used by
## harvesting, burning down and the tornado.
func _remove_tree(tree: TreeResource) -> void:
	if not (tree in trees):
		return
	trees.erase(tree)
	var c: Vector2i = _tree_cells.get(tree, Vector2i(-1, -1))
	_tree_cells.erase(tree)
	if c.x >= 0:
		_occupied.erase(c)
	if tree.is_inside_tree():
		tree.queue_free()
	else:
		tree.free()


# --- Forester queries (phase 7d) --------------------------------------------

## Number of standing trees whose cell lies within `radius` (Chebyshev cells)
## of `center` cell — the forester's local density readout.
func trees_in_area(center: Vector2i, radius: int) -> int:
	var count: int = 0
	for c: Vector2i in _occupied.keys():
		if maxi(absi(c.x - center.x), absi(c.y - center.y)) <= radius:
			count += 1
	return count


## True when a sapling may be planted on `cell`: walkable (excludes water,
## steep ground and building footprints), free of trees and with no tree within
## `spacing` cells (forester plantings may pack denser than the wild MIN_SPACING).
func can_plant_at(cell: Vector2i, spacing: int) -> bool:
	if nav_grid == null or not nav_grid.is_cell_walkable(cell):
		return false
	if _occupied.has(cell):
		return false
	for dz in range(-spacing, spacing + 1):
		for dx in range(-spacing, spacing + 1):
			if _occupied.has(cell + Vector2i(dx, dz)):
				return false
	return true


# --- Fire & tornado (phase 7d) ----------------------------------------------

## Ignites every standing tree within `radius` (world XZ) — fire spells and
## lava call this. Returns how many trees were freshly set alight.
func ignite_in_radius(pos: Vector3, radius: float) -> int:
	var flat: Vector2 = Vector2(pos.x, pos.z)
	var count: int = 0
	for tree in trees:
		if not is_instance_valid(tree) or tree.felled_flag or tree.is_burning():
			continue
		if Vector2(tree.position.x, tree.position.z).distance_to(flat) <= radius:
			tree.ignite()
			count += 1
	return count


## Destroys every standing tree within `radius` (world XZ) outright — the
## tornado shreds trees (no wood, no burn).
func destroy_in_radius(pos: Vector3, radius: float) -> void:
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for tree in trees.duplicate():
		if not is_instance_valid(tree):
			continue
		if Vector2(tree.position.x, tree.position.z).distance_to(flat) <= radius:
			_remove_tree(tree)


## Uproots every tree within `radius`: removes them and returns one entry per
## tree {position, wood} (wood = its current yield) so the caller can whirl each
## one away (the tornado turns them into flying wood — saplings carry 0 wood).
func uproot_in_radius(pos: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for tree in trees.duplicate():
		if not is_instance_valid(tree):
			continue
		if Vector2(tree.position.x, tree.position.z).distance_to(flat) <= radius:
			out.append({"position": tree.position, "wood": tree.wood_yield()})
			_remove_tree(tree)
	return out
