extends SceneTree

## Minimal headless test runner.
##
## Run with:  godot --headless -s res://tests/run_tests.gd
##
## Loads every res://tests/test_*.gd (except test_base.gd), instantiates it and
## calls all methods whose name starts with "test_" via reflection. Prints a
## per-test summary and quits with exit code 0 (all passed) or 1 (any failure).
##
## RUNTIME GUARDS: the suite drives thousands of simulated ticks, so a single
## careless loop can quietly add minutes. Every test method and every file is
## timed; slow ones are flagged inline (so a long run is visible WHILE it runs,
## not only at the end), and a method or the whole suite blowing through its
## hard cap FAILS the run instead of just being slow.

const TESTS_DIR: String = "res://tests"

## A single test method above this is printed as SLOW (still passes) …
const SLOW_TEST_MS: int = 3000
## … and above this it FAILS the suite: no test needs half a minute.
const MAX_TEST_MS: int = 30000
## Same pair for a whole file.
const SLOW_FILE_MS: int = 45000
## Hard cap for the entire suite (the wall the CI/agent timeout hits at 10 min).
const MAX_TOTAL_MS: int = 480000

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
	var suite_start: int = Time.get_ticks_msec()
	## (name, ms) of everything above SLOW_TEST_MS — repeated at the end so a
	## long run has a ranked culprit list instead of a shrug.
	var slow: Array[Array] = []

	for path in files:
		var script: GDScript = load(path)
		if script == null:
			push_error("Could not load %s" % path)
			all_errors.append("%s: Datei konnte nicht geladen werden (Parse-Fehler?)" % path)
			total_failed += 1
			continue
		# A script that FAILED to compile still loads as a GDScript object, but
		# new() returns null — and iterating a null instance used to send the
		# runner into a hang that looked like "the suite got slow" (it cost two
		# ten-minute timeouts before it was tracked down). Fail it loudly.
		var instance: Object = script.new()
		if instance == null:
			all_errors.append("%s: konnte nicht instanziiert werden (Parse-Fehler)" % path)
			total_failed += 1
			print("  [FAIL] %s  (Parse-Fehler — Datei uebersprungen)" % path)
			continue
		var file_passed: int = 0
		var file_failed: int = 0
		var file_start: int = Time.get_ticks_msec()
		seed(TEST_SEED)   # deterministic RNG per file (see TEST_SEED)
		for method in instance.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var t0: int = Time.get_ticks_msec()
			instance.call(name)
			var took: int = Time.get_ticks_msec() - t0
			if took >= SLOW_TEST_MS:
				slow.append([("%s::%s" % [path.get_file(), name]), took])
				print("  [SLOW] %s::%s  %.1f s" % [path.get_file(), name, took / 1000.0])
			if took >= MAX_TEST_MS:
				total_failed += 1
				all_errors.append("%s: %s brauchte %.1f s (Limit %.0f s) — Endlosschleife?"
					% [path, name, took / 1000.0, MAX_TEST_MS / 1000.0])
		var file_ms: int = Time.get_ticks_msec() - file_start
		if instance is TestBase:
			file_passed = instance.passed
			file_failed = instance.failed
			for e in instance.errors:
				all_errors.append("%s: %s" % [path, e])
		total_passed += file_passed
		total_failed += file_failed
		var status: String = "OK" if file_failed == 0 else "FAIL"
		var slow_mark: String = "  <-- LANGSAM" if file_ms >= SLOW_FILE_MS else ""
		print("  [%s] %s  (%d passed, %d failed, %.1f s)%s"
			% [status, path, file_passed, file_failed, file_ms / 1000.0, slow_mark])

	var total_ms: int = Time.get_ticks_msec() - suite_start
	if total_ms >= MAX_TOTAL_MS:
		total_failed += 1
		all_errors.append("Gesamtlaufzeit %.1f s über dem Limit von %.0f s"
			% [total_ms / 1000.0, MAX_TOTAL_MS / 1000.0])
	print("== Total: %d passed, %d failed, %.1f s ==" % [total_passed, total_failed,
		total_ms / 1000.0])
	if not slow.is_empty():
		slow.sort_custom(func(a, b): return a[1] > b[1])
		print("-- Langsamste Tests (>= %.0f s) --" % (SLOW_TEST_MS / 1000.0))
		for entry in slow:
			print("  %6.1f s  %s" % [entry[1] / 1000.0, entry[0]])
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
