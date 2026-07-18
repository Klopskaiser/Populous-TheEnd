extends SceneTree

## Runs a single test file (optionally a single test method) — quick iteration
## helper next to run_tests.gd:
##   godot --headless -s res://tests/run_one.gd -- res://tests/test_x.gd [test_method]

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: -s res://tests/run_one.gd -- res://tests/test_file.gd [test_method]")
		quit(1)
		return
	var script: GDScript = load(args[0])
	if script == null:
		push_error("Could not load %s" % args[0])
		quit(1)
		return
	var instance: Object = script.new()
	var only: String = args[1] if args.size() > 1 else ""
	for method in instance.get_method_list():
		var name: String = method.name
		if not name.begins_with("test_"):
			continue
		if only != "" and name != only:
			continue
		print("-- %s" % name)
		instance.call(name)
	if instance is TestBase:
		print("== %s: %d passed, %d failed ==" % [args[0], instance.passed, instance.failed])
		for e in instance.errors:
			print("  * " + e)
		quit(1 if instance.failed > 0 else 0)
		return
	quit(0)
