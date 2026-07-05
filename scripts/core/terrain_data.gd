class_name TerrainData extends RefCounted

## Single source of truth for terrain heights, walkability and runtime deformation.
##
## Heightmap grid: 128x128 cells, 129x129 vertices, 1.0 world metre per cell.
## Mesh, collision and navigation are all derived from this data. Pure data class
## (no Node dependency) so it is fully headless-testable.

const SIZE: int = 128          # cells per side
const VERTS: int = SIZE + 1    # vertices per side (129)
const CELL_SIZE: float = 1.0   # world metres per cell
const SEA_LEVEL: float = 2.0   # water line
const MAX_SLOPE: float = 1.5   # max corner height delta for a walkable cell (metres)

# Island generation tuning
const BASE_LAND: float = 6.0
const NOISE_AMP: float = 6.0
const NOISE_FREQ: float = 0.03

var heights: PackedFloat32Array = PackedFloat32Array()

func _init() -> void:
	heights.resize(VERTS * VERTS)


# --- Vertex access -----------------------------------------------------------

func vertex_height(x: int, z: int) -> float:
	x = clampi(x, 0, VERTS - 1)
	z = clampi(z, 0, VERTS - 1)
	return heights[z * VERTS + x]


func set_vertex_height(x: int, z: int, h: float) -> void:
	if x < 0 or x >= VERTS or z < 0 or z >= VERTS:
		return
	heights[z * VERTS + x] = h


## Bilinearly interpolated height at an arbitrary world position.
## Central for Y-snapping of units/buildings (no raycast needed).
func get_height(world_x: float, world_z: float) -> float:
	var fx: float = clampf(world_x / CELL_SIZE, 0.0, float(SIZE))
	var fz: float = clampf(world_z / CELL_SIZE, 0.0, float(SIZE))
	var x0: int = clampi(int(floor(fx)), 0, VERTS - 2)
	var z0: int = clampi(int(floor(fz)), 0, VERTS - 2)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heights[z0 * VERTS + x0]
	var h10: float = heights[z0 * VERTS + x0 + 1]
	var h01: float = heights[(z0 + 1) * VERTS + x0]
	var h11: float = heights[(z0 + 1) * VERTS + x0 + 1]
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
	var min_vx: int = clampi(int(floor((center.x - radius) / CELL_SIZE)), 0, VERTS - 1)
	var max_vx: int = clampi(int(ceil((center.x + radius) / CELL_SIZE)), 0, VERTS - 1)
	var min_vz: int = clampi(int(floor((center.y - radius) / CELL_SIZE)), 0, VERTS - 1)
	var max_vz: int = clampi(int(ceil((center.y + radius) / CELL_SIZE)), 0, VERTS - 1)

	var changed_min_x: int = VERTS
	var changed_min_z: int = VERTS
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
			heights[vz * VERTS + vx] += amount * falloff
			changed_min_x = mini(changed_min_x, vx)
			changed_min_z = mini(changed_min_z, vz)
			changed_max_x = maxi(changed_max_x, vx)
			changed_max_z = maxi(changed_max_z, vz)

	if changed_max_x < 0:
		return Rect2i()

	# A cell is affected if any of its 4 corner vertices moved. Vertex vx belongs
	# to cells (vx-1) and (vx); clamp the resulting cell range to the grid.
	var cell_min_x: int = clampi(changed_min_x - 1, 0, SIZE - 1)
	var cell_min_z: int = clampi(changed_min_z - 1, 0, SIZE - 1)
	var cell_max_x: int = clampi(changed_max_x, 0, SIZE - 1)
	var cell_max_z: int = clampi(changed_max_z, 0, SIZE - 1)
	return Rect2i(cell_min_x, cell_min_z,
		cell_max_x - cell_min_x + 1, cell_max_z - cell_min_z + 1)


# --- Walkability -------------------------------------------------------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < SIZE and cell.y >= 0 and cell.y < SIZE

## Average height of a cell's four corner vertices.
func cell_height(cell: Vector2i) -> float:
	var h00: float = heights[cell.y * VERTS + cell.x]
	var h10: float = heights[cell.y * VERTS + cell.x + 1]
	var h01: float = heights[(cell.y + 1) * VERTS + cell.x]
	var h11: float = heights[(cell.y + 1) * VERTS + cell.x + 1]
	return (h00 + h10 + h01 + h11) * 0.25

## A cell is walkable if it sits above the sea line and is not too steep.
func is_walkable(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var h00: float = heights[cell.y * VERTS + cell.x]
	var h10: float = heights[cell.y * VERTS + cell.x + 1]
	var h01: float = heights[(cell.y + 1) * VERTS + cell.x]
	var h11: float = heights[(cell.y + 1) * VERTS + cell.x + 1]
	var lo: float = minf(minf(h00, h10), minf(h01, h11))
	var hi: float = maxf(maxf(h00, h10), maxf(h01, h11))
	if (lo + hi) * 0.5 <= SEA_LEVEL:
		return false
	if hi - lo > MAX_SLOPE:
		return false
	return true


# --- Island generation -------------------------------------------------------

## Deterministic procedural island: FastNoiseLite heights multiplied by a radial
## falloff so the border is guaranteed to sit below sea level (water all around).
func generate_island(p_seed: int) -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = p_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = NOISE_FREQ

	var half: float = float(SIZE) * 0.5
	for vz in range(VERTS):
		for vx in range(VERTS):
			var n01: float = (noise.get_noise_2d(float(vx), float(vz)) + 1.0) * 0.5
			var d: float = Vector2(float(vx) - half, float(vz) - half).length() / half
			var mask: float = 1.0 - smoothstep(0.4, 1.0, d)
			var h: float = (BASE_LAND + n01 * NOISE_AMP) * mask
			heights[vz * VERTS + vx] = h
