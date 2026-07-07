class_name MapGenerator extends RefCounted

## Skirmish map registry (phase 7i). Each map knows its grid size, whether the
## minimap uses the round island mask, how many players it places bases for and
## how to fill its heightmap + base anchors. Generation is deterministic from
## the match seed, so player and AI get identical terrain.
##
## Base anchors and terrain generation share the same anchor cells (corners /
## halves), so bases always land on the raised / flat build spots.

const STANDARD_SIZE: int = TerrainData.SIZE   # 128
const LARGE_SIZE: int = 256                    # "twice the standard map"

const DEFAULT_MAP: String = "island"

# --- Generation tuning --------------------------------------------------------
const SEA: float = TerrainData.SEA_LEVEL       # 2.0
const LAND: float = 6.0                        # flat land base height

# Seenland
const LAKE_RADIUS_F: float = 0.22              # * size
const LAKE_DEPTH: float = 8.0                  # below LAND
const CORNER_RAISE: float = 10.0               # extra height at the corners
const CORNER_REACH_F: float = 0.30             # * size, corner bump reach

# Bergpass
const RIDGE_HALF_F: float = 0.10               # * size, half-width of the ridge band
const RIDGE_HEIGHT: float = 26.0               # above LAND
const PASS_HALF: int = 4                        # half-width of a walkable pass (cells)

# Plateau
const PLATEAU_HEIGHT: float = 12.0             # above LAND (hard-edged)
const PLATEAU_HALF: int = 16                    # half side of the flat top (cells)
const RAMP_HALF_WIDTH: float = 3.0             # walkable ramp toward map centre


# --- Registry -----------------------------------------------------------------

static func map_ids() -> PackedStringArray:
	return PackedStringArray(["island", "seenland", "bergpass", "plateau"])

static func display_name(map_id: String) -> String:
	match map_id:
		"island": return "Insel"
		"seenland": return "Seenland"
		"bergpass": return "Bergpass"
		"plateau": return "Plateau"
	return map_id

static func map_size(map_id: String) -> int:
	match map_id:
		"seenland", "bergpass": return LARGE_SIZE
	return STANDARD_SIZE

## The round island mask fits only the radial island; the others are square.
static func round_mask(map_id: String) -> bool:
	return map_id == "island"

## How many distinct player bases the map places (min 2).
static func max_players(map_id: String) -> int:
	return 4


# --- Terrain creation ---------------------------------------------------------

static func create_terrain(map_id: String, p_seed: int) -> TerrainData:
	var td: TerrainData = TerrainData.new(map_size(map_id))
	generate(td, map_id, p_seed)
	return td

static func generate(td: TerrainData, map_id: String, p_seed: int) -> void:
	match map_id:
		"seenland": _gen_seenland(td, p_seed)
		"bergpass": _gen_bergpass(td, p_seed)
		"plateau": _gen_plateau(td, p_seed)
		_: td.generate_island(p_seed)


# --- Base anchors -------------------------------------------------------------

## Base anchor cells for `count` tribes (index 0 = player). Clamped to what the
## map supports; always at least the requested count on the supported maps.
static func spawn_anchors(td: TerrainData, map_id: String, count: int) -> Array[Vector2i]:
	match map_id:
		"seenland", "plateau": return _corner_anchors(td, count)
		"bergpass": return _half_anchors(td, count)
		_: return _circle_anchors(td, count)


## Evenly spaced on a circle around the centre; the player starts in the south
## (matches the previous island behaviour).
static func _circle_anchors(td: TerrainData, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var center: float = float(td.size) * 0.5
	var radius: float = float(td.size) * 0.2
	var n: int = maxi(count, 1)
	for i in range(count):
		var angle: float = TAU * float(i) / float(n) + PI * 0.5
		result.append(Vector2i(
			int(round(center + cos(angle) * radius)),
			int(round(center + sin(angle) * radius))))
	return result


## The four corners, ordered so 2 players start diagonally opposite.
static func _corner_cells(td: TerrainData) -> Array[Vector2i]:
	var m: int = int(round(float(td.size) * 0.18))
	var lo: int = m
	var hi: int = td.size - m
	# order: top-left, bottom-right, top-right, bottom-left
	return [Vector2i(lo, lo), Vector2i(hi, hi), Vector2i(hi, lo), Vector2i(lo, hi)]


static func _corner_anchors(td: TerrainData, count: int) -> Array[Vector2i]:
	var corners: Array[Vector2i] = _corner_cells(td)
	var result: Array[Vector2i] = []
	for i in range(count):
		result.append(corners[i % corners.size()])
	return result


## Two players per half (split by the ridge at z = centre); bases sit a moderate
## distance from the ridge so they are relatively close across the passes.
static func _half_anchors(td: TerrainData, count: int) -> Array[Vector2i]:
	var s: int = td.size
	var off: int = int(round(float(s) * 0.18))
	var top_z: int = s / 2 - off
	var bot_z: int = s / 2 + off
	var xl: int = int(round(float(s) * 0.3))
	var xr: int = int(round(float(s) * 0.7))
	# order alternates halves so 2 players face off across the ridge
	var slots: Array[Vector2i] = [
		Vector2i(xl, top_z), Vector2i(xr, bot_z),
		Vector2i(xr, top_z), Vector2i(xl, bot_z)]
	var result: Array[Vector2i] = []
	for i in range(count):
		result.append(slots[i % slots.size()])
	return result


# --- Generators ---------------------------------------------------------------

static func _noise(p_seed: int, freq: float) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	return n


## Seenland: mostly land, a round lake in the middle, raised corners; players
## start in the (flat, elevated) corners. Twice the standard size.
static func _gen_seenland(td: TerrainData, p_seed: int) -> void:
	var noise: FastNoiseLite = _noise(p_seed, 0.035)
	var center: Vector2 = Vector2(float(td.size), float(td.size)) * 0.5
	var lake_r: float = float(td.size) * LAKE_RADIUS_F
	var reach: float = float(td.size) * CORNER_REACH_F
	var corners: Array[Vector2i] = _corner_cells(td)
	for vz in range(td.verts):
		for vx in range(td.verts):
			var p: Vector2 = Vector2(float(vx), float(vz))
			var h: float = LAND + noise.get_noise_2d(float(vx), float(vz)) * 2.0
			# Central lake: smoothstep dip below the sea line.
			var ld: float = p.distance_to(center)
			if ld < lake_r:
				var t: float = 1.0 - smoothstep(0.0, lake_r, ld)   # 1 at centre
				h = lerpf(h, SEA - LAKE_DEPTH, t)
			# Raised corners (nearest corner bump).
			var best: float = INF
			for c in corners:
				best = minf(best, p.distance_to(Vector2(c)))
			if best < reach:
				var ct: float = 1.0 - smoothstep(0.0, reach, best)
				h += CORNER_RAISE * ct * ct
			td.heights[vz * td.verts + vx] = h


## Bergpass: flat, no water, a high ridge across the middle with 3 narrow passes
## and steep foothills; two players per half. Twice the standard size.
static func _gen_bergpass(td: TerrainData, p_seed: int) -> void:
	var noise: FastNoiseLite = _noise(p_seed, 0.05)
	var s: int = td.size
	var mid: float = float(s) * 0.5
	var half: float = float(s) * RIDGE_HALF_F
	# Three passes at 1/4, 1/2, 3/4 across x.
	var passes: Array[int] = [s / 4, s / 2, s * 3 / 4]
	for vz in range(td.verts):
		for vx in range(td.verts):
			var h: float = LAND + noise.get_noise_2d(float(vx), float(vz)) * 1.5
			var dz: float = absf(float(vz) - mid)
			if dz < half:
				# On the ridge band — high, unless inside a pass corridor.
				var in_pass: bool = false
				for px in passes:
					if absi(vx - px) <= PASS_HALF:
						in_pass = true
						break
				if not in_pass:
					# Steep foothills: near-vertical rise over a couple of cells.
					var rise: float = smoothstep(half, half - 3.0, dz)  # 0 at edge -> 1 inside
					h += RIDGE_HEIGHT * rise
			td.heights[vz * td.verts + vx] = h


## Plateau: each player on a smooth, strongly raised flat plateau with hard
## cliff edges; the rest is flat, no water. One walkable ramp per plateau leads
## down toward the map centre (so a hard-edged start is still playable).
## Standard size.
static func _gen_plateau(td: TerrainData, p_seed: int) -> void:
	var noise: FastNoiseLite = _noise(p_seed, 0.05)
	# Flat base everywhere.
	for vz in range(td.verts):
		for vx in range(td.verts):
			td.heights[vz * td.verts + vx] = LAND + noise.get_noise_2d(float(vx), float(vz)) * 1.0
	# Hard-edged raised plateaus at each corner anchor.
	var center: Vector2 = Vector2(float(td.size), float(td.size)) * 0.5
	var top: float = LAND + PLATEAU_HEIGHT
	for c in _corner_cells(td):
		for dz in range(-PLATEAU_HALF, PLATEAU_HALF + 1):
			for dx in range(-PLATEAU_HALF, PLATEAU_HALF + 1):
				var vx: int = c.x + dx
				var vz: int = c.y + dz
				if vx < 0 or vx >= td.verts or vz < 0 or vz >= td.verts:
					continue
				td.heights[vz * td.verts + vx] = top
		# One ramp from the plateau edge toward the map centre.
		var dir: Vector2 = (center - Vector2(c)).normalized()
		var edge: Vector2 = Vector2(c) + dir * float(PLATEAU_HALF)
		var foot: Vector2 = Vector2(c) + dir * float(PLATEAU_HALF + 12)
		td.raise_line(edge, foot, RAMP_HALF_WIDTH, top, LAND, 1.0)
