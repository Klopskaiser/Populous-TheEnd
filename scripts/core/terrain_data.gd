class_name TerrainData extends RefCounted

## Single source of truth for terrain heights, walkability and runtime deformation.
##
## Heightmap grid: `size`x`size` cells, `verts`x`verts` vertices, 1.0 world metre
## per cell. `SIZE` below is only the DEFAULT/test size — the actual skirmish map
## edge lengths live in `MapGenerator` (STANDARD_SIZE / LARGE_SIZE) and are passed
## to _init. Mesh, collision and navigation are all derived from this data. Pure
## data class (no Node dependency) so it is fully headless-testable.
##
## Phase 10j — SCHEIBENWELT: the world is a DISC inscribed in the square grid.
## Everything outside that disc is the void: no ground, no walkable cell, no mesh.
## The mask lives in `is_walkable()`/`is_grass()`, which makes `NavGrid`'s single
## solidity writer pull it into A*, the PathWorker clone, the vehicle grid, island
## labels, tree/unit spawns and `can_place_at` for free.

const SIZE: int = 128          # DEFAULT cells per side (tests; maps use MapGenerator)
const VERTS: int = SIZE + 1    # DEFAULT vertices per side (129)
const CELL_SIZE: float = 1.0   # world metres per cell
const SEA_LEVEL: float = 2.0   # water line
const MAX_SLOPE: float = 1.5   # max corner height delta for a walkable cell (metres)

## Disc radius as a fraction of the half edge length (1.0 = inscribed). The map
## sizes are chosen so the disc area matches the old square area, so there is no
## reason to shrink this further.
const DISC_RADIUS_FRAC: float = 1.0

## Grass band (single source of truth for visuals AND gameplay): cells whose
## height falls in [GRASS_MIN, GRASS_MAX) read as grass — below is sand/beach,
## above is rock. Terrain/minimap colouring and the tree-type rules (leaf trees
## and bamboo, phase 7d+) all derive from these two thresholds.
const GRASS_MIN: float = SEA_LEVEL + 1.5
const GRASS_MAX: float = SEA_LEVEL + 8.0

# Island generation tuning
const BASE_LAND: float = 6.0
const NOISE_AMP: float = 6.0
const NOISE_FREQ: float = 0.03

## Actual grid dimensions of THIS instance (defaults to the 128 map).
var size: int = SIZE
var verts: int = VERTS

var heights: PackedFloat32Array = PackedFloat32Array()

## Cell-indexed disc mask (1 = inside), index `z * size + x`. Precomputed ONCE in
## _init and read INLINE by `is_walkable()`/`is_grass()` rather than through
## `in_disc()`.
##
## That is not premature micro-optimisation, it is measured: `NavGrid._init` runs
## `update_region` over the whole grid, and `_refresh_vehicle_region` asks
## `is_walkable` about ~17 cells per cell, so a 128 grid triggers ~280 000 calls per
## NavGrid. Routing each through one extra GDScript method call cost the test suite
## 79 s -> 170 s (a uniform 2.5x across every file). A single indexed byte read
## brings it back. `size` never changes after _init, so the mask cannot go stale.
var _disc_mask: PackedByteArray = PackedByteArray()
## Disc geometry in world units, for the float-space queries (`has_ground`).
var _disc_center: float = 0.0
var _disc_radius: float = 0.0
var _disc_radius_sq: float = 0.0
## `has_ground()` is deliberately half a cell diagonal MORE generous than
## `in_disc()`: a unit standing on the outer corner of a legitimately walkable rim
## cell must still have ground under it, otherwise a roll would drop it into the
## void while it is provably still on the map.
var _ground_radius_sq: float = 0.0

func _init(p_size: int = SIZE) -> void:
	size = maxi(p_size, 1)
	verts = size + 1
	heights.resize(verts * verts)
	_disc_center = float(size) * 0.5 * CELL_SIZE
	# Half a cell short of the inscribed circle so the rim never coincides with
	# the heightmap's own array edge.
	_disc_radius = maxf(
		float(size) * 0.5 * DISC_RADIUS_FRAC * CELL_SIZE - CELL_SIZE * 0.5, CELL_SIZE)
	_disc_radius_sq = _disc_radius * _disc_radius
	var ground_r: float = _disc_radius + CELL_SIZE * 0.75
	_ground_radius_sq = ground_r * ground_r
	_disc_mask.resize(size * size)
	for z in range(size):
		var dz: float = (float(z) + 0.5) * CELL_SIZE - _disc_center
		var dz2: float = dz * dz
		var row: int = z * size
		for x in range(size):
			var dx: float = (float(x) + 0.5) * CELL_SIZE - _disc_center
			_disc_mask[row + x] = 1 if dx * dx + dz2 <= _disc_radius_sq else 0


## World-space centre (same on both axes) and radius of the walkable disc.
func disc_center() -> float:
	return _disc_center


func disc_radius() -> float:
	return _disc_radius


## True when the CENTRE of this cell lies inside the disc, bounds included — the
## complete "is this a real cell?" predicate. `heights` is vertex-indexed while
## walkability is cell-indexed; the mask belongs on the cell side, otherwise the rim
## is off by one. The hot callers (`is_walkable`, `is_grass`) read `_disc_mask`
## inline instead of going through here — see the field's comment.
func in_disc(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= size or cell.y < 0 or cell.y >= size:
		return false
	return _disc_mask[cell.y * size + cell.x] != 0


## Radius of the VISIBLE rim — the full inscribed circle, half a cell further out than
## the walkability radius. Every walkable cell (centre within `disc_radius()`) is thus
## exactly covered by it, so the visual edge never cuts into playable ground.
func rim_radius() -> float:
	return float(size) * 0.5 * DISC_RADIUS_FRAC * CELL_SIZE


## True for a vertex on the OUTER RING of the meshed cell set: it belongs to at least one
## in-disc cell and at least one cell outside. Exactly the vertices that form the visible
## silhouette.
func is_boundary_vertex(vx: int, vz: int) -> bool:
	var inside: int = 0
	var outside: int = 0
	for dz in [-1, 0]:
		for dx in [-1, 0]:
			if in_disc(Vector2i(vx + dx, vz + dz)):
				inside += 1
			else:
				outside += 1
	return inside > 0 and outside > 0


## World XZ of a mesh vertex, projected onto the rim circle if it is a boundary vertex.
##
## This is what makes the edge round. Cell culling alone leaves a staircase with one-metre
## steps, which reads as coarse jags on a 144 m disc (user report: "die Zacken sind extrem
## groß"). Projecting the outer vertex ring onto the circle turns that staircase into a
## polygon whose corners all sit ON the rim — chords of about a metre, so the silhouette is
## smooth. WALKABILITY stays strictly cell-based and untouched; this is presentation only,
## and since walkable cell centres reach at most `disc_radius()` (half a cell inside
## `rim_radius()`), no unit can ever stand past the visible edge.
##
## It projects BOTH WAYS, and that is the whole point. A first attempt only pulled
## vertices that lay OUTSIDE the circle inward — but measured against a 144 map the
## boundary ring sits at 70.0 to 72.1 m, so almost every vertex is INSIDE and was left on
## the grid. The staircase survived, and the sea (cut on the circle at 72) overhung the
## land by up to 2 m, which is the blue layer that showed up under the land at the rim.
##
## `TerrainRim` builds from these same projected positions, so the mesh edge and the rock
## flank cannot drift apart.
func vertex_mesh_xz(vx: int, vz: int) -> Vector2:
	var p: Vector2 = Vector2(float(vx) * CELL_SIZE, float(vz) * CELL_SIZE)
	if not is_boundary_vertex(vx, vz):
		return p
	var centre: Vector2 = Vector2(_disc_center, _disc_center)
	var d: Vector2 = p - centre
	var dist: float = d.length()
	if dist < 0.000001:
		return p
	return centre + d / dist * rim_radius()


## Vertex-side disc test — for the rim skirt mesh and `average_height()`. A vertex
## counts as inside when it belongs to at least one in-disc CELL, so the outer
## vertices of a walkable rim cell stay writable (that is the vertex-vs-cell layout
## trap: `heights` is verts², walkability size²).
func vertex_in_disc(vx: int, vz: int) -> bool:
	return in_disc(Vector2i(vx - 1, vz - 1)) or in_disc(Vector2i(vx, vz - 1)) \
		or in_disc(Vector2i(vx - 1, vz)) or in_disc(Vector2i(vx, vz))


## True when ground exists at this world position. Outside the disc is the void.
## THIS is the core of phase 10j: `get_height()` clamps its input coordinates and
## therefore reports the rim height infinitely far outwards, which is why before
## 10j there was ground EVERYWHERE — the real cause of the shaman-outside-the-map
## report that commit 95b0e73 papered over with an invisible wall. Without this
## query nobody falls into space.
func has_ground(world_x: float, world_z: float) -> bool:
	var dx: float = world_x - _disc_center
	var dz: float = world_z - _disc_center
	return dx * dx + dz * dz <= _ground_radius_sq


## `x`/`z` pulled RADIALLY into the disc, one metre inside the rim — the clamp for
## anything that wanders on its own (tornado, swarm, debris). STATIC with a null
## fallback because the callers hold an OPTIONAL terrain reference: written out by
## hand, that fallback is easy to get wrong, and `TerrainData.SIZE` is the DEFAULT
## 128, not this map's size. Exactly that mistake pinned tornadoes on the large
## maps (Seenland/Bergpass) to the 127-line — a cast past it teleported the funnel
## up to 100 m and it then jittered against the invisible wall (user report:
## Tornados am See). Before 10j this was `world_clamp_limit()` and clamped to the
## square; the wall it clamped against no longer exists.
## `margin` is how far INSIDE the rim the clamp bites; a NEGATIVE margin allows
## overshoot past it, which is what the camera rig uses so the edge can be viewed
## head-on (see CameraRig.PAN_RIM_OVERSHOOT).
static func clamp_into_world(td: TerrainData, x: float, z: float,
		margin: float = CELL_SIZE * 1.5) -> Vector2:
	var s: int = td.size if td != null else SIZE
	var c: float = float(s) * 0.5 * CELL_SIZE
	var r: float = maxf(
		float(s) * 0.5 * DISC_RADIUS_FRAC * CELL_SIZE - margin, CELL_SIZE)
	var d: Vector2 = Vector2(x - c, z - c)
	var dist: float = d.length()
	if dist <= r or dist < 0.000001:
		return Vector2(x, z)
	return Vector2(c, c) + d / dist * r


## `cell` pulled radially into the disc — the entry clamp for every "nearest
## walkable cell" ring search. A plain rectangle clamp is NOT enough on a disc: the
## corner of a 288-cell map is 59.6 cells away from the nearest disc cell, far
## beyond `MAX_SNAP_RADIUS = 32`, so a void query used to return (-1, -1). That
## answer then travelled on as `island_at() == -1` into
## `AIController._home_islands()`, whose empty-set bail-outs switch the AI's
## build-site guard off without a word. STATIC and size-driven so the PathWorker
## clone (which holds no TerrainData) can use the very same rule.
static func clamp_cell_into_disc(cell: Vector2i, p_size: int) -> Vector2i:
	var s: int = maxi(p_size, 1)
	var c: float = float(s) * 0.5 * CELL_SIZE
	# One full cell inside the rim, so the cell we land on is safely in the disc.
	var r: float = maxf(
		float(s) * 0.5 * DISC_RADIUS_FRAC * CELL_SIZE - CELL_SIZE, CELL_SIZE)
	var dx: float = (float(cell.x) + 0.5) * CELL_SIZE - c
	var dz: float = (float(cell.y) + 0.5) * CELL_SIZE - c
	var d2: float = dx * dx + dz * dz
	if d2 > r * r and d2 > 0.000001:
		# Only the (rare) out-of-disc case pays for the square root.
		var k: float = r / sqrt(d2)
		dx *= k
		dz *= k
	return Vector2i(
		clampi(int(floor((dx + c) / CELL_SIZE)), 0, s - 1),
		clampi(int(floor((dz + c) / CELL_SIZE)), 0, s - 1))


## Centre CELL of the map. Same trap as clamp_into_world: a hand-written
## `TerrainData.SIZE / 2` is the DEFAULT 128er centre (64, 64) and lands in the
## north-west quarter of a 256-cell map. Used by the debug/test setups, which
## place their armies relative to the map centre.
static func center_cell(td: TerrainData) -> Vector2i:
	var s: int = td.size if td != null else SIZE
	return Vector2i(s / 2, s / 2)


# --- Vertex access -----------------------------------------------------------

func vertex_height(x: int, z: int) -> float:
	x = clampi(x, 0, verts - 1)
	z = clampi(z, 0, verts - 1)
	return heights[z * verts + x]


func set_vertex_height(x: int, z: int, h: float) -> void:
	if x < 0 or x >= verts or z < 0 or z >= verts:
		return
	heights[z * verts + x] = h


## Map-wide mean surface height over maxf(h, SEA_LEVEL) — the airship's
## cruise reference ("normal ground"). Computed lazily ONCE and cached:
## runtime deformation (spells) shifts the map-wide mean by a negligible
## amount, so no recompute on deform.
var _average_height: float = -INF


func average_height() -> float:
	if _average_height == -INF:
		var sum: float = 0.0
		var count: int = 0
		for vz in range(verts):
			for vx in range(verts):
				# The void has no height. Averaging it in (as SEA_LEVEL) would drag
				# the airship's cruise altitude down by a fifth on every map.
				if not vertex_in_disc(vx, vz):
					continue   # lazy + cached once, so the call cost is irrelevant here
				sum += maxf(heights[vz * verts + vx], SEA_LEVEL)
				count += 1
		_average_height = sum / float(maxi(count, 1))
	return _average_height


## Bilinearly interpolated height at an arbitrary world position.
## Central for Y-snapping of units/buildings (no raycast needed).
func get_height(world_x: float, world_z: float) -> float:
	var fx: float = clampf(world_x / CELL_SIZE, 0.0, float(size))
	var fz: float = clampf(world_z / CELL_SIZE, 0.0, float(size))
	var x0: int = clampi(int(floor(fx)), 0, verts - 2)
	var z0: int = clampi(int(floor(fz)), 0, verts - 2)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heights[z0 * verts + x0]
	var h10: float = heights[z0 * verts + x0 + 1]
	var h01: float = heights[(z0 + 1) * verts + x0]
	var h11: float = heights[(z0 + 1) * verts + x0 + 1]
	var top: float = lerpf(h00, h10, tx)
	var bottom: float = lerpf(h01, h11, tx)
	return lerpf(top, bottom, tz)


# --- Deformation -------------------------------------------------------------

## Raises terrain around a world-space center with a smoothstep falloff.
## Returns the cell rectangle that was affected (for partial mesh/collision/nav
## rebuilds). This is the core of the Landbridge spell.
func raise_area(center: Vector2, radius: float, amount: float) -> Rect2i:
	if radius <= 0.0:
		return Rect2i()
	var min_vx: int = clampi(int(floor((center.x - radius) / CELL_SIZE)), 0, verts - 1)
	var max_vx: int = clampi(int(ceil((center.x + radius) / CELL_SIZE)), 0, verts - 1)
	var min_vz: int = clampi(int(floor((center.y - radius) / CELL_SIZE)), 0, verts - 1)
	var max_vz: int = clampi(int(ceil((center.y + radius) / CELL_SIZE)), 0, verts - 1)

	var changed_min_x: int = verts
	var changed_min_z: int = verts
	var changed_max_x: int = -1
	var changed_max_z: int = -1

	for vz in range(min_vz, max_vz + 1):
		for vx in range(min_vx, max_vx + 1):
			var wx: float = float(vx) * CELL_SIZE
			var wz: float = float(vz) * CELL_SIZE
			var dist: float = Vector2(wx, wz).distance_to(center)
			if dist > radius:
				continue
			var t: float = clampf((radius - dist) / radius, 0.0, 1.0)
			var falloff: float = t * t * (3.0 - 2.0 * t)  # smoothstep
			heights[vz * verts + vx] += amount * falloff
			changed_min_x = mini(changed_min_x, vx)
			changed_min_z = mini(changed_min_z, vz)
			changed_max_x = maxi(changed_max_x, vx)
			changed_max_z = maxi(changed_max_z, vz)

	if changed_max_x < 0:
		return Rect2i()

	# A cell is affected if any of its 4 corner vertices moved. Vertex vx belongs
	# to cells (vx-1) and (vx); clamp the resulting cell range to the grid.
	var cell_min_x: int = clampi(changed_min_x - 1, 0, size - 1)
	var cell_min_z: int = clampi(changed_min_z - 1, 0, size - 1)
	var cell_max_x: int = clampi(changed_max_x, 0, size - 1)
	var cell_max_z: int = clampi(changed_max_z, 0, size - 1)
	return Rect2i(cell_min_x, cell_min_z,
		cell_max_x - cell_min_x + 1, cell_max_z - cell_min_z + 1)


## Computes the target heights of a corridor from `from` to `to` (world XZ)
## GRADED onto a straight height profile interpolated between height_from and
## height_to: dips are raised AND bumps are shaved, producing a smooth,
## walkable ramp/causeway (already-straight ground yields no targets at all).
## Beyond half_width the grading blends out smoothly over `edge` metres.
## Returns {"indices": PackedInt32Array, "targets": PackedFloat32Array,
## "rect": Rect2i} WITHOUT touching the heightmap — raise_line applies it
## instantly, the Landbridge morph interpolates toward it over time.
func line_raise_targets(from: Vector2, to: Vector2, half_width: float,
		height_from: float, height_to: float, edge: float = 1.5,
		forward_only: bool = false) -> Dictionary:
	var axis: Vector2 = to - from
	var len2: float = axis.length_squared()
	var reach: float = half_width + edge
	var min_vx: int = clampi(int(floor((minf(from.x, to.x) - reach) / CELL_SIZE)), 0, verts - 1)
	var max_vx: int = clampi(int(ceil((maxf(from.x, to.x) + reach) / CELL_SIZE)), 0, verts - 1)
	var min_vz: int = clampi(int(floor((minf(from.y, to.y) - reach) / CELL_SIZE)), 0, verts - 1)
	var max_vz: int = clampi(int(ceil((maxf(from.y, to.y) + reach) / CELL_SIZE)), 0, verts - 1)

	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	var changed_min_x: int = verts
	var changed_min_z: int = verts
	var changed_max_x: int = -1
	var changed_max_z: int = -1

	for vz in range(min_vz, max_vz + 1):
		for vx in range(min_vx, max_vx + 1):
			var p: Vector2 = Vector2(float(vx) * CELL_SIZE, float(vz) * CELL_SIZE)
			var s: float = 0.0
			if len2 > 0.000001:
				s = (p - from).dot(axis) / len2
			if forward_only and s < 0.0:
				continue   # nur Gelände VOR dem Startpunkt planieren (keine Kappe hinter der Schamanin)
			var t: float = clampf(s, 0.0, 1.0)
			var d: float = p.distance_to(from + axis * t)
			if d > reach:
				continue
			var profile: float = lerpf(height_from, height_to, t)
			var blend: float = 1.0
			if d > half_width:
				var e: float = clampf((reach - d) / edge, 0.0, 1.0)
				blend = e * e * (3.0 - 2.0 * e)  # smoothstep to the old terrain
			var idx: int = vz * verts + vx
			var current: float = heights[idx]
			var nh: float = lerpf(current, profile, blend)
			if absf(nh - current) <= 0.01:
				continue   # already on the line: nothing to grade
			indices.append(idx)
			targets.append(nh)
			changed_min_x = mini(changed_min_x, vx)
			changed_min_z = mini(changed_min_z, vz)
			changed_max_x = maxi(changed_max_x, vx)
			changed_max_z = maxi(changed_max_z, vz)

	var rect: Rect2i = Rect2i()
	if changed_max_x >= 0:
		var cell_min_x: int = clampi(changed_min_x - 1, 0, size - 1)
		var cell_min_z: int = clampi(changed_min_z - 1, 0, size - 1)
		var cell_max_x: int = clampi(changed_max_x, 0, size - 1)
		var cell_max_z: int = clampi(changed_max_z, 0, size - 1)
		rect = Rect2i(cell_min_x, cell_min_z,
			cell_max_x - cell_min_x + 1, cell_max_z - cell_min_z + 1)
	return {"indices": indices, "targets": targets, "rect": rect}


## Applies a corridor raise instantly (see line_raise_targets). Returns the
## affected cell rect (like raise_area).
func raise_line(from: Vector2, to: Vector2, half_width: float,
		height_from: float, height_to: float, edge: float = 1.5,
		forward_only: bool = false) -> Rect2i:
	var plan: Dictionary = line_raise_targets(from, to, half_width,
		height_from, height_to, edge, forward_only)
	var indices: PackedInt32Array = plan.indices
	var targets: PackedFloat32Array = plan.targets
	for i in range(indices.size()):
		heights[indices[i]] = targets[i]
	return plan.rect


# --- Walkability -------------------------------------------------------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < size and cell.y >= 0 and cell.y < size

## Average height of a cell's four corner vertices.
func cell_height(cell: Vector2i) -> float:
	var h00: float = heights[cell.y * verts + cell.x]
	var h10: float = heights[cell.y * verts + cell.x + 1]
	var h01: float = heights[(cell.y + 1) * verts + cell.x]
	var h11: float = heights[(cell.y + 1) * verts + cell.x + 1]
	return (h00 + h10 + h01 + h11) * 0.25

## True when the cell's (average) height lies in the grass band — the gameplay
## ground-type query used by the tree types (leaf/bamboo growth and sprouting).
func is_grass(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _disc_mask[cell.y * size + cell.x] == 0:
		return false
	var h: float = cell_height(cell)
	return h >= GRASS_MIN and h < GRASS_MAX

## A cell is walkable if it lies inside the disc, sits above the sea line and is
## not too steep. The disc test is what makes the void unreachable everywhere:
## `NavGrid.update_region()` is the only solidity writer and it asks exactly this
## question, so A*, the PathWorker clone, the vehicle grid, the island labels, the
## tree/unit spawns and `can_place_at` all inherit the mask. It also means a
## terrain-deforming spell can never ENLARGE the world: raising a void cell cannot
## make it walkable.
func is_walkable(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _disc_mask[cell.y * size + cell.x] == 0:
		return false
	var h00: float = heights[cell.y * verts + cell.x]
	var h10: float = heights[cell.y * verts + cell.x + 1]
	var h01: float = heights[(cell.y + 1) * verts + cell.x]
	var h11: float = heights[(cell.y + 1) * verts + cell.x + 1]
	var lo: float = minf(minf(h00, h10), minf(h01, h11))
	var hi: float = maxf(maxf(h00, h10), maxf(h01, h11))
	if (lo + hi) * 0.5 <= SEA_LEVEL:
		return false
	if hi - lo > MAX_SLOPE:
		return false
	return true


# --- Map generation -----------------------------------------------------------

## Deterministic procedural island: FastNoiseLite heights multiplied by a radial
## falloff so the border is guaranteed to sit below sea level (water all around).
func generate_island(p_seed: int) -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = p_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = NOISE_FREQ

	var half: float = float(size) * 0.5
	for vz in range(verts):
		for vx in range(verts):
			var n01: float = (noise.get_noise_2d(float(vx), float(vz)) + 1.0) * 0.5
			var d: float = Vector2(float(vx) - half, float(vz) - half).length() / half
			var mask: float = 1.0 - smoothstep(0.4, 1.0, d)
			var h: float = (BASE_LAND + n01 * NOISE_AMP) * mask
			heights[vz * verts + vx] = h
