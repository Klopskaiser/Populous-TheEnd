extends SceneTree

## Prints the content of a save game per tribe (units with their bindings, buildings)
## — to look into a reported state without loading it. KEIN test_-Praefix.
##   godot --headless -s res://tests/diag_inspect_save.gd -- [slot] [max_units_per_tribe]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var slot: String = args[0] if args.size() > 0 else SaveGame.QUICKSAVE_SLOT
	var limit: int = int(args[1]) if args.size() > 1 else 12
	var result: Dictionary = SaveGame.read(slot)
	if result.has("error"):
		print(result["error"])
		quit(1)
		return
	var header: Dictionary = result["header"]
	var body: Dictionary = result["body"]
	print(SaveGame.describe(header))
	var buildings: Array = body.get("buildings", [])
	var units: Array = body.get("units", [])
	for td in body.get("tribes", []):
		var id: int = int(td["id"])
		var own_units: Array = []
		for i in range(units.size()):
			if int(units[i]["tribe"]) == id:
				own_units.append(i)
		var own_buildings: Array = []
		for i in range(buildings.size()):
			if int(buildings[i]["tribe"]) == id:
				own_buildings.append(i)
		print("== Stamm %d %s: %d Einheiten, %d Gebaeude, aus=%s, Statistik %s" % [id,
			td.get("ai_personality_name", ""), own_units.size(), own_buildings.size(),
			td.get("eliminated", false), td.get("stats", {})])
		for i in own_buildings:
			var b: Dictionary = buildings[i]
			print("   G%d %s cell %s hp %d bau %s fortschritt %.2f holz %d crew %s training %s occ %s" % [i,
				String(b["scene"]).get_file(), b["cell"], int(b["health"]), b["under_construction"],
				float(b["build_progress"]), int(b["wood_delivered"]), b.get("crew", "-"),
				b.get("training", "-"), b.get("occupants", "-")])
		if own_units.size() <= limit:
			for i in own_units:
				var u: Dictionary = (units[i] as Dictionary).duplicate()
				u.erase("facing")
				print("   E%d %s" % [i, u])
	quit(0)
