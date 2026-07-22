extends SceneTree

## Minimal headless test runner.
##
## Run with:  godot --headless -s res://tests/run_tests.gd
##
## Loads every res://tests/test_*.gd (except test_base.gd), instantiates it and
## calls all methods whose name starts with "test_" via reflection. Prints a
## per-test summary and quits with exit code 0 (all passed) or 1 (any failure).

const TESTS_DIR: String = "res://tests"

## Fixed RNG seed. The global generator is reset to this value before EACH test
## file runs, so every run produces the identical randf()/randi()/randf_range()
## sequence. Without it, tests that let a simulation play out (RNG-driven combat,
## conversion, shove rolls) took a different path each run — the check count per
## file drifted and combat/conversion tests flaked (a unit that died in an
## unseeded brawl made a later line abort the method, dropping its checks).
## Per-file (not once globally) so each file is reproducible on its own,
## independent of what ran before it.
const TEST_SEED: int = 0x50D07  # arbitrary fixed value ("Godot"-ish)

func _initialize() -> void:
	var total_passed: int = 0
	var total_failed: int = 0
	var all_errors: Array[String] = []

	var files: PackedStringArray = _collect_test_files()
	print("== Running %d test file(s) ==" % files.size())

	for path in files:
		var script: GDScript = load(path)
		if script == null:
			push_error("Could not load %s" % path)
			total_failed += 1
			continue
		var instance: Object = script.new()
		var file_passed: int = 0
		var file_failed: int = 0
		seed(TEST_SEED)   # deterministic RNG per file (see TEST_SEED)
		for method in instance.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			instance.call(name)
		if instance is TestBase:
			file_passed = instance.passed
			file_failed = instance.failed
			for e in instance.errors:
				all_errors.append("%s: %s" % [path, e])
		total_passed += file_passed
		total_failed += file_failed
		var status: String = "OK" if file_failed == 0 else "FAIL"
		print("  [%s] %s  (%d passed, %d failed)" % [status, path, file_passed, file_failed])

	print("== Total: %d passed, %d failed ==" % [total_passed, total_failed])
	if total_failed > 0:
		print("-- Failures --")
		for e in all_errors:
			print("  * " + e)
		quit(1)
	else:
		quit(0)


func _collect_test_files() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	if dir == null:
		push_error("Cannot open %s" % TESTS_DIR)
		return result
	for file in dir.get_files():
		if not file.begins_with("test_"):
			continue
		if not file.ends_with(".gd"):
			continue
		if file == "test_base.gd":
			continue
		result.append(TESTS_DIR + "/" + file)
	result.sort()
	return result
