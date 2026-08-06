extends TestBase

## Phase 10k, Teil 1+2: die gedämpfte Manakurve und wer Mana kostet.
##
## Die Manaerzeugung war linear und unbegrenzt (1000 Anhänger = 10x die Rate von
## 100). Ab Balance.MANA_SOFT_CAP dämpft eine logarithmische Kurve auf etwa ein
## Viertel je weiterem Kopf. Die Zielwerte sind EXAKT, nicht gefittet: 500
## Anhänger liefern genau das Doppelte von 100 (weil 400/10000 = 0,04 und der
## Logarithmus damit genau ln(1,04) ist), 1000 das 3,197-Fache.
##
## Zweiter Teil: nur die AUSBILDUNG kostet Mana. Fahrzeugbau und die
## Brave-Produktion der Hütte sind ausdrücklich kostenlos (Nutzervorgabe) — die
## beiden Wächter dafür fallen um, sobald jemand die Buchung von
## TrainingBuilding nach Building hochzieht.

const TICK: float = 0.5

const HUT_SCENE: PackedScene = preload("res://scenes/buildings/hut.tscn")
const WARRIOR_CAMP_SCENE: PackedScene = preload("res://scenes/buildings/warrior_camp.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/buildings/workshop.tscn")
const BRAVE_SCENE: PackedScene = preload("res://scenes/units/brave.tscn")


func _flat_terrain(h: float = 5.0) -> TerrainData:
	var td: TerrainData = TerrainData.new()
	for i in range(td.heights.size()):
		td.heights[i] = h
	return td


func _make_world() -> Dictionary:
	var td: TerrainData = _flat_terrain()
	var nav: NavGrid = NavGrid.new(td)
	var tribe: Tribe = Tribe.new(0)
	var tm: TreeManager = TreeManager.new()
	tm.setup(td, nav)
	var wpm: WoodPileManager = WoodPileManager.new()
	wpm.setup(td)
	var um: UnitManager = UnitManager.new()
	um.setup(td, nav, [tribe] as Array[Tribe], tm, wpm)
	var bm: BuildingManager = BuildingManager.new()
	bm.setup(td, nav, um, wpm)
	var tc: TribeCommands = TribeCommands.new()
	tc.setup(nav, bm, um, tm)
	return {"td": td, "nav": nav, "tribe": tribe, "um": um, "bm": bm,
		"tm": tm, "wpm": wpm, "commands": tc}


func _free_world(w: Dictionary) -> void:
	w.commands.free()
	w.tm.free()
	w.wpm.free()
	w.bm.free()
	w.um.free()


## Rate a tribe of `n` followers would earn, without spawning n units.
func _rate_for(n: int) -> float:
	return Tribe.mana_population_for(n) * Balance.MANA_BASE_RATE


# --- Die Kurve ----------------------------------------------------------------

func test_below_the_soft_cap_stays_linear() -> void:
	var cap: int = Balance.MANA_SOFT_CAP
	check_near(Tribe.mana_population_for(0), 0.0, "no followers, no production")
	check_near(Tribe.mana_population_for(1), 1.0, "one follower counts as one")
	check_near(Tribe.mana_population_for(cap / 2), float(cap / 2),
		"half the cap is still linear")
	check_near(Tribe.mana_population_for(cap), float(cap), "at the cap: unchanged")
	# Negative / nonsense input must not produce negative income.
	check(Tribe.mana_population_for(-5) >= 0.0, "a negative count clamps to zero")


func test_500_is_exactly_double_100() -> void:
	var p100: float = Tribe.mana_population_for(100)
	var p500: float = Tribe.mana_population_for(500)
	check_near(p500 / p100, 2.0, "500 followers produce exactly twice as much as 100")
	# Exact, not approximate: 400/10000 = 0,04, so the log is exactly ln(1,04).
	check(absf(p500 - 200.0) < 0.001, "the value is exact (%.6f)" % p500)


func test_1000_is_about_triple_100() -> void:
	var ratio: float = Tribe.mana_population_for(1000) / Tribe.mana_population_for(100)
	check(ratio > 3.0 and ratio < 3.5,
		"1000 followers land above 3x and below 3,5x (%.3f)" % ratio)
	check_near(ratio, 3.197, "and specifically on 3,197x", 0.01)


func test_marginal_contribution_drops_to_about_a_quarter() -> void:
	var cap: int = Balance.MANA_SOFT_CAP
	# One more follower below the cap is worth a full head.
	var below: float = Tribe.mana_population_for(cap) - Tribe.mana_population_for(cap - 1)
	check_near(below, 1.0, "below the cap a follower is worth a full head")
	# Just above the cap it is about a quarter of that ...
	var at_cap: float = Tribe.mana_population_for(cap + 1) - Tribe.mana_population_for(cap)
	check(at_cap > 0.20 and at_cap < 0.30,
		"the first follower past the cap contributes ~1/4 (%.3f)" % at_cap)
	# ... and it keeps sinking, but stays positive (more people are never bad).
	var at_1000: float = Tribe.mana_population_for(1001) - Tribe.mana_population_for(1000)
	check(at_1000 > 0.0, "even at 1000 another follower still helps")
	check(at_1000 < at_cap, "but less than right past the cap")


func test_curve_is_monotonic_and_continuous_at_the_cap() -> void:
	var prev: float = -1.0
	var monotone: bool = true
	for n in range(0, 1200, 7):
		var v: float = Tribe.mana_population_for(n)
		if v < prev - 0.000001:
			monotone = false
		prev = v
	check(monotone, "the curve never falls")
	# No step at the boundary: the log term is 0 exactly at the cap.
	var cap: int = Balance.MANA_SOFT_CAP
	var jump: float = absf(Tribe.mana_population_for(cap + 1)
		- Tribe.mana_population_for(cap))
	check(jump < 1.0, "no jump at the soft cap (delta %.4f)" % jump)


## The rate a real tribe reports must use the curve, not the raw head count.
func test_tribe_rate_uses_the_curve() -> void:
	var w: Dictionary = _make_world()
	var tribe: Tribe = w.tribe
	for i in range(120):
		var b: Unit = w.um.spawn_unit(BRAVE_SCENE, 0,
			w.nav.cell_to_world(Vector2i(20 + i % 40, 20 + i / 40)))
		check(b != null or true, "")   # spawn may clamp; the count below is what matters
	var n: int = tribe.population()
	check(n > Balance.MANA_SOFT_CAP, "the tribe is past the soft cap (%d)" % n)
	check_near(tribe.mana_rate(), _rate_for(n),
		"mana_rate() follows mana_population_for()")
	check(tribe.mana_rate() < float(n) * Balance.MANA_BASE_RATE,
		"and is BELOW the old linear rate")
	_free_world(w)


# --- Wer kostet Mana ----------------------------------------------------------

## Active training costs as much as one forester worker — but only while a
## trainee is really inside.
func test_training_costs_mana_only_while_a_trainee_is_inside() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.bm.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	# Nobody inside: no cost.
	var before: float = w.tribe.upkeep_debt()
	for i in range(10):
		camp.tick(TICK)
	check_near(w.tribe.upkeep_debt(), before, "an idle camp costs nothing")

	# A brave walks in and training starts.
	var brave: Brave = w.um.spawn_unit(BRAVE_SCENE, 0,
		w.nav.cell_to_world(Vector2i(30, 36))) as Brave
	w.commands.order_train(camp, [brave] as Array[Unit])
	var used: int = 0
	for i in range(2000):
		brave.tick(0.05)
		camp.tick(0.05)
		used += 1
		if camp.trainee != null:
			break
	check(camp.trainee != null, "the brave is inside training")
	# Measure INSIDE the training time (warrior camp: 3 s) — ticking past the end
	# would charge fewer ticks than expected and read as a code error.
	var window: float = 1.0
	var steps: int = 20
	var mid: float = w.tribe.upkeep_debt()
	for i in range(steps):
		camp.tick(window / float(steps))
	check(camp.trainee != null, "still training after the measured window")
	var charged: float = w.tribe.upkeep_debt() - mid
	check(charged > 0.0, "active training books mana (%.3f)" % charged)
	check_near(charged, Balance.TRAINING_MANA_PER_BUILDING * window,
		"and it is exactly TRAINING_MANA_PER_BUILDING per second")
	check_near(Balance.TRAINING_MANA_PER_BUILDING, Balance.FORESTER_MANA_PER_WORKER,
		"as much as one forester worker (user requirement)")
	_free_world(w)


func test_queued_braves_cost_nothing() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.bm.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	# Paused: the queue forms but nobody is admitted, so nothing may be charged.
	camp.paused = true
	var braves: Array[Unit] = []
	for i in range(3):
		braves.append(w.um.spawn_unit(BRAVE_SCENE, 0,
			w.nav.cell_to_world(Vector2i(28 + i, 36))))
	w.commands.order_train(camp, braves)
	var before: float = w.tribe.upkeep_debt()
	for i in range(40):
		for u in braves:
			u.tick(0.05)
		camp.tick(0.05)
	check(camp.trainee == null, "nobody was admitted (paused)")
	check_near(w.tribe.upkeep_debt(), before, "a queue alone costs nothing")
	_free_world(w)


## WÄCHTER: vehicle construction must stay free. Falls over the moment somebody
## moves the training booking up into Building.
func test_vehicle_construction_costs_no_mana() -> void:
	var w: Dictionary = _make_world()
	var shop: Workshop = w.bm.place(
		WORKSHOP_SCENE, w.tribe, Vector2i(40, 40), 0, true) as Workshop
	check(shop != null, "the workshop stands")
	# Feed it wood so it really produces, then let it run.
	w.wpm.deposit(shop.delivery_point(), 20)
	var before: float = w.tribe.upkeep_debt()
	for i in range(200):
		shop.tick(TICK)
	check_near(w.tribe.upkeep_debt(), before,
		"building vehicles costs NO mana (user requirement)")
	_free_world(w)


## WÄCHTER: the hut's brave production must stay free.
func test_hut_brave_production_costs_no_mana() -> void:
	var w: Dictionary = _make_world()
	var hut: Hut = w.bm.place(HUT_SCENE, w.tribe, Vector2i(50, 50), 0, true) as Hut
	# Crew it so it actually spawns braves (a hut without crew produces nothing).
	for i in range(2):
		var b: Brave = w.um.spawn_unit(BRAVE_SCENE, 0,
			w.nav.cell_to_world(Vector2i(50 + i, 56))) as Brave
		check(hut.admit_crew(b), "crew member %d admitted" % i)
	var before: float = w.tribe.upkeep_debt()
	var pop_before: int = w.tribe.population()
	for i in range(400):
		hut.tick(TICK)
	check(w.tribe.population() >= pop_before, "the hut produced (or at least tried)")
	check_near(w.tribe.upkeep_debt(), before,
		"hut population costs NO mana (user requirement)")
	_free_world(w)


# --- Bugfix: die Manaanzeige muss den Unterhalt zeigen ------------------------

## Nutzerreport: "Manaanzeige ist falsch — schickt man Leute in Holzfäller oder
## Training, wird die gleiche Manazahl angezeigt." Die Sidebar zeigte
## mana_rate(), also das BRUTTO-Einkommen; der Unterhalt wird erst in
## Tribe.tick() abgezogen und war damit unsichtbar. Die Anzeige liest jetzt
## charging_income() und nennt upkeep_rate() daneben.
func test_active_training_lowers_the_displayed_income() -> void:
	var w: Dictionary = _make_world()
	var camp: WarriorCamp = w.bm.place(
		WARRIOR_CAMP_SCENE, w.tribe, Vector2i(30, 30), 0, true) as WarriorCamp
	for i in range(40):
		w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(10 + i % 20, 10 + i / 20)))
	var gross: float = w.tribe.mana_rate()
	check(gross > 0.0, "the tribe earns something")
	check_near(w.tribe.charging_income(), gross,
		"with nothing running, net equals gross")
	check_near(w.tribe.upkeep_rate(), 0.0, "and there is no upkeep")

	# Get a brave into the camp so training really runs.
	var brave: Brave = w.um.spawn_unit(BRAVE_SCENE, 0,
		w.nav.cell_to_world(Vector2i(30, 36))) as Brave
	w.commands.order_train(camp, [brave] as Array[Unit])
	for i in range(2000):
		brave.tick(0.05)
		camp.tick(0.05)
		if camp.trainee != null:
			break
	check(camp.trainee != null, "the brave is training")
	# The rate is a PER-TICK value that Tribe.tick() clears, so measure exactly one
	# building tick after a tribe tick — otherwise the bookings of the loop above
	# pile up and read like a double charge.
	w.tribe.tick(0.01)
	camp.tick(0.1)
	# Gross has to be re-read: spawning the training brave raised the population.
	var gross_now: float = w.tribe.mana_rate()
	check_near(w.tribe.upkeep_rate(), Balance.TRAINING_MANA_PER_BUILDING,
		"the training shows up as upkeep")
	check(w.tribe.charging_income() < gross_now,
		"and the DISPLAYED income drops (%.2f < %.2f)"
			% [w.tribe.charging_income(), gross_now])
	check_near(w.tribe.charging_income(),
		gross_now - Balance.TRAINING_MANA_PER_BUILDING,
		"by exactly the training cost")
	_free_world(w)


## Derselbe Fehler betraf die Försterei — dort war die Rate schon erfasst
## (claim_upkeep_rate), aber die Anzeige las sie nicht.
func test_forester_upkeep_is_visible_in_the_income() -> void:
	var w: Dictionary = _make_world()
	# The claim is capped by the income, so the tribe needs people first.
	for i in range(30):
		w.um.spawn_unit(BRAVE_SCENE, 0, w.nav.cell_to_world(Vector2i(10 + i, 10)))
	var gross: float = w.tribe.mana_rate()
	# The forester claims its rate against the income; simulate one claim.
	var granted: float = w.tribe.claim_upkeep_rate(Balance.FORESTER_MANA_PER_WORKER * 2.0)
	check(granted > 0.0, "the claim was granted (%.2f)" % granted)
	check_near(w.tribe.upkeep_rate(), granted, "it counts as upkeep")
	check_near(w.tribe.charging_income(), gross - granted,
		"and the displayed income is the NET one")
	_free_world(w)


func test_upkeep_resets_every_tick() -> void:
	var w: Dictionary = _make_world()
	w.tribe.book_upkeep_rate(2.0, 0.1)
	check(w.tribe.upkeep_rate() > 0.0, "booked")
	w.tribe.tick(0.1)
	check_near(w.tribe.upkeep_rate(), 0.0,
		"the per-tick rate is cleared again (it is a rate, not a stock)")
	_free_world(w)
