extends SceneTree

## Micro-benchmark for the TreeManager tick with a full growing forest:
## 1000 trees (mixed types, low stages, all actively growing) on a flat grass
## map, ticked for 100 simulated seconds at 30 Hz. Prints the average tick
## cost in microseconds. Run headless:
##   $GODOT --path . --headless -s res://tests/benchmark_tree_growth.gd
## Note: headless rendering is a dummy server, so GPU-side costs of transform
## updates are not captured — this measures the script/scene-side tick cost.

const TREES: int = 1000
const TICKS: int = 3000          # 100 s at 30 Hz
const DELTA: float = 1.0 / 30.0


func _init() -> void:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = 5.0   # grass everywhere -> every type grows
	var nav: NavGrid = NavGrid.new(td)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	root.add_child(tm)

	var placed: int = 0
	for z in range(2, 126, 2):
		for x in range(2, 126, 2):
			if placed >= TREES:
				break
			var type: TreeResource.TreeType = (placed % 3) as TreeResource.TreeType
			tm.spawn_tree(Vector2i(x, z), placed % 2, type)
			placed += 1
		if placed >= TREES:
			break

	var t0: int = Time.get_ticks_usec()
	for i in range(TICKS):
		tm.tick(DELTA)
	var total: int = Time.get_ticks_usec() - t0
	print("growing: trees=%d ticks=%d  total=%.1f ms  avg per tick=%.1f us"
		% [placed, TICKS, total / 1000.0, float(total) / float(TICKS)])

	# Steady state: a mature forest (every tree at max stage) must be near-free.
	for tree in tm.trees:
		tree.set_stage(tree.max_stage())
	t0 = Time.get_ticks_usec()
	for i in range(TICKS):
		tm.tick(DELTA)
	total = Time.get_ticks_usec() - t0
	print("mature:  trees=%d ticks=%d  total=%.1f ms  avg per tick=%.1f us"
		% [placed, TICKS, total / 1000.0, float(total) / float(TICKS)])
	quit()
