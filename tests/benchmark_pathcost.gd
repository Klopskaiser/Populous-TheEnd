extends SceneTree

## Micro-benchmark: cost of NavGrid.find_path calls for the tree search
## (bug backlog #4 follow-up). Measures short/medium/long paths, detour paths
## around a cliff and failing lookups on a 128 map with a plateau+ramp.
##   godot --headless -s res://tests/benchmark_pathcost.gd

const RUNS: int = 200


func _initialize() -> void:
	# Plateau world like the real repro: high west, low east, one ramp strip.
	var td: TerrainData = TerrainData.new()
	for vz in range(td.size + 1):
		for vx in range(td.size + 1):
			var h: float = 9.0
			if vx >= 46:
				h = 3.0
			elif vx >= 41:
				h = (9.0 - float(vx - 40)) if (vz >= 100 and vz <= 110) else 9.0 \
					if vx <= 42 else 3.0
			td.set_vertex_height(vx, vz, h)
	var nav: NavGrid = NavGrid.new(td)

	var cases: Dictionary = {
		"kurz (8 m, gleiche Ebene)":
			[Vector3(30.5, 0, 20.5), Vector3(38.5, 0, 20.5)],
		"mittel (30 m, gleiche Ebene)":
			[Vector3(10.5, 0, 20.5), Vector3(39.5, 0, 25.5)],
		"Umweg (10 m Luftlinie, ~170 m Pfad ueber Rampe)":
			[Vector3(39.5, 0, 20.5), Vector3(48.5, 0, 20.5)],
		"lang (120 m quer)":
			[Vector3(50.5, 0, 5.5), Vector3(120.5, 0, 120.5)],
		"unerreichbar (Insel-Check greift vorher)":
			[Vector3(39.5, 0, 20.5), Vector3(48.5, 0, 20.5)],
	}
	print("find_path-Kosten (%d Laeufe je Fall, 128er-Karte):" % RUNS)
	for label: String in cases.keys():
		var from: Vector3 = cases[label][0]
		var to: Vector3 = cases[label][1]
		var t0: int = Time.get_ticks_usec()
		var pts: int = 0
		for i in range(RUNS):
			pts = nav.find_path(from, to).size()
		var us: float = float(Time.get_ticks_usec() - t0) / float(RUNS)
		print("  %-50s %7.1f us/Aufruf (%d Punkte)" % [label, us, pts])

	# same_island as the cheap prefilter, for comparison.
	var t0: int = Time.get_ticks_usec()
	var hits: int = 0
	for i in range(RUNS * 10):
		if nav.same_island(Vector3(39.5, 0, 20.5), Vector3(48.5, 0, 20.5)):
			hits += 1
	var us: float = float(Time.get_ticks_usec() - t0) / float(RUNS * 10)
	print("  %-50s %7.1f us/Aufruf" % ["same_island (Vorfilter)", us])
	quit(0)
