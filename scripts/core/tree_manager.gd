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
## Hard global limit.
const MAX_TREES: int = 250
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
	for tree in trees:
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
			_rng.randi_range(0, TerrainData.SIZE - 1),
			_rng.randi_range(0, TerrainData.SIZE - 1))
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
		spawn_tree(c, 0)  # new trees always start small
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
		trees.erase(tree)
		var c: Vector2i = _tree_cells.get(tree, Vector2i(-1, -1))
		_tree_cells.erase(tree)
		if c.x >= 0:
			_occupied.erase(c)
		if tree.is_inside_tree():
			tree.queue_free()
		else:
			tree.free()
	return wood
