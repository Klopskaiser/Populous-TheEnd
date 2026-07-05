class_name TreeManager extends Node

## Registry for wild trees (child of Main). Spawns the initial seed-based
## tree distribution and answers nearest_tree() queries for gathering braves.
## Depleted trees are deregistered here; nodes inside the scene tree are also
## queue_free'd (standalone test nodes stay owned by their creator).

const TREE_SCENE: PackedScene = preload("res://scenes/tree_resource.tscn")
## Minimum cell distance between two spawned trees.
const MIN_SPACING: int = 2

var terrain_data: TerrainData = null
var nav_grid: NavGrid = null

var trees: Array[TreeResource] = []
var _occupied: Dictionary[Vector2i, TreeResource] = {}


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid


## Deterministic tree distribution on walkable cells.
func spawn_trees(count: int, p_seed: int) -> void:
	if nav_grid == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = p_seed
	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 60:
		attempts += 1
		var c: Vector2i = Vector2i(
			rng.randi_range(0, TerrainData.SIZE - 1),
			rng.randi_range(0, TerrainData.SIZE - 1))
		if not nav_grid.is_cell_walkable(c):
			continue
		if _too_close(c):
			continue
		spawn_tree(c)
		placed += 1
	if placed < count:
		push_warning("Only %d of %d trees spawned" % [placed, count])


func _too_close(c: Vector2i) -> bool:
	for dz in range(-MIN_SPACING, MIN_SPACING + 1):
		for dx in range(-MIN_SPACING, MIN_SPACING + 1):
			if _occupied.has(c + Vector2i(dx, dz)):
				return true
	return false


func spawn_tree(c: Vector2i) -> TreeResource:
	var tree: TreeResource = TREE_SCENE.instantiate() as TreeResource
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
	tree.depleted.connect(_on_tree_depleted)


func has_tree_at(c: Vector2i) -> bool:
	return _occupied.has(c)


## Nearest non-empty tree (XZ distance); null if none is left.
func nearest_tree(pos: Vector3) -> TreeResource:
	var best: TreeResource = null
	var best_dist: float = INF
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for tree in trees:
		if not is_instance_valid(tree) or tree.wood_remaining <= 0:
			continue
		var d: float = Vector2(tree.position.x, tree.position.z).distance_squared_to(flat)
		if d < best_dist:
			best_dist = d
			best = tree
	return best


func _on_tree_depleted(tree: TreeResource) -> void:
	trees.erase(tree)
	for c in _occupied.keys():
		if _occupied[c] == tree:
			_occupied.erase(c)
			break
	if tree.is_inside_tree():
		tree.queue_free()
