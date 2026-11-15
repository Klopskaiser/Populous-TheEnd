class_name Golem extends Unit

## Golem (Zauber 13, 2026-09-06): eine beschworene Riesin — so hoch wie der
## Wachturm (GOLEM_HEIGHT), schlank (Koerperbox 1,55 m breit x 1,22 m tief, eigenes 3D-Modell
## statt Sprite), stark (GOLEM_HP), langsam im Angriff und zeitlich begrenzt.
##
## Kampf: ZWEI Flaechenangriffe im Takt GOLEM_STRIKE_COOLDOWN (Nutzervorgabe
## 2026-11-15), sobald das Ziel innerhalb GOLEM_REACH steht:
##   HANDSCHLAG (slam) — sie bueckt sich und schlaegt beide Haende auf den Boden:
##     Schaden RUNDHERUM, ein Kreis (GOLEM_SLAM_RADIUS) um den Aufschlagpunkt
##     GOLEM_SLAM_FORWARD vor ihr. GOLEM_SLAM_DAMAGE; Ueberlebende werden mit je
##     30 % hochgewirbelt oder ins Rollen gebracht, vom Golem weg.
##   TRITT (kick) — ein Fussballtritt: Schaden in einer SCHNEISE nach vorn
##     (GOLEM_KICK_WIDTH x GOLEM_KICK_LENGTH, weniger als die halbe Flaeche).
##     Mehr Schaden (GOLEM_KICK_DAMAGE) und viel Rueckstoss: JEDER Ueberlebende
##     fliegt in Trittrichtung davon.
## Wahl (_choose_attack): stehen mindestens GOLEM_SLAM_MIN_TARGETS Feinde in der
## Flaeche des Handschlags, schlaegt sie, sonst tritt sie. Beide Angriffe haben
## eine AUSHOLZEIT (GOLEM_*_WINDUP): der Angriff wird angesetzt, der Schaden
## faellt erst beim Aufschlag der Animation — in der dann aktuellen Blickrichtung.
## Jedes feindliche Gebaeude in der Wirkflaeche verliert eine Zerstoerungsstufe.
## Sitzende (Bekehrung) werden wie beim Katapult mitgetroffen; eigene Einheiten
## nie. Ziele in Reichweite gehen immer vor dem Verfolgen weggeschleuderter
## (_tick_attack).
##
## Der Golem haelt sich NICHT an die Kampfgruppenregeln (3er-Ringe, Warteringe):
## `_is_ranged()` ist der vorhandene Schalter dafuer — kein _bind_to_fight, der
## Naechster-nach-Distanz-Scan, und der Gebaeudeangriff laeuft ueber
## _bombard_building (von aussen, ohne Raider-Platz). Luftziele lehnt er ab
## (Nahkampf).
##
## Lebenszeit GOLEM_LIFETIME, +GOLEM_LIFE_PER_KILL je Kill. Ein Kill hebt ausserdem
## seine Lebensobergrenze um GOLEM_MAX_HP_PER_KILL und heilt ihn um
## GOLEM_HP_PER_KILL (bis zur Obergrenze); danach zerfaellt er (golem_death) und
## versinkt.
##
## STUFEN (Nutzervorgabe 2026-11-15): alle GOLEM_KILLS_PER_LEVEL Kills steigt er
## eine Stufe auf (0 .. GOLEM_MAX_LEVEL). Je Stufe +20 s Lebenszeit, +3 Leben/s
## Dauerheilung (bis zur Lebensobergrenze), +5 Schaden und 20 % groesser als davor
## (aufgezinst, size_factor()). Reichweite und Wirkflaechen wachsen langsamer —
## 10 % je Stufe (reach_factor()) —, das Tempo mit der Wurzel der Groesse. Ab
## Stufe 1 laeuft er durch Einheiten hindurch (ignores_unit_collision) und
## TRAMPELT Feinde unter seinem Koerper, solange er sich bewegt (_tick_trample).
## Auf der hoechsten Stufe laeuft die Lebenszeit nicht mehr ab, und er schlaegt
## auch nach Luftschiffen in Reichweite (ATTACK_SWAT, ein Huellentreffer je
## Schlag) und laeuft ihnen nach, wenn er sie zu Fuss erreichen kann. Kein Anhaenger: zaehlt nicht als Bevoelkerung
## (kein Mana, kein Wohnraum, haelt keinen Stamm am Leben), aber gegen den
## Einheiten-Hardcap. Immun gegen Bekehrung, Hypnose, Panik, Wurf und Rollen;
## brennt nur mit GOLEM_BURN_DPS und ohne Panik. Nimmt sonst normalen Schaden.

const REACH: float = Balance.GOLEM_REACH
## The model (golem.glb and the placeholder alike) is BUILT 4 m tall. The game
## scales its WIDTH AND DEPTH with MODEL_SCALE (the build of a 5,25-m figure) and
## its HEIGHT with MODEL_SCALE_Y (10 percent less — she looked too slender, user
## 2026-11-15). The squash is applied at the model root, above the skeleton, so
## it is a plain vertical scale in every pose. The walk stride is horizontal and
## follows MODEL_SCALE.
const MODEL_HEIGHT: float = 4.0
const MODEL_SCALE: float = Balance.GOLEM_BUILD_HEIGHT / MODEL_HEIGHT
const MODEL_SCALE_Y: float = Balance.GOLEM_HEIGHT / MODEL_HEIGHT
const BODY_HALF_WIDTH: float = Balance.GOLEM_BODY_HALF_WIDTH
const BODY_HALF_DEPTH: float = Balance.GOLEM_BODY_HALF_DEPTH
## The two attacks. The names double as animation clip names of the model.
const ATTACK_SLAM: StringName = &"slam"
const ATTACK_KICK: StringName = &"kick"
## The upward strike at an airship (maximum level only).
const ATTACK_SWAT: StringName = &"swat"
## Strike areas in the heading frame (along = forward, side = right), flat in XZ:
## slam = circle of SLAM_RADIUS around the point SLAM_FORWARD ahead,
## kick = lane -KICK_BACK <= along <= KICK_LENGTH, |side| <= KICK_HALF_WIDTH (the
## leg swings back first, so the lane reaches behind her too).
const SLAM_RADIUS: float = Balance.GOLEM_SLAM_RADIUS
const SLAM_FORWARD: float = Balance.GOLEM_SLAM_FORWARD
const KICK_HALF_WIDTH: float = Balance.GOLEM_KICK_WIDTH * 0.5
const KICK_LENGTH: float = Balance.GOLEM_KICK_LENGTH
const KICK_BACK: float = Balance.GOLEM_KICK_LENGTH * Balance.GOLEM_KICK_BACK_SHARE
## Length of the model's attack clips (seconds, golem_export.mjs) — an attack
## animation may be slowed down until it fills the attack cooldown, no further.
const CLIP_LENGTH: Dictionary = {&"slam": 1.5, &"kick": 1.2, &"swat": 1.2}
const STRIKE_COOLDOWN: float = Balance.GOLEM_STRIKE_COOLDOWN
## A swat still hits an airship that drifted this far beyond reach() during the
## wind-up (factor on the reach).
const SWAT_SLACK: float = 1.15
## Above this many remembered vertices the flatten memory drops what lies far
## behind the golem (see _prune_flatten_memory).
const FLATTEN_MEMORY_MAX: int = 6000
## How often the airship chase re-aims (s), and how close to the ship (share of
## reach()) the golem stops walking and just swats.
const AIR_CHASE_INTERVAL: float = 0.7
const AIR_CHASE_STAND: float = 0.8
## Fraction of REACH the golem walks in to when closing on a building (see
## Unit.stand_off_point / SiegeEngine.APPROACH_RANGE_FRACTION).
const APPROACH_RANGE_FRACTION: float = 0.85
## Wreck sink speed after the crumble (m/s), like the vehicle wrecks, and how
## long the collapse may play before the sinking starts.
const SINK_SPEED: float = 0.8
const SINK_DELAY: float = 1.2
## Summoning: the figure rises out of the ground over RISE_TIME (visual only —
## the unit acts from its first tick). RISE_DEPTH = its height.
const RISE_TIME: float = 0.9
## How fast the model's size follows a level-up (size factor per second).
const GROW_SPEED: float = 0.25
const RISE_DEPTH: float = Balance.GOLEM_HEIGHT + 0.2

# --- Model animation (assets/models/units/golem.glb) ---------------------------------
## Clip names the model may bring. All optional: a model without them (or the
## placeholder) still works, it just does not move its limbs.
const CLIP_IDLE: StringName = &"idle"
const CLIP_WALK: StringName = &"walk"
const CLIP_DEATH: StringName = &"death"
## Ground speed (m/s) the walk clip covers at speed scale 1 — the model's stride
## per cycle divided by the cycle length (golem_export.mjs reports 2,658 m per
## 1-s cycle at the 4-m model height), scaled with the figure. The clip is played
## faster or slower so the feet match the real speed.
const WALK_CLIP_SPEED: float = 2.658 * MODEL_SCALE
## Cross-fade between clips (s), and the speed (m/s) above which she walks.
const CLIP_BLEND: float = 0.15
const WALK_THRESHOLD: float = 0.3

const C_STONE: Color = Color(0.46, 0.45, 0.43)
const C_STONE_DARK: Color = Color(0.32, 0.31, 0.3)
const C_STONE_LIGHT: Color = Color(0.58, 0.57, 0.54)

## Seconds of life left; the golem crumbles at zero (never at the maximum level).
var life_left: float = Balance.GOLEM_LIFETIME
## Kills credited to the golem (attacks AND trampling; each one extends the life).
var kills: int = 0
## Level 0 .. Balance.GOLEM_MAX_LEVEL (see level_for_kills).
var level: int = 0
## The spell context of the summoning (set by GolemSpell): the level-7 giant
## needs it to level the ground. Null (tests, odd spawns) = no levelling.
var terrain_ctx: SpellContext = null
## The running ground-levelling morph and the seconds until the next check.
var _flatten_morph: TerrainMorph = null
var _flatten_timer: float = 0.0
## Heights the terrain had BEFORE this golem lowered it: vertex index -> height.
## The level he flattens to is the lowest NATURAL ground under him — without
## this memory his own pit would count as "the lowest spot", he would drag it
## along as he walks and cut the whole route down to the first shore he stood
## on (user report 2026-11-15).
var _flatten_natural: Dictionary = {}
## Growth steps beyond level 7 (see growth_steps_for_kills).
var growth_steps: int = 0

## Fraction of a health point the level regeneration has built up.
var _level_regen_frac: float = 0.0
## Position at the end of the previous tick (INF = none yet) — how far it walked.
var _tick_pos: Vector3 = Vector3.INF
## Trample cooldowns: victim instance id -> seconds until it can be hit again.
var _trampled: Dictionary = {}
## Size the model is drawn at right now; eases toward size_factor() on a level-up.
var _shown_size: float = 1.0

## The attack that is wound up right now (&"" = none) and the seconds until it
## lands. `_pending_building` is the assault target that is guaranteed its stage.
var _pending_attack: StringName = &""
var _pending_time: float = 0.0
var _pending_building = null
## The airship a wound-up swat is aimed at.
var _pending_airship: Airship = null
## Seconds until the next attack may begin OUTSIDE the melee loop (the swat at
## an airship while idle or walking). Every wind-up resets it, so the overall
## cadence stays GOLEM_STRIKE_COOLDOWN whichever attack comes next.
var _air_cooldown: float = 0.0
## The airship the golem is walking after (maximum level, see _tick_air_chase),
## and the seconds until the chase looks again.
var _chase_ship: Airship = null
var _chase_timer: float = 0.0
## True only while the chase issues its own move order (see order_move).
var _own_order: bool = false

var _model: Node3D = null
var _arm: Node3D = null
var _flag_mesh: MeshInstance3D = null
var _anim: AnimationPlayer = null
var _clip: StringName = &""
## Strike swing progress of the placeholder arms (0 = just begun, 1 = at rest).
var _arm_anim: float = 1.0
var _rise: float = 0.0
var _dead_time: float = 0.0
var _last_pos: Vector3 = Vector3.INF


func _init() -> void:
	max_health = Balance.GOLEM_HP
	health = max_health
	speed = Balance.GOLEM_SPEED
	push_immune = true                 # infantry does not shove the giant around
	vehicle_separation = Balance.GOLEM_SEPARATION   # ...but big bodies keep apart
	joins_idle_groups = false          # never docks onto idle 6-packs
	counts_population = false          # a construct, not a believer


# --- Identity & rules --------------------------------------------------------------

func unit_kind() -> StringName:
	return &"golem"


func display_name() -> String:
	return "Golem"


## The golem's vital numbers for the sidebar panel (shown while it is selected):
## level and the kills to the next step, size, health, lifetime.
func status_text() -> String:
	var next: String = ""
	if level < Balance.GOLEM_MAX_LEVEL:
		next = "   noch %d Kills bis Stufe %d" % [kills_for_level(level + 1) - kills, level + 1]
	elif growth_steps < max_growth_steps():
		var base: int = kills_for_level(Balance.GOLEM_MAX_LEVEL)
		next = "   noch %d Kills bis zum nächsten Wachstum" % [
			base + (growth_steps + 1) * Balance.GOLEM_GROWTH_KILLS - kills]
	var life: String = "unbegrenzt" if level >= Balance.GOLEM_FINAL_BONUS_LEVEL \
		else "%d s" % int(ceil(maxf(life_left, 0.0)))
	return "Stufe %d/%d%s\nGröße: %.1f m   Leben: %d/%d\nLebenszeit: %s   Kills: %d" % [
		level, Balance.GOLEM_MAX_LEVEL, next, height_m(), health, max_health, life, kills]


func _is_combatant() -> bool:
	return true


## The existing "no melee groups" switch (see class doc). Side effects handled
## here: airborne targets are refused in _begin_attack, buildings are struck from
## outside in _bombard_building.
func _is_ranged() -> bool:
	return true


func renders_as_sprite() -> bool:
	return false   # own 3D model


func death_sfx_key() -> StringName:
	return &"golem_death"


func is_conversion_immune() -> bool:
	return true


func is_hypnosis_immune() -> bool:
	return true


func is_panic_immune() -> bool:
	return true


func can_crew_siege() -> bool:
	return false


func can_garrison() -> bool:
	return false


func burn_damage_per_second() -> float:
	return Balance.GOLEM_BURN_DPS


func burn_fx_scale() -> float:
	return 2.5 * size_factor()


func burn_fx_height() -> float:
	return Balance.GOLEM_HEIGHT * 0.75 * size_factor()


## Too heavy to be thrown, rolled or shoved (damage still applies).
func throw_airborne(_velocity: Vector3, _fall_damage: int = 0,
		_force: bool = false) -> void:
	pass


func start_roll(_dir: Vector3, _duration: float = MINI_ROLL_DURATION,
		_initial_speed: float = 0.0, _stumble: bool = false) -> void:
	pass


func displace(_dir: Vector3, _dist: float) -> void:
	pass


## Whole hull is clickable; the selection ring encloses the body.
func pick_size_m() -> Vector2:
	return Vector2(BODY_HALF_WIDTH * 2.0, Balance.GOLEM_HEIGHT) * size_factor()


func selection_ring_scale() -> float:
	return 2.43 * size_factor()   # ring radius 0,83 m around the 1,55-m-wide body


# --- Lifetime -----------------------------------------------------------------------

func tick(delta: float) -> void:
	super.tick(delta)
	_tick_pending_attack(delta)
	if state != State.DEAD and not doomed and not garrison_housed:
		_tick_air_strike(delta)
		_tick_air_chase(delta)
		_tick_level_regen(delta)
		_tick_trample(delta)
		_tick_flatten(delta)
		# From the final-bonus level on the lifetime no longer runs out (user spec).
		if level < Balance.GOLEM_FINAL_BONUS_LEVEL:
			life_left -= delta
			if life_left <= 0.0:
				_crumble()
	_tick_pos = position
	_tick_visual(delta)


# --- Levels -------------------------------------------------------------------------

## Kills needed for `p_level`: six per level up to the final-bonus level (6 = 36
## kills), then GOLEM_TOP_LEVEL_KILLS more for the last one (7 = 86 kills).
static func kills_for_level(p_level: int) -> int:
	var regular: int = mini(p_level, Balance.GOLEM_FINAL_BONUS_LEVEL)
	var kills_needed: int = regular * Balance.GOLEM_KILLS_PER_LEVEL
	if p_level > Balance.GOLEM_FINAL_BONUS_LEVEL:
		kills_needed += (p_level - Balance.GOLEM_FINAL_BONUS_LEVEL) * Balance.GOLEM_TOP_LEVEL_KILLS
	return kills_needed


## Level a golem with `p_kills` kills has reached.
static func level_for_kills(p_kills: int) -> int:
	var lvl: int = 0
	while lvl < Balance.GOLEM_MAX_LEVEL and p_kills >= kills_for_level(lvl + 1):
		lvl += 1
	return lvl


## How much bigger than a fresh golem a golem of `p_level` is: every level is
## GOLEM_LEVEL_GROWTH bigger than the one before (compounded, user spec —
## 1,2 ^ level: level 5 is 2,49 times the starting size).
static func size_factor_for(p_level: int) -> float:
	var regular: int = mini(p_level, Balance.GOLEM_FINAL_BONUS_LEVEL)
	var f: float = pow(1.0 + Balance.GOLEM_LEVEL_GROWTH, float(regular))
	if p_level > Balance.GOLEM_FINAL_BONUS_LEVEL:
		# Level 7, the giant: half as big again (user spec).
		f *= pow(1.0 + Balance.GOLEM_TOP_LEVEL_GROWTH,
			float(p_level - Balance.GOLEM_FINAL_BONUS_LEVEL))
	return f


## Ground speed at `p_level`: the stride grows with the body, the cadence eases
## off with it (speed ~ square root of the size) — deliberately modest.
static func speed_for(p_level: int) -> float:
	return Balance.GOLEM_SPEED * sqrt(size_factor_for(p_level))


## Growth steps a golem with `p_kills` kills has taken BEYOND level 7: one per
## GOLEM_GROWTH_KILLS, until the body would pass GOLEM_MAX_HEIGHT.
static func growth_steps_for_kills(p_kills: int) -> int:
	var extra: int = p_kills - kills_for_level(Balance.GOLEM_MAX_LEVEL)
	if extra <= 0:
		return 0
	return mini(extra / Balance.GOLEM_GROWTH_KILLS, max_growth_steps())


## The step at which the body reaches GOLEM_MAX_HEIGHT (its size is clamped there).
static func max_growth_steps() -> int:
	var room: float = max_size_factor() / size_factor_for(Balance.GOLEM_MAX_LEVEL)
	if room <= 1.0:
		return 0
	return int(ceil(log(room) / log(1.0 + Balance.GOLEM_GROWTH_SIZE) - 0.000001))


## Size factor at which the figure is GOLEM_MAX_HEIGHT tall.
static func max_size_factor() -> float:
	return Balance.GOLEM_MAX_HEIGHT / Balance.GOLEM_HEIGHT


func size_factor() -> float:
	return minf(size_factor_for(level)
		* pow(1.0 + Balance.GOLEM_GROWTH_SIZE, float(growth_steps)), max_size_factor())


## Factor of the strike areas and the trample radius from the growth steps
## beyond level 7 (1 below that): they grow far slower than the body.
func growth_area_factor() -> float:
	return pow(1.0 + Balance.GOLEM_GROWTH_AREA, float(growth_steps))


## How much further a golem of `p_level` reaches and strikes than a fresh one:
## GOLEM_LEVEL_REACH_GROWTH per level, compounded — on purpose slower than the
## body grows (user spec: about 10 percent a level).
static func reach_factor_for(p_level: int) -> float:
	var regular: int = mini(p_level, Balance.GOLEM_FINAL_BONUS_LEVEL)
	var f: float = pow(1.0 + Balance.GOLEM_LEVEL_REACH_GROWTH, float(regular))
	if p_level > Balance.GOLEM_FINAL_BONUS_LEVEL:
		f *= pow(1.0 + Balance.GOLEM_TOP_LEVEL_REACH_GROWTH,
			float(p_level - Balance.GOLEM_FINAL_BONUS_LEVEL))
	return f


## Scale of the reach and of both strike areas at the current level.
func reach_factor() -> float:
	return reach_factor_for(level) * growth_area_factor()


func reach() -> float:
	return REACH * reach_factor()


## Flat damage bonus of the current level: GOLEM_LEVEL_DAMAGE per level up to the
## final-bonus level — level 7 adds no more damage (user spec).
func level_damage_bonus() -> int:
	return Balance.GOLEM_LEVEL_DAMAGE * mini(level, Balance.GOLEM_FINAL_BONUS_LEVEL)


## Damage of an attack at the current level.
func attack_damage(kind: StringName) -> int:
	var base: int = Balance.GOLEM_KICK_DAMAGE if kind == ATTACK_KICK else Balance.GOLEM_SLAM_DAMAGE
	return base + level_damage_bonus()


## Trample damage comes from the SIZE (user spec 2026-11-15): body height in
## metres / GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE, rounded, at least 1.
func trample_damage() -> int:
	return maxi(1, int(round(height_m() / Balance.GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE)))


## Body height in metres right now.
func height_m() -> float:
	return Balance.GOLEM_HEIGHT * size_factor()


## Radius around the golem's centre it tramples in: its body, grown with the
## level — and beyond level 7 only with the slow area growth, not with the body.
func trample_radius() -> float:
	return BODY_HALF_WIDTH * size_factor_for(level) * growth_area_factor()


## Ground speed right now: the level's speed, plus the slight gain per growth step.
func current_speed() -> float:
	return speed_for(level) * pow(1.0 + Balance.GOLEM_GROWTH_SPEED, float(growth_steps))


## From level 1 the golem walks straight through other units (and tramples the
## enemies among them).
func ignores_unit_collision() -> bool:
	return level >= 1


## A kill — by an attack or underfoot: buys time, raises the health limit, patches
## the construct up (to that limit) and counts toward the next level.
func _credit_kill() -> void:
	kills += 1
	life_left += Balance.GOLEM_LIFE_PER_KILL
	max_health = mini(max_health + Balance.GOLEM_MAX_HP_PER_KILL, Balance.GOLEM_MAX_HP_CAP)
	health = mini(health + Balance.GOLEM_HP_PER_KILL, max_health)
	while level < level_for_kills(kills):
		_level_up()
	var steps: int = growth_steps_for_kills(kills)
	if steps != growth_steps:
		growth_steps = steps
		_apply_speed()


func _level_up() -> void:
	level += 1
	life_left += Balance.GOLEM_LEVEL_LIFETIME
	if level >= Balance.GOLEM_MAX_LEVEL:
		max_health = Balance.GOLEM_MAX_HP_CAP   # the giant: flat 1000 (user spec)
	_apply_speed()
	_sync_soa_flags()   # level 1 switches the unit collision off


func _apply_speed() -> void:
	speed = current_speed()
	# The manager mirrors the walk speed at registration ("static per unit kind")
	# — keep its copy in step, even though the golem is not kernel-walked today.
	if _idx >= 0 and path_service is UnitManager:
		(path_service as UnitManager).soa_speed[_idx] = speed


## Radius of the ground the giant levels: his body.
func flatten_radius() -> float:
	return trample_radius()


## The height map of one levelling step under the golem at `at`: every terrain
## vertex within `radius` goes down to the LOWEST one among them, and around that
## plate the ground is cut back to a walkable bank (at most `slope` metres of
## rise per metre) — never raised. `max_drop` limits how far any vertex sinks in
## this one step (the levelling is gradual). Same plan format as
## FlattenSpell.flatten_targets. Empty when the ground under him is already
## level (spread <= `min_spread`).
##
## `natural` (vertex index -> height before this golem touched it) decides the
## LEVEL: the plate goes to the lowest NATURAL ground under him, so ground he has
## already lowered does not pull the level down any further. Vertices that
## already lie below that level are left alone (never raised).
##
## `floor_height` is the waterline guard: no vertex is lowered below it, and
## ground that already lies at or below it (the sea bed) is not touched at all.
static func flatten_plan(td: TerrainData, at: Vector3, radius: float, slope: float,
		min_spread: float, max_drop: float = INF, natural: Dictionary = {},
		floor_height: float = -INF) -> Dictionary:
	var cs: float = TerrainData.CELL_SIZE
	var empty: Dictionary = {"indices": PackedInt32Array(), "targets": PackedFloat32Array(),
		"rect": Rect2i()}
	var cx: float = at.x / cs
	var cz: float = at.z / cs
	var rv: float = radius / cs
	var lo: float = INF
	var hi: float = -INF
	for vz in range(maxi(int(ceil(cz - rv)), 0), mini(int(floor(cz + rv)), td.verts - 1) + 1):
		for vx in range(maxi(int(ceil(cx - rv)), 0), mini(int(floor(cx + rv)), td.verts - 1) + 1):
			var d2: float = (float(vx) - cx) * (float(vx) - cx) + (float(vz) - cz) * (float(vz) - cz)
			if d2 > rv * rv:
				continue
			var idx0: int = vz * td.verts + vx
			var h: float = td.heights[idx0]
			# The level comes from the natural ground, the spread from what is
			# there NOW (so a finished plate is recognised as level).
			lo = minf(lo, float(natural.get(idx0, h)))
			hi = maxf(hi, h)
	if lo == INF:
		return empty
	# Never below the waterline: at the shore the plate stops just above the sea.
	lo = maxf(lo, floor_height)
	if hi - lo <= min_spread:
		return empty
	# The bank reaches as far as the highest ground under him needs to come down.
	var bank: float = (hi - lo) / maxf(slope, 0.05) + cs
	var reach_v: float = rv + bank / cs
	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	var min_v: Vector2i = Vector2i(td.verts, td.verts)
	var max_v: Vector2i = Vector2i(-1, -1)
	for vz in range(maxi(int(ceil(cz - reach_v)), 0), mini(int(floor(cz + reach_v)), td.verts - 1) + 1):
		for vx in range(maxi(int(ceil(cx - reach_v)), 0), mini(int(floor(cx + reach_v)), td.verts - 1) + 1):
			var d: float = sqrt((float(vx) - cx) * (float(vx) - cx)
				+ (float(vz) - cz) * (float(vz) - cz)) * cs
			var limit: float = lo + maxf(d - radius, 0.0) * slope
			var idx: int = vz * td.verts + vx
			if td.heights[idx] <= limit + 0.01 or td.heights[idx] <= floor_height:
				continue   # already at or below the plate / the bank, or sea bed
			indices.append(idx)
			targets.append(maxf(limit, td.heights[idx] - max_drop))
			min_v = Vector2i(mini(min_v.x, vx), mini(min_v.y, vz))
			max_v = Vector2i(maxi(max_v.x, vx), maxi(max_v.y, vz))
	if indices.is_empty():
		return empty
	var cmin: Vector2i = Vector2i(clampi(min_v.x - 1, 0, td.size - 1),
		clampi(min_v.y - 1, 0, td.size - 1))
	var cmax: Vector2i = Vector2i(clampi(max_v.x, 0, td.size - 1),
		clampi(max_v.y, 0, td.size - 1))
	return {"indices": indices, "targets": targets,
		"rect": Rect2i(cmin, cmax - cmin + Vector2i.ONE)}


## Level 7, the giant: the ground he stands on becomes level — it sinks to the
## lowest spot under his body (user spec) — gradually, at most GOLEM_FLATTEN_RATE
## metres per second. Checked every GOLEM_FLATTEN_INTERVAL, one morph at a time; the usual terrain rules apply (TerrainMorph: buildings on
## a new edge burst, the flooded drown, everything rides the moving ground).
func _tick_flatten(delta: float) -> void:
	if level < Balance.GOLEM_MAX_LEVEL or terrain_ctx == null or terrain_data == null \
			or path_service == null:
		return
	_flatten_timer -= delta
	if _flatten_timer > 0.0:
		return
	_flatten_timer = Balance.GOLEM_FLATTEN_INTERVAL
	if _flatten_morph != null and is_instance_valid(_flatten_morph) and not _flatten_morph.done:
		return
	_flatten_morph = null
	var plan: Dictionary = flatten_plan(terrain_data, position, flatten_radius(),
		Balance.GOLEM_FLATTEN_SLOPE, Balance.GOLEM_FLATTEN_MIN_SPREAD,
		Balance.GOLEM_FLATTEN_RATE * Balance.GOLEM_FLATTEN_INTERVAL, _flatten_natural,
		TerrainData.SEA_LEVEL + Balance.GOLEM_FLATTEN_ABOVE_WATER)
	var touched: PackedInt32Array = plan.indices
	if touched.is_empty():
		return
	# Remember what the ground looked like before he lowered it (first touch only).
	for idx in touched:
		if not _flatten_natural.has(idx):
			_flatten_natural[idx] = terrain_data.heights[idx]
	_prune_flatten_memory()
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(terrain_ctx, plan, Balance.GOLEM_FLATTEN_DURATION)
	path_service.register_projectile(morph)
	_flatten_morph = morph


## Keeps the memory of natural heights from growing without bound: once it is
## large, everything far behind him is forgotten (ground he returns to later then
## simply counts as natural again).
func _prune_flatten_memory() -> void:
	if _flatten_natural.size() < FLATTEN_MEMORY_MAX or terrain_data == null:
		return
	var keep: float = flatten_radius() * 4.0 + 20.0
	var verts: int = terrain_data.verts
	for idx in _flatten_natural.keys():
		var dx: float = float(idx % verts) * TerrainData.CELL_SIZE - position.x
		var dz: float = float(idx / verts) * TerrainData.CELL_SIZE - position.z
		if dx * dx + dz * dz > keep * keep:
			_flatten_natural.erase(idx)


## Permanent healing from level 1 on: GOLEM_LEVEL_REGEN health per second and
## level, right through a fight — up to max_health, which only kills raise
## (without that limit he would heal himself up endlessly).
func _tick_level_regen(delta: float) -> void:
	if level <= 0 or health >= max_health:
		_level_regen_frac = 0.0
		return
	_level_regen_frac += Balance.GOLEM_LEVEL_REGEN * float(level) * delta
	if _level_regen_frac >= 1.0:
		var heal: int = int(_level_regen_frac)
		_level_regen_frac -= float(heal)
		health = mini(health + heal, max_health)


## Trampling (from level 1): every enemy under the body takes damage while the
## golem WALKS — never while it stands, and the same victim at most once per
## GOLEM_TRAMPLE_INTERVAL. Same victims as the attacks: living, targetable, on
## the ground, no devices; own units are never hurt.
func _tick_trample(delta: float) -> void:
	if not _trampled.is_empty():
		for id in _trampled.keys():
			_trampled[id] -= delta
			if _trampled[id] <= 0.0:
				_trampled.erase(id)
	if level <= 0 or path_service == null or _tick_pos == Vector3.INF or delta <= 0.0:
		return
	var walked: float = Vector2(position.x - _tick_pos.x, position.z - _tick_pos.z).length()
	if walked / delta < Balance.GOLEM_TRAMPLE_MIN_SPEED:
		return
	var damage: int = trample_damage()
	for u in path_service.get_units_in_radius(position, trample_radius()):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		var id: int = u.get_instance_id()
		if _trampled.has(id):
			continue
		_trampled[id] = Balance.GOLEM_TRAMPLE_INTERVAL
		_no_combat_timer = 0.0
		u.take_damage(damage, self)
		if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
			_credit_kill()
	# The giant (maximum level) walks buildings down as well: one destruction
	# stage every GOLEM_TRAMPLE_BUILDING_INTERVAL for each enemy building under him.
	if level < Balance.GOLEM_MAX_LEVEL or building_manager == null:
		return
	var here: Vector2 = Vector2(position.x, position.z)
	var radius: float = trample_radius()
	for b in building_manager.buildings.duplicate():
		if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == tribe_id \
				or not b.is_attackable():
			continue
		if b.footprint_distance_to(here) > radius:
			continue
		var bid: int = b.get_instance_id()
		if _trampled.has(bid):
			continue
		_trampled[bid] = Balance.GOLEM_TRAMPLE_BUILDING_INTERVAL
		_no_combat_timer = 0.0
		_strike_building(b)


## Time is up: the construct falls apart (a normal death — corpse, sink, removal).
func _crumble() -> void:
	if state == State.DEAD:
		return
	life_left = 0.0
	health = 0
	_die()


# --- Combat -------------------------------------------------------------------------

## Sent off WITHOUT an attack order (a plain move), the golem walks to his goal
## and lets himself be beaten on the way (user spec 2026-11-15): the base rule
## "a fleeing unit hits back after every third melee hit" would stop him at every
## skirmish he passes. Standing still or on an attack-move he fights as usual.
func _maybe_retaliate(attacker) -> void:
	if state == State.MOVE and not move_aggressive:
		return
	super._maybe_retaliate(attacker)


## Melee cannot reach flyers — _is_ranged() would otherwise let the base lock
## onto airborne targets.
func _begin_attack(enemy: Unit) -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.is_airborne():
		return
	super._begin_attack(enemy)


## Lean attack loop without the group machinery: close to REACH, then attack on
## cooldown. Stays object-ticked (no SoA melee hold) — there are only ever a
## handful of golems.
##
## Target discipline (user feedback 2026-09-06): the golem does NOT run after a
## target it just hurled away while other enemies stand within reach — it turns
## on the nearest one in reach instead. Only when nobody is in reach does it
## chase; a target still in the air is waited for, not followed.
##
## While an attack is wound up she stands and finishes it: no retargeting, no
## chasing in mid-swing.
func _tick_attack(delta: float) -> void:
	if _pending_attack != &"":
		_attack_cooldown -= delta
		return
	if not _unit_target_attackable(attack_target) or attack_target.tribe_id == tribe_id:
		_tick_no_unit_target(delta)
		return
	var target: Unit = attack_target
	var dist: float = _flat_dist(position, target.position)
	if dist > reach() or target.is_airborne():
		var near: Unit = _nearest_enemy_in_reach()
		if near != null and near != target:
			_begin_attack(near)   # retarget keeps the cooldown (state stays ATTACK)
			return
		if target.is_airborne():
			_in_melee = false
			if _has_path():
				_clear_path()
			_face_point(target.position)   # wait for the body to land
			return
		_in_melee = false
		if not _approach(target.position, delta):
			_mark_target_unreachable(target)
			_retarget_or_idle()
			return
		_face_point(target.position)
		return
	if _has_path():
		_clear_path()
	_in_melee = true
	_face_point(target.position)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = STRIKE_COOLDOWN
		var ship: Airship = _airship_in_reach()
		if ship != null:
			_swat(ship)   # an airship overhead goes before the crowd at her feet
		else:
			_wind_up(_choose_attack())


## Nearest living, standing enemy within reach() that the golem can strike (no
## flyers, no sitting converts, no devices); null when nobody is that close.
func _nearest_enemy_in_reach() -> Unit:
	if path_service == null:
		return null
	var best: Unit = null
	var best_d: float = INF
	for u in path_service.get_units_in_radius(position, reach()):
		if u == self or u.tribe_id == tribe_id or u.state == State.DEAD \
				or u.state == State.SIT:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


## Building assault from OUTSIDE (the _is_ranged() dispatch lands here): walk to
## just inside REACH of the footprint, then attack on cooldown. The target
## building is guaranteed its stage per attack even when the area geometry
## misses it (e.g. an odd footprint corner) — see _land_attack.
func _bombard_building(building, delta: float) -> void:
	if _pending_attack != &"":
		_attack_cooldown -= delta
		return
	var center: Vector3 = building.center_world()
	var flat: Vector2 = Vector2(position.x, position.z)
	if building.footprint_distance_to(flat) > reach() - 0.5:
		_in_melee = false
		# Never path onto the footprint itself (unwalkable): stop short of it.
		_approach(stand_off_point(position, center, reach() * APPROACH_RANGE_FRACTION), delta)
		_face_point(center)
		return
	if _has_path():
		_clear_path()
	_in_melee = true
	_face_point(center)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = STRIKE_COOLDOWN
		_wind_up(_choose_attack(), building)


## True when the point at (along, side) in the heading frame lies inside the
## slam: the circle around the spot where the hands come down. `scale` = the
## golem's reach_factor() (1 = level 0).
static func in_slam_area(along: float, side: float, scale: float = 1.0) -> bool:
	var a: float = along - SLAM_FORWARD * scale
	var r: float = SLAM_RADIUS * scale
	return a * a + side * side <= r * r


## True when the point lies in the kick's lane: straight ahead of the golem and,
## for the backswing, a shorter stretch behind her.
static func in_kick_lane(along: float, side: float, scale: float = 1.0) -> bool:
	return along >= -KICK_BACK * scale and along <= KICK_LENGTH * scale \
		and absf(side) <= KICK_HALF_WIDTH * scale


static func in_attack_area(kind: StringName, along: float, side: float,
		scale: float = 1.0) -> bool:
	if kind == ATTACK_KICK:
		return in_kick_lane(along, side, scale)
	return in_slam_area(along, side, scale)


static func attack_windup(kind: StringName) -> float:
	if kind == ATTACK_SWAT:
		return Balance.GOLEM_SWAT_WINDUP
	return Balance.GOLEM_KICK_WINDUP if kind == ATTACK_KICK else Balance.GOLEM_SLAM_WINDUP


## Playback speed of an attack animation: a bigger body swings slower (with the
## root of its size, like the stride) — but never so slow that the animation
## would outlast the attack cooldown. At that limit one attack flows straight
## into the next; she no longer stands idle in between (user spec 2026-11-15).
## The attack RATE is untouched (GOLEM_STRIKE_COOLDOWN), only the wind-up grows.
func attack_speed(kind: StringName) -> float:
	var slowest: float = float(CLIP_LENGTH.get(kind, STRIKE_COOLDOWN)) / STRIKE_COOLDOWN
	return clampf(1.0 / sqrt(size_factor()), slowest, 1.0)


## Seconds from the start of an attack to its impact at the current size.
func current_windup(kind: StringName) -> float:
	return attack_windup(kind) / attack_speed(kind)


# --- The giant's straight routes (maximum level) ---------------------------------------

## Sample distance along a line the giant wants to walk (metres).
const GIANT_LINE_STEP: float = 0.5

## From the highest level on the giant walks in straight lines: buildings, trees
## and ordinary terrain no longer stop him (user spec 2026-11-15). Only the sea,
## the rim of the world and big cliffs do.
func walks_straight() -> bool:
	return level >= Balance.GOLEM_MAX_LEVEL


## The tallest step the giant still takes: metres of height per metre of way.
func giant_step_limit() -> float:
	return height_m() * Balance.GOLEM_GIANT_STEP_SHARE


## True when a giant can walk the straight line from `from` to `to`: ground all
## the way (no void), never the sea, and no cliff taller than `max_step` metres
## within one metre of way. Buildings and the walkability grid are NOT asked —
## that is the point.
static func giant_line_clear(td: TerrainData, from: Vector3, to: Vector3,
		max_step: float) -> bool:
	var a: Vector2 = Vector2(from.x, from.z)
	var b: Vector2 = Vector2(to.x, to.z)
	var dist: float = a.distance_to(b)
	var steps: int = maxi(1, int(ceil(dist / GIANT_LINE_STEP)))
	# Heights of the two samples before the current one: the cliff test compares
	# over a full metre (two samples), so a slope sampled finely is not mistaken
	# for level ground.
	var h_prev: float = td.get_height(a.x, a.y)
	var h_prev2: float = h_prev
	for i in range(1, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		if not td.has_ground(p.x, p.y):
			return false
		var h: float = td.get_height(p.x, p.y)
		if h <= TerrainData.SEA_LEVEL + WATER_EPS:
			return false
		if absf(h - h_prev2) > max_step:
			return false
		h_prev2 = h_prev
		h_prev = h
	return true


## Where a route to `target` ends for the giant: the point itself, or — when it
## lies inside a building or on ground nobody can stand on — the nearest
## walkable cell (he walks THROUGH buildings, he does not stop inside one).
func _giant_goal(target: Vector3) -> Vector3:
	var goal: Vector3 = target
	if nav_grid != null:
		var cell: Vector2i = nav_grid.world_to_cell(target)
		if not nav_grid.is_cell_walkable(cell):
			var near: Vector2i = nav_grid.nearest_walkable_cell(cell)
			if near.x >= 0:
				goal = nav_grid.cell_to_world(near)
	goal.y = terrain_data.get_height(goal.x, goal.z)
	return goal


## Pulls a planned route straight: from each point on, every waypoint is skipped
## that the giant can reach in one straight line. What is left are the few bends
## the sea or a big cliff really force — no zigzag along the grid, no detour
## around a house. (Binary search for the furthest reachable waypoint: not exact
## where reachability flips back and forth, but cheap and always a valid route —
## the next waypoint of the planned path is taken when nothing further works.)
func _straighten(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() < 2 or terrain_data == null:
		return path
	var limit: float = giant_step_limit()
	var out: PackedVector3Array = PackedVector3Array()
	var anchor: Vector3 = position
	var i: int = 0
	var last: int = path.size() - 1
	while i <= last:
		var far: int = i
		if giant_line_clear(terrain_data, anchor, path[last], limit):
			far = last
		else:
			var lo: int = i
			var hi: int = last - 1
			while lo < hi:
				var mid: int = (lo + hi + 1) / 2
				if giant_line_clear(terrain_data, anchor, path[mid], limit):
					lo = mid
				else:
					hi = mid - 1
			far = lo
		out.append(path[far])
		anchor = path[far]
		i = far + 1
	return out


## A move order: the giant takes the straight line when it is free — at once,
## without the path queue. Otherwise the normal search runs (and its result is
## straightened, see _plan_path_to / _apply_worker_path).
func _start_path_to(target: Vector3) -> void:
	if walks_straight() and terrain_data != null:
		var goal: Vector3 = _giant_goal(target)
		if giant_line_clear(terrain_data, position, goal, giant_step_limit()):
			_clear_soa_hold()
			_pending_target = Vector3.INF   # cancels a queued request, like set_path
			_path = PackedVector3Array([goal])
			_path_index = 0
			_set_state(State.MOVE)
			return
	super._start_path_to(target)


func _plan_path_to(target: Vector3, allow_partial: bool = false) -> bool:
	if not walks_straight() or terrain_data == null:
		return super._plan_path_to(target, allow_partial)
	var goal: Vector3 = _giant_goal(target)
	if giant_line_clear(terrain_data, position, goal, giant_step_limit()):
		_path = PackedVector3Array([goal])
		_path_index = 0
		return true
	if not super._plan_path_to(target, allow_partial):
		return false
	_path = _straighten(_path)
	_path_index = 0
	return true


func _apply_worker_path(request_id: int, cells: PackedVector2Array) -> void:
	super._apply_worker_path(request_id, cells)
	if walks_straight() and _has_path() and _path_index == 0:
		_path = _straighten(_path)


## The last metres to a target (combat approach): everyone else stops at a cell
## that is not walkable, the giant only at the sea, the void or a big cliff.
func _step_toward(point: Vector3, delta: float) -> void:
	if not walks_straight() or terrain_data == null:
		super._step_toward(point, delta)
		return
	var flat: Vector2 = Vector2(position.x, position.z)
	var flat_target: Vector2 = Vector2(point.x, point.z)
	var to_target: Vector2 = flat_target - flat
	if to_target.length_squared() > 0.000001:
		facing = Vector3(to_target.x, 0.0, to_target.y).normalized()
	var next: Vector2 = flat.move_toward(flat_target, _slope_speed(_slope_ahead(to_target)) * delta)
	if not giant_line_clear(terrain_data, position, Vector3(next.x, 0.0, next.y),
			giant_step_limit()):
		return
	position = Vector3(next.x, position.y, next.y)
	_snap_to_ground()


# --- Airships (maximum level) ---------------------------------------------------------

func can_strike_air() -> bool:
	return level >= Balance.GOLEM_FINAL_BONUS_LEVEL


## Nearest enemy airship the golem can swat right now: maximum level only, a
## crewed ship (a neutral one is nobody's target), within reach() — measured
## FLAT, the same reach as on the ground.
func _airship_in_reach() -> Airship:
	if not can_strike_air() or path_service == null:
		return null
	var best: Airship = null
	var best_d: float = INF
	for u in path_service.get_enemy_vehicles_in_radius(position, reach(), tribe_id):
		if not (u is Airship) or not (u as Airship).auto_attackable():
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d:
			best_d = d
			best = u as Airship
	return best


## Where the golem has to walk to get under `ship`: the spot below it when he
## can reach that on foot, else the nearest walkable spot that still lies within
## striking distance of the ship. Vector3.INF = out of his reach (open water, the
## void, another island).
func _chase_point(ship: Airship) -> Vector3:
	if nav_grid == null:
		return Vector3.INF
	var below: Vector3 = Vector3(ship.position.x, position.y, ship.position.z)
	var cell: Vector2i = nav_grid.nearest_walkable_cell(nav_grid.world_to_cell(below))
	if cell.x < 0:
		return Vector3.INF
	var spot: Vector3 = nav_grid.cell_to_world(cell)
	if _flat_dist(spot, below) > reach() * AIR_CHASE_STAND:
		return Vector3.INF
	if not nav_grid.same_island(position, spot):
		return Vector3.INF
	return spot


## Nearest crewed enemy airship within GOLEM_AIR_CHASE_RADIUS that the golem can
## get under on foot.
func _chase_target() -> Airship:
	if not can_strike_air() or path_service == null:
		return null
	var best: Airship = null
	var best_d: float = INF
	for u in path_service.get_enemy_vehicles_in_radius(position,
			Balance.GOLEM_AIR_CHASE_RADIUS, tribe_id):
		if not (u is Airship) or not (u as Airship).auto_attackable():
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d and _chase_point(u as Airship) != Vector3.INF:
			best_d = d
			best = u as Airship
	return best


## The airship chase (maximum level): an IDLE golem walks after a reachable enemy
## airship and keeps re-aiming while it moves; the swat itself comes from
## _tick_air_strike as soon as the ship is in reach. It is an attack-move, so he
## still deals with what stands in his way. Any order from outside ends it.
func _tick_air_chase(delta: float) -> void:
	if not can_strike_air():
		return
	_chase_timer -= delta
	if _chase_timer > 0.0:
		return
	_chase_timer = AIR_CHASE_INTERVAL
	var chasing: bool = _chase_ship != null and state == State.MOVE
	if state != State.IDLE and not chasing:
		return
	var ship: Airship = _chase_target()
	_chase_ship = ship
	if ship == null:
		return
	if _flat_dist(position, ship.position) <= reach() * AIR_CHASE_STAND:
		return   # close enough: stand and swat
	_own_order = true
	order_move(_chase_point(ship), false, true)
	_own_order = false


## An order from outside (player, AI) ends the airship chase; the chase's own
## move orders pass through.
func order_move(target: Vector3, queue_up: bool = false, aggressive: bool = false) -> void:
	if not _own_order:
		_chase_ship = null
	super.order_move(target, queue_up, aggressive)


func order_attack(enemy: Unit) -> void:
	_chase_ship = null
	super.order_attack(enemy)


func order_attack_building(building) -> void:
	_chase_ship = null
	super.order_attack_building(building)


## Winds up the upward strike at `ship`.
func _swat(ship: Airship) -> void:
	_face_point(ship.position)
	_wind_up(ATTACK_SWAT)
	_pending_airship = ship


## Swats at an airship in reach while NOT in the melee loop (idle, walking,
## closing in on something) — in melee the attack loop does it on its own
## cooldown. One shared cadence: _wind_up resets _air_cooldown.
func _tick_air_strike(delta: float) -> void:
	_air_cooldown = maxf(_air_cooldown - delta, 0.0)
	if _air_cooldown > 0.0 or _pending_attack != &"" or not can_strike_air():
		return
	if state == State.ATTACK and _in_melee:
		return
	var ship: Airship = _airship_in_reach()
	if ship != null:
		_swat(ship)


## Heading frame of the golem: [forward, right], flat in XZ.
func _heading_frame() -> Array[Vector3]:
	var forward: Vector3 = Vector3(facing.x, 0.0, facing.z)
	forward = forward.normalized() if forward.length_squared() > 0.000001 else Vector3(0, 0, 1)
	return [forward, Vector3(-forward.z, 0.0, forward.x)]


## Every enemy unit the attack `kind` would strike right now: living, targetable,
## on the ground, no devices (they have no HP) — sitting converts included.
func _victims(kind: StringName) -> Array[Unit]:
	var out: Array[Unit] = []
	if path_service == null:
		return out
	var frame: Array[Vector3] = _heading_frame()
	var forward: Vector3 = frame[0]
	var right: Vector3 = frame[1]
	var size: float = reach_factor()
	# Broad phase: a circle around the middle of the area.
	var centre: Vector3 = position + forward * (SLAM_FORWARD * size)
	var broad: float = SLAM_RADIUS * size + 0.5
	if kind == ATTACK_KICK:
		centre = position + forward * ((KICK_LENGTH - KICK_BACK) * size * 0.5)
		broad = Vector2((KICK_LENGTH + KICK_BACK) * 0.5, KICK_HALF_WIDTH).length() * size + 0.5
	for u in path_service.get_units_in_radius(centre, broad):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue   # protected reserves, flyers, and devices (no HP) are out
		var rel: Vector3 = u.position - position
		var along: float = rel.x * forward.x + rel.z * forward.z
		var side: float = rel.x * right.x + rel.z * right.z
		if in_attack_area(kind, along, side, size):
			out.append(u)
	return out


## Slam when a crowd stands around her, kick otherwise (single targets and
## buildings): the kick hurts more but only clears a lane.
func _choose_attack() -> StringName:
	if _victims(ATTACK_SLAM).size() >= Balance.GOLEM_SLAM_MIN_TARGETS:
		return ATTACK_SLAM
	return ATTACK_KICK


## Begins an attack: the animation starts now, the damage lands after the
## wind-up (_tick_pending_attack). `building` = the assault target, if any.
func _wind_up(kind: StringName, building = null) -> void:
	_pending_attack = kind
	_pending_time = current_windup(kind)
	_pending_building = building
	_pending_airship = null
	_air_cooldown = STRIKE_COOLDOWN
	attack_anim = kind
	anim_base_name = attack_anim
	anim_start_ms = Time.get_ticks_msec()
	_arm_anim = 0.0
	_no_combat_timer = 0.0
	_play_clip(kind, attack_speed(kind), true)


func _tick_pending_attack(delta: float) -> void:
	if _pending_attack == &"":
		return
	if state == State.DEAD or doomed:
		_pending_attack = &""
		_pending_building = null
		_pending_airship = null
		return
	_pending_time -= delta
	if _pending_time > 0.0:
		return
	var kind: StringName = _pending_attack
	var building = _pending_building
	var ship: Airship = _pending_airship
	_pending_attack = &""
	_pending_building = null
	_pending_airship = null
	if kind == ATTACK_SWAT:
		_land_swat(ship)
		return
	var struck: Dictionary = _land_attack(kind)
	if building != null and is_instance_valid(building) and building.health > 0 \
			and not struck.has(building) and state == State.ATTACK \
			and attack_building == building:
		_strike_building(building)


## The swat LANDS: one hull hit on the airship it was aimed at — like a catapult
## hit, AIRSHIP_HULL_HITS of them bring the ship down. Misses when the ship has
## left the reach in the meantime (a little slack for its drift) or lost its crew.
## Returns whether it hit.
func _land_swat(ship: Airship) -> bool:
	_no_combat_timer = 0.0
	if ship == null or not is_instance_valid(ship) or ship.state == State.DEAD \
			or ship.tribe_id == tribe_id or not ship.auto_attackable():
		return false
	if _flat_dist(position, ship.position) > reach() * SWAT_SLACK:
		return false
	_play_sfx(&"golem_strike", 200)
	ship.register_hull_hit(position)
	return true


## The hand slam landing (see class doc). Returns the buildings it hit (keys).
func _smash() -> Dictionary:
	return _land_attack(ATTACK_SLAM)


## The kick landing (see class doc). Returns the buildings it hit (keys).
func _kick() -> Dictionary:
	return _land_attack(ATTACK_KICK)


## An attack LANDS: every enemy in its area takes the damage, survivors are
## thrown (slam: by chance, away from the golem; kick: all of them, along the
## kick), every enemy building in the area loses a stage. Kills extend the
## lifetime AND heal the golem. Returns the buildings it hit (keys) so the
## building assault can top up its target.
func _land_attack(kind: StringName) -> Dictionary:
	_no_combat_timer = 0.0
	_play_sfx(&"golem_strike", 200)
	var frame: Array[Vector3] = _heading_frame()
	var forward: Vector3 = frame[0]
	var kick: bool = kind == ATTACK_KICK
	var damage: int = attack_damage(kind)
	# The victims are collected first: a kill can raise the level, and the area
	# of THIS attack must not grow while it lands.
	for u in _victims(kind):
		u.take_damage(damage, self)
		if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
			_credit_kill()
			continue
		if kick:
			# In front she kicks them away forward; whoever the backswing catches
			# behind her flies off backward.
			var rel: Vector3 = u.position - position
			var ahead: bool = rel.x * forward.x + rel.z * forward.z >= 0.0
			u.apply_lift(forward if ahead else -forward,
				Balance.GOLEM_KICK_PUSH, Balance.GOLEM_KICK_UP)
			continue
		var away: Vector3 = Vector3(u.position.x - position.x, 0.0,
			u.position.z - position.z)
		match Fireball.impact_outcome(randf(), Balance.GOLEM_LIFT_CHANCE,
				Balance.GOLEM_ROLL_CHANCE):
			Fireball.OUTCOME_LIFT:
				u.apply_lift(away, Balance.GOLEM_LIFT_PUSH, Balance.GOLEM_LIFT_UP)
			Fireball.OUTCOME_ROLL:
				if away.length_squared() < 0.000001:
					away = forward
				u.start_roll(away.normalized(), Balance.GOLEM_ROLL_DURATION,
					Balance.GOLEM_ROLL_SPEED)
	var struck_buildings: Dictionary = {}
	if building_manager != null:
		# duplicate() because a stage can level a construction site and mutate
		# the list.
		for b in building_manager.buildings.duplicate():
			if not is_instance_valid(b) or b.health <= 0:
				continue
			if b.tribe_id == tribe_id or not b.is_attackable():
				continue
			if _building_in_area(b, kind, forward):
				struck_buildings[b] = true
				_strike_building(b)
	return struck_buildings


## One attack's worth of damage on a building. A building the golem brings down
## counts as ONE kill, like a unit (user spec 2026-11-15).
func _strike_building(b) -> void:
	b.apply_destruction_stages(Balance.GOLEM_BUILDING_STAGES)
	if not is_instance_valid(b) or b.health <= 0:
		_credit_kill()


## Does the attack's area touch the building's footprint? Slam: the footprint
## comes within the radius of the impact point. Kick: centreline samples along
## the lane, each with the lane's half-width (like the fire ram's blast).
func _building_in_area(b, kind: StringName, forward: Vector3) -> bool:
	var size: float = reach_factor()
	if kind != ATTACK_KICK:
		var hit: Vector3 = position + forward * (SLAM_FORWARD * size)
		return b.footprint_distance_to(Vector2(hit.x, hit.z)) <= SLAM_RADIUS * size
	var along: float = -KICK_BACK * size + 0.5
	while along < KICK_LENGTH * size:
		var sample: Vector3 = position + forward * along
		if b.footprint_distance_to(Vector2(sample.x, sample.z)) <= KICK_HALF_WIDTH * size:
			return true
		along += 1.0
	return false


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _ready() -> void:
	_create_model()
	_refresh_flag_color()


## User-provided model (assets/models/units/golem.glb) when present: built
## MODEL_HEIGHT (4 m) tall — scaled here to Balance.GOLEM_HEIGHT —, front +Z,
## origin at the feet. Optional parts: an AnimationPlayer with the
## clips idle / walk / slam / kick / death, a MeshInstance3D "Flag" that takes
## the tribe colour, a Node3D "Arm" that swings on an attack (models without
## clips). Otherwise a blocky stone figure of the same size.
func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	root.scale = Vector3(MODEL_SCALE, MODEL_SCALE_Y, MODEL_SCALE)
	add_child(root)
	_model = root
	var custom: Node3D = AssetLibrary.instantiate_model("models/units/golem.glb")
	if custom != null:
		root.add_child(custom)
		_arm = custom.find_child("Arm", true, false) as Node3D
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_anim = custom.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_prepare_clips()
		_finish_model(root)
		return
	# Legs.
	for sx in [-0.45, 0.45]:
		_add_box(root, Vector3(0.6, 1.9, 0.7), Vector3(sx, 0.95, 0.0), C_STONE_DARK)
	# Torso (1.5 wide, 1.0 deep).
	_add_box(root, Vector3(1.5, 1.3, 1.0), Vector3(0.0, 2.5, 0.0), C_STONE)
	# Shoulders and head.
	_add_box(root, Vector3(1.8, 0.4, 0.9), Vector3(0.0, 3.25, 0.0), C_STONE_LIGHT)
	_add_box(root, Vector3(0.7, 0.7, 0.7), Vector3(0.0, 3.65, 0.1), C_STONE)
	# Arms under one pivot at shoulder height: they hang beside the torso and
	# swing forward/down on an attack (_tick_visual).
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(0.0, 3.1, 0.1)
	root.add_child(_arm)
	for sx in [-0.75, 0.75]:
		_add_box(_arm, Vector3(0.4, 1.7, 0.45), Vector3(sx, -0.85, 0.0), C_STONE_DARK)
		_add_box(_arm, Vector3(0.5, 0.5, 0.55), Vector3(sx, -1.9, 0.05), C_STONE)
	# Chest rune in the tribe colour (the "flag").
	_flag_mesh = _add_box(root, Vector3(0.6, 0.6, 0.1), Vector3(0.0, 2.6, 0.53), Color.WHITE)
	_flag_mesh.name = "Flag"
	_finish_model(root)


## Idle and walk loop; everything else plays once. Starts in idle.
func _prepare_clips() -> void:
	if _anim == null:
		return
	for clip in [CLIP_IDLE, CLIP_WALK]:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play_clip(CLIP_IDLE)


## Plays `clip` if the model has it. `restart` re-triggers a clip that is
## already running (two kicks in a row).
func _play_clip(clip: StringName, speed: float = 1.0, restart: bool = false) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if _clip == clip and not restart:
		_anim.speed_scale = speed
		return
	_clip = clip
	if restart:
		_anim.stop()
	_anim.play(clip, CLIP_BLEND)
	_anim.speed_scale = speed


func _add_box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = _mat(color)
	m.position = at
	parent.add_child(m)
	return m


## Same rig as CrewedVehicle._finish_model: no real-time shadows on units, a
## blob shadow quad instead.
func _finish_model(root: Node3D) -> void:
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blob: MeshInstance3D = MeshInstance3D.new()
	blob.name = "BlobShadow"
	# Child of the scaled model root, so its size is given in model units.
	blob.mesh = UnitRenderer.make_blob_mesh(
		Vector2(BODY_HALF_WIDTH * 2.6, BODY_HALF_DEPTH * 2.8) / MODEL_SCALE)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.04 / MODEL_SCALE
	root.add_child(blob)


func _mat(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


func _refresh_flag_color() -> void:
	if _flag_mesh == null:
		return
	var mat: StandardMaterial3D = _mat(TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()])
	mat.emission_enabled = true
	mat.emission = TRIBE_COLORS[tribe_id % TRIBE_COLORS.size()]
	mat.emission_energy_multiplier = 0.6
	_flag_mesh.material_override = mat


## Rotates the model with the facing, drives its clips (or swings the
## placeholder arms), lets it rise on the summoning and sinks the crumbled wreck
## into the ground (the base corpse timer removes it).
func _tick_visual(delta: float) -> void:
	if not is_inside_tree():
		return
	if state == State.DEAD:
		if _dead_time == 0.0:
			_play_clip(CLIP_DEATH, 1.0, true)
		_dead_time += delta
		# With a collapse clip the body falls first and sinks afterwards.
		if _dead_time >= SINK_DELAY or _clip != CLIP_DEATH:
			position.y -= SINK_SPEED * delta
		return
	if facing.length_squared() > 0.000001:
		rotation.y = atan2(facing.x, facing.z)
	# A level-up lets the figure grow over about a second.
	if _model != null and not is_equal_approx(_shown_size, size_factor()):
		_shown_size = move_toward(_shown_size, size_factor(), delta * GROW_SPEED)
		_model.scale = Vector3(MODEL_SCALE, MODEL_SCALE_Y, MODEL_SCALE) * _shown_size
	if _rise < 1.0 and _model != null:
		_rise = minf(_rise + delta / RISE_TIME, 1.0)
		var left: float = 1.0 - _rise
		_model.position.y = -RISE_DEPTH * left * left
	var ground_speed: float = 0.0
	if _last_pos != Vector3.INF and delta > 0.0:
		ground_speed = Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / delta
	_last_pos = position
	if _anim != null:
		# An attack clip plays out; afterwards walk or idle by the real speed.
		var attacking: bool = (_clip == ATTACK_SLAM or _clip == ATTACK_KICK
			or _clip == ATTACK_SWAT) and _anim.is_playing()
		if not attacking:
			if ground_speed > WALK_THRESHOLD:
				# A bigger body covers more ground per stride.
				_play_clip(CLIP_WALK, ground_speed / (WALK_CLIP_SPEED * _shown_size))
			else:
				_play_clip(CLIP_IDLE)
	if _arm != null and _arm_anim < 1.0:
		_arm_anim = minf(_arm_anim + delta * 2.0, 1.0)
		# Raise, then slam down and settle: a half sine over the swing.
		_arm.rotation.x = -sin(_arm_anim * PI) * 1.3
