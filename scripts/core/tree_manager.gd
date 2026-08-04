class_name TreeManager extends Node

## Registry for wild trees (child of Main). Drives growth and reproduction,
## answers nearest-tree queries and handles claiming/felling for workers.
## Trees carry a TYPE (standard/leaf/bamboo, Balance.TREE_TYPE_PARAMS) whose
## ground-dependent factors this manager feeds via the cached on_grass flag
## (set on spawn/register, refreshed on Events.terrain_deformed).
##
## Reproduction: every REPRO_INTERVAL a few random trees are sampled; the
## spawn chance per parent scales super-linearly with the number of nearby
## trees (dense woods seed faster than isolated trees). Overgrowth is kept in
## check by a local density limit, a global tree cap and the minimum spacing.

const TREE_SCENE: PackedScene = preload("res://scenes/tree_resource.tscn")

## Minimum cell distance between two trees (default; bamboo packs denser via
## its per-type min_spacing in Balance.TREE_TYPE_PARAMS).
const MIN_SPACING: int = 2
## Hard global limit (raised again for the tree types: bamboo reproduces 3x
## and would starve at the old 400 cap; no per-type limits by design).
const MAX_TREES: int = 1000
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
## Spatial index for radius counting: world-position bucket (8 m) -> trees.
## Mirrors `trees` membership exactly (trees never move once registered).
var _pos_buckets: Dictionary[Vector2i, Array] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _repro_timer: float = REPRO_INTERVAL


func setup(p_terrain_data: TerrainData, p_nav_grid: NavGrid) -> void:
	terrain_data = p_terrain_data
	nav_grid = p_nav_grid


func _ready() -> void:
	# Grass-cache invalidation on terrain deformation (Landbridge, quake, …).
	# Guarded lookup — the Events bus autoload is absent in headless tests.
	var bus: Node = get_node_or_null("/root/Events")
	if bus != null:
		bus.terrain_deformed.connect(_on_terrain_deformed)


## Recomputes the cached on_grass flag for every tree whose cell lies in the
## deformed rect (tests call this directly — no Events bus headless).
func _on_terrain_deformed(rect: Rect2i) -> void:
	if terrain_data == null:
		return
	for dz in range(rect.size.y):
		for dx in range(rect.size.x):
			var c: Vector2i = rect.position + Vector2i(dx, dz)
			var tree: TreeResource = _occupied.get(c, null)
			if tree != null and is_instance_valid(tree):
				tree.on_grass = terrain_data.is_grass(c)


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
## (new trees later always sprout small). Grass cells roll a tree type
## (bamboo/leaf/standard shares from Balance); off-grass is always standard.
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
		var type: TreeResource.TreeType = TreeResource.TreeType.STANDARD
		if terrain_data.is_grass(c):
			var roll: float = _rng.randf()
			if roll < Balance.TREE_BAMBOO_SHARE:
				type = TreeResource.TreeType.BAMBOO
			elif roll < Balance.TREE_BAMBOO_SHARE + Balance.TREE_LEAF_SHARE:
				type = TreeResource.TreeType.LEAF
		var params: Dictionary = Balance.TREE_TYPE_PARAMS[type]
		var tree: TreeResource = spawn_tree(
			c, _rng.randi_range(1, int(params.max_stage)), type)
		# Spread the growth fraction so same-stage start trees do not cross
		# their wood-stage boundaries in sync (growth is deterministic now).
		tree.set_growth(tree.growth + _rng.randf())
		placed += 1
	if placed < count:
		push_warning("Only %d of %d trees spawned" % [placed, count])


## Pure leaf/bamboo groves on grass (map start, after spawn_trees — shares the
## already-seeded _rng, so the fixed call order keeps map gen deterministic).
func spawn_groves(count: int) -> void:
	if nav_grid == null:
		return
	for i in range(count):
		var seed_cell: Vector2i = Vector2i(-1, -1)
		for attempt in range(40):
			var c: Vector2i = Vector2i(
				_rng.randi_range(0, terrain_data.size - 1),
				_rng.randi_range(0, terrain_data.size - 1))
			if nav_grid.is_cell_walkable(c) and terrain_data.is_grass(c) \
					and not _too_close(c):
				seed_cell = c
				break
		if seed_cell.x < 0:
			continue
		var type: TreeResource.TreeType = TreeResource.TreeType.LEAF \
			if _rng.randf() < 0.5 else TreeResource.TreeType.BAMBOO
		var params: Dictionary = Balance.TREE_TYPE_PARAMS[type]
		var grove_size: int = _rng.randi_range(
			Balance.TREE_GROVE_TREES_MIN, Balance.TREE_GROVE_TREES_MAX)
		for j in range(grove_size):
			if trees.size() >= MAX_TREES:
				return
			var c: Vector2i = seed_cell + Vector2i(
				_rng.randi_range(-Balance.TREE_GROVE_RADIUS, Balance.TREE_GROVE_RADIUS),
				_rng.randi_range(-Balance.TREE_GROVE_RADIUS, Balance.TREE_GROVE_RADIUS))
			if not nav_grid.is_cell_walkable(c):
				continue
			if bool(params.grass_only) and not terrain_data.is_grass(c):
				continue
			if _too_close(c, int(params.min_spacing)):
				continue
			var tree: TreeResource = spawn_tree(
				c, _rng.randi_range(1, int(params.max_stage)), type)
			tree.set_growth(tree.growth + _rng.randf())


func spawn_tree(c: Vector2i, stage: int = 0,
		type: TreeResource.TreeType = TreeResource.TreeType.STANDARD) -> TreeResource:
	var tree: TreeResource = TREE_SCENE.instantiate() as TreeResource
	tree.type = type   # BEFORE set_stage — the stage clamp is type-dependent
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
		# Standalone test nodes without a cell keep the default on_grass = true.
		if terrain_data != null:
			tree.on_grass = terrain_data.is_grass(c)
	var bucket: Vector2i = _pos_bucket(tree.position)
	if not _pos_buckets.has(bucket):
		_pos_buckets[bucket] = []
	_pos_buckets[bucket].append(tree)


func has_tree_at(c: Vector2i) -> bool:
	return _occupied.has(c)


const POS_BUCKET_SIZE: float = 8.0

static func _pos_bucket(pos: Vector3) -> Vector2i:
	return Vector2i(int(floorf(pos.x / POS_BUCKET_SIZE)),
		int(floorf(pos.z / POS_BUCKET_SIZE)))


## Number of standing trees within `radius` of `pos` (3D distance — the same
## term the old linear scans used). Bucket-indexed: only trees near `pos` are
## touched instead of the whole registry (AI plot scans call this per
## candidate cell — the linear scan was 400 distance checks each).
func count_trees_near(pos: Vector3, radius: float) -> int:
	var lo: Vector2i = _pos_bucket(Vector3(pos.x - radius, 0.0, pos.z - radius))
	var hi: Vector2i = _pos_bucket(Vector3(pos.x + radius, 0.0, pos.z + radius))
	var count: int = 0
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var bucket: Array = _pos_buckets.get(Vector2i(bx, bz), [])
			for tree in bucket:
				if is_instance_valid(tree) and tree.position.distance_to(pos) <= radius:
					count += 1
	return count


## Harvestable WOOD (not trees) within `radius` of `pos` — the sum of the
## per-stage yields, saplings and felled trees excluded. Unlike count_trees_near
## this also skips trees on another navigation island, so the answer is wood a
## walker at `pos` could actually fetch. Same bucket walk, so the cost is the
## same; the island lookup is O(1) against the cached labels.
##
## Added in 10f: "are there trees nearby" is NOT the same question as "is there
## enough wood to pay for something", and a hut must not send its crew out for a
## grove across the water (see Hut._upgrade_wood_available).
func wood_yield_near(pos: Vector3, radius: float, same_island: bool = true) -> int:
	var lo: Vector2i = _pos_bucket(Vector3(pos.x - radius, 0.0, pos.z - radius))
	var hi: Vector2i = _pos_bucket(Vector3(pos.x + radius, 0.0, pos.z + radius))
	var island: int = -1
	if same_island and nav_grid != null:
		island = nav_grid.island_at(nav_grid.nearest_walkable_cell(
			nav_grid.world_to_cell(pos)))
	var total: int = 0
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var bucket: Array = _pos_buckets.get(Vector2i(bx, bz), [])
			for tree in bucket:
				if not is_instance_valid(tree) or tree.felled_flag:
					continue
				var yield_left: int = tree.wood_yield()
				if yield_left <= 0:
					continue
				if tree.position.distance_to(pos) > radius:
					continue
				if island >= 0 and nav_grid.island_at(nav_grid.nearest_walkable_cell(
						nav_grid.world_to_cell(tree.position))) != island:
					continue
				total += yield_left
	return total


# --- Harvest areas (phase 10e) ---------------------------------------------------

## Slack for the quad tests: sub-millimetre cross products are "on the edge".
const QUAD_EPS: float = 0.001

## Point (world XZ) inside a harvest area: the Rect2 hull first (cheap reject),
## then — with a usable convex quad — four half-plane tests. Boundary points
## count as inside (a tree exactly on the drag edge belongs to the order).
## Winding-agnostic, so the caller need not normalise the corner order.
static func point_in_area(p: Vector2, area: Rect2, poly: PackedVector2Array) -> bool:
	if not area.has_point(p):
		return false
	if poly.size() != 4:
		return true
	var pos_side: bool = false
	var neg_side: bool = false
	for i in range(4):
		var a: Vector2 = poly[i]
		var side: float = (poly[(i + 1) % 4] - a).cross(p - a)
		if side > QUAD_EPS:
			pos_side = true
		elif side < -QUAD_EPS:
			neg_side = true
	return not (pos_side and neg_side)   # mixed sides = outside


## True when `poly` is a usable convex quad. The four drag corners are raycast
## onto UNEVEN terrain, so a hill can push one corner past the others and yield
## a concave or self-crossing quad — the half-plane test would then reject good
## trees. Callers drop such a quad and fall back to the Rect2 hull, which is a
## superset: the player gets slightly more than drawn, never less.
static func is_convex_quad(poly: PackedVector2Array) -> bool:
	if poly.size() != 4:
		return false
	var pos_turn: bool = false
	var neg_turn: bool = false
	for i in range(4):
		var turn: float = (poly[(i + 1) % 4] - poly[i]).cross(
			poly[(i + 2) % 4] - poly[(i + 1) % 4])
		if turn > QUAD_EPS:
			pos_turn = true
		elif turn < -QUAD_EPS:
			neg_turn = true
	return not (pos_turn and neg_turn)


## Standing trees whose position lies inside the harvest area (Rect2 hull plus
## optional convex quad). Bucket-indexed via _pos_buckets: a 20 m rectangle
## touches ~9 buckets instead of the whole registry.
func area_trees(area: Rect2,
		poly: PackedVector2Array = PackedVector2Array()) -> Array[TreeResource]:
	var out: Array[TreeResource] = []
	var lo: Vector2i = _pos_bucket(Vector3(area.position.x, 0.0, area.position.y))
	var hi: Vector2i = _pos_bucket(Vector3(area.end.x, 0.0, area.end.y))
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			for tree in _pos_buckets.get(Vector2i(bx, bz), []):
				if not is_instance_valid(tree) or tree.felled_flag:
					continue
				if point_in_area(Vector2(tree.position.x, tree.position.z), area, poly):
					out.append(tree)
	return out


## Grove radius scored around a bucket centre (bucket + its 8 neighbours, so a
## grove straddling a bucket border is not cut in half).
const GROVE_SCORE_RADIUS: float = POS_BUCKET_SIZE * 1.5
## Returned rect edge: the 3x3 bucket block, comfortably below
## Balance.HARVEST_AREA_MAX_SIDE.
const GROVE_RECT_SIDE: float = POS_BUCKET_SIZE * 3.0

## Best tree groves around `from`, strongest first, as world-space XZ rects —
## exactly the shape TribeCommands.order_chop_area takes (phase 10e, AI wood
## logistics). Opens up the existing 8 m position-bucket index: every non-empty
## bucket is one candidate, scored trees / (1 + beeline), island-filtered via one
## representative tree per bucket. Overlapping candidates are dropped so the
## caller gets distinct groves rather than three views of the same one.
func grove_candidates(from: Vector3, max_results: int = 4) -> Array[Rect2]:
	var scored: Array = []   # [score, centre] pairs
	var flat_from: Vector2 = Vector2(from.x, from.z)
	for bucket in _pos_buckets:
		var entry: Array = _pos_buckets[bucket]
		var rep: TreeResource = null
		for tree in entry:
			if is_instance_valid(tree) and not tree.felled_flag:
				rep = tree
				break
		if rep == null:
			continue
		if nav_grid != null and not nav_grid.same_island(from, rep.position):
			continue
		var centre: Vector3 = Vector3(
			(float(bucket.x) + 0.5) * POS_BUCKET_SIZE, rep.position.y,
			(float(bucket.y) + 0.5) * POS_BUCKET_SIZE)
		var count: int = count_trees_near(centre, GROVE_SCORE_RADIUS)
		if count <= 0:
			continue
		var d: float = Vector2(centre.x, centre.z).distance_to(flat_from)
		scored.append([float(count) / (1.0 + d), centre])
	if scored.is_empty():
		return []
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[Rect2] = []
	for entry in scored:
		if out.size() >= max_results:
			break
		var centre: Vector3 = entry[1]
		var flat: Vector2 = Vector2(centre.x, centre.z)
		var overlaps: bool = false
		for rect in out:
			if rect.has_point(flat):
				overlaps = true
				break
		if overlaps:
			continue
		out.append(Rect2(flat - Vector2(GROVE_RECT_SIDE, GROVE_RECT_SIDE) * 0.5,
			Vector2(GROVE_RECT_SIDE, GROVE_RECT_SIDE)))
	return out


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
		var params: Dictionary = Balance.TREE_TYPE_PARAMS[parent.type]
		var neighbors: int = _neighbor_count(parent_cell)
		if neighbors > int(params.density_limit):
			continue
		# Super-linear in the neighbour count: woods seed faster than the sum
		# of their individual trees would.
		var chance: float = clampf(
			REPRO_BASE_CHANCE * pow(float(maxi(neighbors, 1)), 1.5), 0.0, 0.2)
		# Type factor AFTER the 0.2 cap: standard/leaf keep the legacy curve
		# shape, bamboo gets headroom up to 0.6 instead of starving at the
		# clamp; off-grass factor 0 (bamboo) yields chance 0 — no special case.
		chance *= float(params.repro_grass if parent.on_grass else params.repro_off)
		if _rng.randf() > chance:
			continue
		_sprout_near(parent_cell, parent.type)


## Counts ALL types (physical cell competition — a per-type index would buy no
## gameplay): dense bamboo therefore suppresses the reproduction of neighbouring
## other types. "Bamboo crowds out" — thematically intended.
func _neighbor_count(c: Vector2i) -> int:
	var count: int = 0
	for dz in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
		for dx in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue
			if _occupied.has(c + Vector2i(dx, dz)):
				count += 1
	return count


## Sprouts inherit their parent's type (with its spacing; grass_only types
## reject non-grass candidate cells within the 8 attempts).
func _sprout_near(parent_cell: Vector2i,
		type: TreeResource.TreeType = TreeResource.TreeType.STANDARD) -> void:
	var params: Dictionary = Balance.TREE_TYPE_PARAMS[type]
	for attempt in range(8):
		var offset: Vector2i = Vector2i(
			_rng.randi_range(-SPROUT_MAX, SPROUT_MAX),
			_rng.randi_range(-SPROUT_MAX, SPROUT_MAX))
		if absi(offset.x) < SPROUT_MIN and absi(offset.y) < SPROUT_MIN:
			continue
		var c: Vector2i = parent_cell + offset
		if nav_grid == null or not nav_grid.is_cell_walkable(c):
			continue
		if bool(params.grass_only) and (terrain_data == null or not terrain_data.is_grass(c)):
			continue
		if _too_close(c, int(params.min_spacing)):
			continue
		# Natural sprouts start as a small grown tree (stage 1) — the sapling
		# stage 0 is reserved for forester plantings.
		spawn_tree(c, 1, type)
		return


func _too_close(c: Vector2i, spacing: int = MIN_SPACING) -> bool:
	for dz in range(-spacing, spacing + 1):
		for dx in range(-spacing, spacing + 1):
			if _occupied.has(c + Vector2i(dx, dz)):
				return true
	return false


# --- Queries & claiming -------------------------------------------------------------

## Nearest standing tree (walk distance, see best_tree); ignores claims.
func nearest_tree(pos: Vector3) -> TreeResource:
	return best_tree(pos, pos, INF, false)


## Nearest tree within radius that still has a free harvest slot (a tree
## supports as many parallel harvesters as it has wood, max 3); claims a slot
## for the claimer. `walker` is where the claimer actually stands (defaults
## to the search origin) — the walk-path check runs from there.
func claim_nearest_tree(pos: Vector3, radius: float, claimer: Object,
		walker: Vector3 = Vector3.INF) -> TreeResource:
	var start: Vector3 = walker if walker != Vector3.INF else pos
	var tree: TreeResource = best_tree(pos, start, radius, true)
	if tree != null:
		tree.add_claimer(claimer)
	return tree


func release_claim(tree: TreeResource, claimer: Object) -> void:
	if is_instance_valid(tree):
		tree.remove_claimer(claimer)


## Lower bound for the area walk budget so a tree one metre away is not
## rejected over a three-metre detour (mirrors Brave.CHOP_CHAIN_RADIUS).
const AREA_MIN_SEARCH_RADIUS: float = 8.0

## Claims the cheapest-to-reach claimable tree INSIDE the harvest area for
## `claimer`, walking from `walker`. Reuses best_tree wholesale — island check,
## real path verification and the negative-verdict caches all apply unchanged.
##
## The search ORIGIN is the walker, not the area centre: best_tree derives its
## walk budget from `radius` (radius x PATH_RADIUS_FACTOR), so a radius taken
## from the area's own diagonal would cap the walk at a few metres and reject
## every grove that is not already under the worker's feet. With origin ==
## walker the radius spans exactly the distance that has to be walked, and area
## containment is handled by the pre-filtered candidate pool instead. Ranking
## therefore reads "cheapest to reach from here", which also means the worker
## eats into the grove from its own side and re-ranks from the drop-off point
## after every load.
func claim_area_tree(area: Rect2, poly: PackedVector2Array, claimer: Object,
		walker: Vector3) -> TreeResource:
	var pool: Array[TreeResource] = area_trees(area, poly)
	if pool.is_empty():
		return null
	var flat: Vector2 = Vector2(walker.x, walker.z)
	var reach: float = 0.0
	for tree in pool:
		reach = maxf(reach, Vector2(tree.position.x, tree.position.z).distance_to(flat))
	var radius: float = maxf(reach + 1.0, AREA_MIN_SEARCH_RADIUS)
	var tree: TreeResource = best_tree(walker, walker, radius, true, Callable(), pool)
	if tree != null:
		tree.add_claimer(claimer)
	return tree


# --- Path-verified tree pick (bug backlog #4) ---------------------------------

## Beeline is only the RANKING of a tree pick — the actual WALK distance
## decides: a tree below a cliff can be beeline-near yet a huge ramp detour
## away. Candidates around `origin` are ranked by beeline + height malus,
## then the best few are verified with a real NavGrid path from `walker`.
## A candidate whose path is roughly its beeline is accepted immediately —
## the typical pick costs ONE cheap find_path (~10-40 us, measured); the
## expensive detour paths (~0.5 ms) only run in blocked layouts, where they
## either find the truly nearest tree or reject walks beyond
## PATH_RADIUS_FACTOR x the search radius (the job then stalls/stops instead
## of luring workers down the cliff).
const HEIGHT_DETOUR_PENALTY: float = 6.0
## Max candidates verified with a real path per pick.
const PATH_CANDIDATES: int = 4
## A path within this factor (+slack) of the beeline counts as direct.
const PATH_ACCEPT_FACTOR: float = 1.35
const PATH_ACCEPT_SLACK: float = 2.0
## Finite search radius: walks longer than this x radius are rejected.
const PATH_RADIUS_FACTOR: float = 1.5

## Negative path verdicts are cached briefly so stuck workers do not re-run
## the SAME expensive A* over and over (Seenland: the beeline-nearest trees
## sit across the lake — the walk check is a multi-ms around-the-lake A*
## every time). Keyed by walker bucket (8x8 cells) + tree cell. Positive
## verdicts are never cached.
const VERDICT_TOO_FAR: int = 1     # path exists but is beyond max_walk
const VERDICT_NO_PATH: int = 2     # A* found no path at all
## Walk distance barely changes with transient blockades -> plain TTL.
const VERDICT_TOO_FAR_TTL_MS: int = 5000
## "No path" CAN be a transient blockade (construction footprint) -> short
## TTL and instant invalidation on any walkability change (change_version).
const VERDICT_NO_PATH_TTL_MS: int = 1500
const VERDICT_CACHE_MAX: int = 4096
const VERDICT_BUCKET_SHIFT: int = 3

var _verdict_cache: Dictionary[Vector4i, Array] = {}

## Telemetry for the benchmarks (pattern: Unit.dbg_plan_*) — pure counters.
static var dbg_best_tree_calls: int = 0
static var dbg_best_tree_paths: int = 0
static var dbg_best_tree_us: int = 0


## Best tree around `origin` (site/search centre) for a walker standing at
## `walker`. `filter` (optional) may veto candidates (e.g. enemies nearby).
## `candidates` (optional) is a pre-filtered pool searched INSTEAD of the whole
## registry — area orders hand in the bucket-indexed trees inside their
## rectangle, which keeps the per-pick cost proportional to the area rather
## than to the tree count.
func best_tree(origin: Vector3, walker: Vector3, radius: float,
		claimable_only: bool, filter: Callable = Callable(),
		candidates: Array[TreeResource] = []) -> TreeResource:
	var t0: int = Time.get_ticks_usec()
	var result: TreeResource = _best_tree_inner(origin, walker, radius,
		claimable_only, filter, candidates)
	dbg_best_tree_calls += 1
	dbg_best_tree_us += Time.get_ticks_usec() - t0
	return result


func _best_tree_inner(origin: Vector3, walker: Vector3, radius: float,
		claimable_only: bool, filter: Callable = Callable(),
		candidates: Array[TreeResource] = []) -> TreeResource:
	var flat_origin: Vector2 = Vector2(origin.x, origin.z)
	var scored: Array = []   # [score, tree] pairs
	# An empty pool means "the whole registry" — the default for every caller
	# that does not restrict the search to an area.
	var pool: Array[TreeResource] = candidates if not candidates.is_empty() else trees
	for tree in pool:
		if not is_instance_valid(tree) or tree.felled_flag:
			continue
		if claimable_only and not tree.can_claim():
			continue
		var d: float = Vector2(tree.position.x, tree.position.z).distance_to(flat_origin)
		if d > radius:
			continue
		if filter.is_valid() and not filter.call(tree):
			continue
		if nav_grid != null and not nav_grid.same_island(walker, tree.position):
			continue   # unreachable outright (no ramp connects at all)
		var score: float = d + HEIGHT_DETOUR_PENALTY * absf(tree.position.y - origin.y)
		scored.append([score, tree])
	if scored.is_empty():
		return null
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# Unbounded searches (AI expansion anchor) skip the path verification:
	# cross-map A* on big maps costs milliseconds per candidate, and a rough
	# malus-ranked anchor is all the caller needs there. Workers always search
	# with a finite radius and get the exact walk check below.
	if nav_grid == null or radius == INF:
		return scored[0][1]
	var flat_walker: Vector2 = Vector2(walker.x, walker.z)
	var max_walk: float = radius * PATH_RADIUS_FACTOR
	var best: TreeResource = null
	var best_len: float = INF
	var now: int = Time.get_ticks_msec()
	var nav_version: int = nav_grid.change_version
	var walker_bucket: Vector2i = nav_grid.world_to_cell(walker)
	walker_bucket = Vector2i(walker_bucket.x >> VERDICT_BUCKET_SHIFT,
		walker_bucket.y >> VERDICT_BUCKET_SHIFT)
	# Cached negatives are skipped WITHOUT an A* and the list moves on to the
	# next candidate — the budget of PATH_CANDIDATES counts real A* runs only
	# (otherwise a handful of across-the-lake trees would eat every slot and
	# hide perfectly reachable trees further down the ranking).
	var paths_run: int = 0
	var idx: int = 0
	while idx < scored.size() and paths_run < PATH_CANDIDATES:
		var tree: TreeResource = scored[idx][1]
		idx += 1
		var tree_cell: Vector2i = _tree_cells.get(tree, Vector2i(-1, -1))
		var key: Vector4i = Vector4i(walker_bucket.x, walker_bucket.y,
			tree_cell.x, tree_cell.y)
		var cached: Array = _verdict_cache.get(key, [])
		if not cached.is_empty():
			var fresh: bool = now < int(cached[1]) and (int(cached[0]) == VERDICT_TOO_FAR
				or int(cached[2]) == nav_version)
			if fresh:
				continue   # known-bad, no A* needed
			_verdict_cache.erase(key)
		paths_run += 1
		dbg_best_tree_paths += 1
		var path: PackedVector3Array = nav_grid.find_path(walker, tree.position)
		if path.is_empty():
			_cache_verdict(key, VERDICT_NO_PATH, now + VERDICT_NO_PATH_TTL_MS, nav_version)
			continue
		var length: float = _path_length(path)
		if length > max_walk:
			# Legal but absurdly far on foot — not worth the walk.
			_cache_verdict(key, VERDICT_TOO_FAR, now + VERDICT_TOO_FAR_TTL_MS, nav_version)
			continue
		var beeline: float = Vector2(tree.position.x, tree.position.z).distance_to(flat_walker)
		if length <= beeline * PATH_ACCEPT_FACTOR + PATH_ACCEPT_SLACK:
			return tree   # direct enough — no need to check the rest
		if length < best_len:
			best_len = length
			best = tree
	return best


func _cache_verdict(key: Vector4i, verdict: int, expiry_ms: int, nav_version: int) -> void:
	# Lazy prune: the cache is purely advisory — dropping it wholesale on
	# overflow is cheaper than bookkeeping and self-heals within one TTL.
	if _verdict_cache.size() >= VERDICT_CACHE_MAX:
		_verdict_cache.clear()
	_verdict_cache[key] = [verdict, expiry_ms, nav_version]


static func _path_length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for i in range(1, path.size()):
		total += Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
	return total


## Takes one unit of wood from the tree (the tree drops a growth stage). When
## the last unit is taken the tree is deregistered and freed. Callers must
## re-validate their reference right after this call.
func harvest_tree(tree: TreeResource) -> int:
	if tree == null or not is_instance_valid(tree) or tree.felled_flag:
		return 0
	var wood: int = tree.harvest_one()
	if wood > 0 and is_inside_tree():
		var audio: Node = get_node_or_null("/root/AudioManager")
		if audio != null:
			audio.play_sfx(&"wood_chop", tree.position, 250)
	if tree.felled_flag:
		_remove_tree(tree)
	return wood


## Deregisters a tree (registry, cell index) and frees the node. Used by
## harvesting, burning down and the tornado.
func _remove_tree(tree: TreeResource) -> void:
	if not (tree in trees):
		return
	trees.erase(tree)
	var bucket: Vector2i = _pos_bucket(tree.position)
	if _pos_buckets.has(bucket):
		_pos_buckets[bucket].erase(tree)
		if _pos_buckets[bucket].is_empty():
			_pos_buckets.erase(bucket)
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
## Drowns every tree inside `rect` that the sea now covers and returns how many
## were lost. Called after a terrain deformation (phase 10a) — a flooded tree
## goes under instead of standing in the sea. Water is defined by the sea level
## alone; there is no modelled depth.
func remove_flooded(rect: Rect2i) -> int:
	if terrain_data == null:
		return 0
	var lost: int = 0
	for tree in trees.duplicate():
		if not is_instance_valid(tree):
			continue
		var c: Vector2i = Vector2i(
			int(floor(tree.position.x / TerrainData.CELL_SIZE)),
			int(floor(tree.position.z / TerrainData.CELL_SIZE)))
		if not rect.has_point(c):
			continue
		if terrain_data.get_height(tree.position.x, tree.position.z) \
				> TerrainData.SEA_LEVEL + Unit.WATER_EPS:
			continue
		_remove_tree(tree)
		lost += 1
	return lost


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
