class_name TestBase extends RefCounted

## Minimal assertion base class for the headless test runner.
## Uses check() (which collects failures) instead of assert(), because assert()
## is a no-op in release builds.

## Fixed RNG seed. Both runners reset the global generator to this value before
## a test FILE runs, so every run produces the identical randf()/randi()/
## randf_range() sequence. Without it, tests that let a simulation play out
## (RNG-driven combat, conversion, shove rolls) took a different path each run —
## the check count per file drifted and combat/conversion tests flaked.
## Per-file (not once globally) so each file is reproducible on its own,
## independent of what ran before it. It lives HERE, not in run_tests.gd, because
## run_one.gd used to skip the seeding entirely: the same file then behaved
## differently in the quick helper than in the suite, which is exactly how a
## seeded-and-green test looks flaky when you iterate on it.
const TEST_SEED: int = 0x50D07  # arbitrary fixed value ("Godot"-ish)

var passed: int = 0
var failed: int = 0
var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		errors.append(msg)

## Float comparison with tolerance.
func check_near(a: float, b: float, msg: String, eps: float = 0.0001) -> void:
	check(absf(a - b) <= eps, "%s (got %f, expected %f)" % [msg, a, b])
