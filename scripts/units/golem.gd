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
##   SPRUNG (stomp, 2026-11-16) — sie springt auf der Stelle und landet auf beiden
##     Fuessen: Schaden rundherum um sie selbst (Trampelradius mal 5/3, doppelter
##     Trampelschaden, doppelt so viele Ziele wie das Trampeln). Nur aus dem Stand; nach der
##     Landung ist sie GEBUECKT und bleibt es oder richtet sich sofort wieder auf
##     (s. Balance.GOLEM_STOMP_*, _tick_stance).
## Wahl (_choose_attack, seit 2026-11-16 nach erwartetem Schaden je Sekunde; frueher: stehen mindestens 3 Feinde in der
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
## STUFEN (Nutzervorgabe 2026-11-15): nach GOLEM_LEVEL_KILLS Kills steigt er
## je eine Stufe auf (0 .. GOLEM_MAX_LEVEL). Je Stufe +20 s Lebenszeit, +3 Leben/s
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
## brennt ohne Panik. KONTER: Feuer macht vollen Schaden, der Blitz doppelten, ein
## Katapult-Volltreffer mehr, je groesser er ist — nur der ausgewachsene Golem
## (100 m) ist dagegen gehaertet. Je Schadenstick trifft er hoechstens
## max_targets() Ziele.

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
## Three hand hits on the ground (left, right, left) — the slam's longer variant.
const ATTACK_DRUM: StringName = &"drum"
## The jump on the spot (2026-11-16): she lands on both feet and the damage falls
## all around her. Struck only from standing — and it leaves her CROUCHED.
const ATTACK_STOMP: StringName = &"stomp"
## Extra clips the model may bring for the same attacks: the kick with the other
## leg, and the level strike at an airship hovering at chest height.
const CLIP_KICK_LEFT: StringName = &"kick_l"
const CLIP_SWIPE: StringName = &"swipe"
const ATTACK_CLIPS: Array[StringName] = [
	&"slam", &"kick", &"kick_l", &"swat", &"swipe", &"drum", &"slam_low", &"drum_low", &"stomp"]
## The two stances (see Balance.GOLEM_STANCE_*): standing kicks, swats and walks;
## crouched slams and drums — faster, but rooted.
const STANCE_STAND: int = 0
const STANCE_CROUCH: int = 1
## Clips of the crouched stance: rest pose, bending down, getting up, and the two
## ground attacks starting and ending in the crouch.
const CLIP_CROUCH_IDLE: StringName = &"crouch_idle"
const CLIP_CROUCH_DOWN: StringName = &"crouch_down"
const CLIP_CROUCH_UP: StringName = &"crouch_up"
const CLIP_SLAM_LOW: StringName = &"slam_low"
const CLIP_DRUM_LOW: StringName = &"drum_low"
## Length of the stance-switch clips at speed 1 (golem_bewegung.mjs).
const STANCE_CLIP_LENGTH: float = 0.45
## The third stance (2026-11-17): SITTING, for every golem from GOLEM_SIT_MIN_HEIGHT.
## It is reached only through the crouch (stand -> crouch -> sit, and back the same
## way, ending standing) and ONLY BY HAND (sit_down / stand_up: key V, the sidebar
## button). From the first step down to the last step up she is sit-locked
## (is_sit_locked): no orders, no walking, no attacks. The numbers keep their order:
## a stance change always goes one step along 0 - 1 - 2 (_begin_stance).
const STANCE_SIT: int = 2
const CLIP_SIT_IDLE: StringName = &"sit_idle"
const CLIP_SIT_DOWN: StringName = &"sit_down"
const CLIP_SIT_UP: StringName = &"sit_up"
## Length of the sit-down / sit-up clips at speed 1 (golem_bewegung_niedlich_sitzen.mjs).
const SIT_CLIP_LENGTH: float = 1.5
## Death while seated or in the crab stand (clip sit_death, 1,4 s, keeps its end pose).
const CLIP_SIT_DEATH: StringName = &"sit_death"
## CRAB WALK (user spec 2026-11-18): with the switch "stationary" off a seated golem lifts her
## bottom (crab_up), crawls feet first on all fours (crab_idle / crab_walk, loops, blended like
## idle / walk) and sits down again (crab_down). She stays in STANCE_SIT the whole time; _crab
## tells the phase. Clip lengths at speed 1 (golem_bewegung_niedlich_krebs.mjs).
const CRAB_NONE: int = 0
const CRAB_UP: int = 1
const CRAB_STAND: int = 2
const CRAB_DOWN: int = 3
const CLIP_CRAB_UP: StringName = &"crab_up"
const CLIP_CRAB_IDLE: StringName = &"crab_idle"
const CLIP_CRAB_WALK: StringName = &"crab_walk"
const CLIP_CRAB_DOWN: StringName = &"crab_down"
## The airship strike in the crab stand (clip still to come; without it the strike lands unseen).
const CLIP_CRAB_SWAT: StringName = &"crab_swat"
const CRAB_CLIP_LENGTH: float = 0.6
## Ground covered by one loop of crab_walk at 4 m (metres of the model, measured on the export).
const CRAB_CLIP_STRIDE: float = 1.029
## How often she looks for a goal while seated (airship, focus) and re-aims a crawl at a moving target.
const CRAB_THINK: float = 0.25
const CRAB_REPATH: float = 1.0
## Failed paths toward a target before she gives up and sits down.
const CRAB_MAX_FAILS: int = 3
## The stretch she does when she grows: clip name and its length at speed 1.
const CLIP_GROW: StringName = &"grow"
const GROW_CLIP_LENGTH: float = 1.0
## Growing on the seat: the stretched legs strike this share into the stretch (the clip
## sit_grow has them stretched out from 0,42 s of its 1,0 s).
const GROW_STRIKE_SHARE: float = 0.43
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
const CLIP_LENGTH: Dictionary = {&"slam": 0.9, &"kick": 1.2, &"swat": 1.2, &"drum": 1.7, &"stomp": 1.0}   # slam_low / drum_low
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
## Outer radius of the selection ring mesh (SelectionRingRenderer) at scale 1.
const SELECTION_RING_MESH_RADIUS: float = 0.34
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

## She had to walk to her target (or came at it out of a march): she closes in to
## strike_distance() instead of stopping at the edge of her reach (user spec
## 2026-11-17). False while she fights from where she stands.
var _closing_in: bool = false

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
## The building an explicit ORDER sent her against (order_attack_building) — see
## has_ordered_building().
var _ordered_building = null
var _chase_timer: float = 0.0
## True only while the chase issues its own move order (see order_move).
var _own_order: bool = false

var _model: Node3D = null
var _arm: Node3D = null
var _flag_mesh: MeshInstance3D = null
var _anim: AnimationPlayer = null
var _clip: StringName = &""
## The body's real direction: it follows `facing` at turn_rate() (see
## _slew_heading). Unset (ZERO) until the first tick — then `facing` counts.
var _heading: Vector3 = Vector3.ZERO
## >= 0 while the attack choice is weighed as if already turned: the turn time
## it would really take (see _stomp_while_turning, turn_time_needed).
var _assumed_turn_time: float = -1.0
## The next kick uses the left leg (alternates with every kick) — still used for the low
## strike at an airship.
var _kick_left: bool = false
## The leg of the next kick on the ground (user spec 2026-11-18): +1 right (clip kick), -1 left
## (kick_l). Each leg has its own lane; the choice takes the leg that strikes more
## (_pick_kick_leg). _last_kick_side: the leg of the last kick (ties alternate).
## _kick_leg_locked: the next wind-up keeps kick_side as it is (felling trees).
var kick_side: float = 1.0
var _last_kick_side: float = -1.0
var _kick_leg_locked: bool = false
## Which of the drum's hits lands next (0-based) while a drum is wound up.
var _pending_hit: int = 0
## Stance right now (STANCE_STAND / STANCE_CROUCH), the one a running switch
## leads to, the seconds that switch still takes (0 = none running), and how long
## she has been in the current stance (starts "long ago": the first switch is free).
var stance: int = STANCE_STAND
var _stance_target: int = STANCE_STAND
var _stance_switch: float = 0.0
var _stance_age: float = 1000.0
## She has been asked to sit (sit_down) and nothing has called her up since.
var _wants_sit: bool = false
## She has been called up from the sit (stand_up) and is not standing yet.
var _leaving_sit: bool = false
## Ground her feet still have to cover toward the free seat (find_seat) while she
## bends down.
var _sit_shift: Vector3 = Vector3.ZERO
## While seated: the middle of the seat (her logic position), its long axis (her
## heading), its half extents (x = across, y = along) — fixed when she sat down —,
## the units (and enemy vehicles) under it then, and the time to the next tick.
var _seat_center: Vector3 = Vector3.INF
var _seat_fwd: Vector3 = Vector3(0, 0, 1)
var _seat_half: Vector2 = Vector2.ZERO
var _sit_victims: Array = []
var _sit_damage_timer: float = 0.0
## While seated she never lies lower than this (the ground under feet, seat and
## hands when she sat down, see _seat_floor_height).
var _seat_floor_y: float = -INF
## The levelling under her while she sits down (TerrainMorph), if any.
var _sit_level_morph = null
## While seated (user spec 2026-11-18): the height the ground under her body evens out to (her
## feet's when she sat down; INF = none), the timer and the running step of that gradual levelling.
var _sit_level_y: float = INF
var _sit_level_timer: float = 0.0
var _sit_level_step = null
## The attacks of her limbs while she sits (GolemSitCombat) and the animation layers
## for them (GolemSitAnim; only with a model that has the clips).
var sit_combat: GolemSitCombat = null
## Off = no sit attacks (tests of the sit damage switch them off).
var sit_attacks_enabled: bool = true
var _sit_anim: GolemSitAnim = null
## Switch "stationary" (user spec 2026-11-18, sidebar): on = seated she never moves (as before);
## off = she crab-walks for orders and of her own accord. A fresh golem is stationary.
var sit_stationary: bool = true
## Crab walk: phase (CRAB_*), seconds left of crab_up / crab_down, the goal of a move order
## (INF = none), the unit / building / airship she crawls toward, the target the player ordered
## (it stays her focus after she sat down), the spot correction while she sits down, timers.
var _crab: int = CRAB_NONE
var _crab_time: float = 0.0
var _crab_goal: Vector3 = Vector3.INF
var _crab_target: Object = null
var _crab_focus: Object = null
var _crab_shift: Vector3 = Vector3.ZERO
var _crab_think: float = 0.0
var _crab_repath: float = 0.0
var _crab_aimed: Vector3 = Vector3.INF
var _crab_fails: int = 0
var _crab_wait: float = 0.0
## Enemy buildings she sat down on (from the crab walk): they take part of the sit damage.
var _sit_buildings: Array = []
## The airship strike in the crab stand: the ship it is wound up at, seconds to the impact,
## seconds to the next strike.
var _crab_air_ship: Airship = null
var _crab_air_time: float = 0.0
var _crab_air_cooldown: float = 0.0
## The stomp has landed and its clip is still settling into the crouch: once it
## has played out she decides whether to stay down or get up again (_tick_stance).
var _stomp_landed: bool = false
## Off = she never jumps of her own accord (the tests of the plain stance change
## switch the stomp off; `_wind_up(ATTACK_STOMP)` still works).
var stomp_enabled: bool = true
## Tests: the body height the knockback chances are read at (-1 = the real one).
var knock_height_override: float = -1.0
## She has grown and still owes the stretch (it starts once the running attack
## animation is through), the seconds a running stretch still takes, and the
## seconds the current attack clip still plays.
var _stretch_queued: bool = false
## Seconds the seated stretch (sit_grow) still runs.
var _sit_stretch_left: float = 0.0
var _stretch_time: float = 0.0
var _attack_anim_left: float = 0.0
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


## The radius she picks her fights in grows with her body (user report
## 2026-11-15: the grown golem hardly attacked anything on her own any more —
## the plain 8 m lay INSIDE her own reach by then). Capped, or the 100-m giant
## would see the whole map.
func aggro_radius() -> float:
	return minf(AGGRO_RADIUS * size_factor(), Balance.GOLEM_AGGRO_MAX)


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
	var pose: String = stance_name()
	return "Stufe %d/%d%s\nGröße: %.1f m   Leben: %d/%d\nLebenszeit: %s   Kills: %d   Haltung: %s" % [
		level, Balance.GOLEM_MAX_LEVEL, next, height_m(), health, max_health, life, kills, pose]


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


## Fire is a counter again (user spec 2026-11-15): the golem burns like every
## unit (still without panic). Only the full-grown one is fire-resistant.
func burn_damage_per_second() -> float:
	return Balance.GOLEM_BURN_DPS if is_full_size() else super.burn_damage_per_second()


## Lightning strikes the golem twice as hard — except the full-grown one.
func lightning_damage(base: int) -> int:
	return base if is_full_size() else int(round(float(base) * Balance.GOLEM_LIGHTNING_MULT))


## A catapult hits his BODY (see SiegeShot._shockwave) — in the crab stand all of it.
func body_hit_radius() -> float:
	return collision_radius()


## A catapult's DIRECT hit — the stone lands inside his body circle — hurts more
## the bigger he is: from the plain shock damage at the starting size linearly up
## to GOLEM_SIEGE_DAMAGE_MAX just below 100 m. The full-grown golem takes at most
## GOLEM_SIEGE_DAMAGE_FULL_SIZE. A stone that only grazes him with its shock ring
## does the plain damage.
func siege_shock_damage(base: int, dist: float) -> int:
	if dist > maxf(trample_radius(), 1.0):
		return base
	var scaled: int = siege_damage_for_height(base, height_m())
	return mini(scaled, Balance.GOLEM_SIEGE_DAMAGE_FULL_SIZE) if is_full_size() else scaled


static func siege_damage_for_height(base: int, height: float) -> int:
	var k: float = clampf((height - Balance.GOLEM_HEIGHT)
		/ (Balance.GOLEM_MAX_HEIGHT - Balance.GOLEM_HEIGHT), 0.0, 1.0)
	return int(round(lerpf(float(base), float(Balance.GOLEM_SIEGE_DAMAGE_MAX), k)))


## True once the body has reached GOLEM_MAX_HEIGHT (no growth step left).
func is_full_size() -> bool:
	return level >= Balance.GOLEM_MAX_LEVEL and growth_steps >= max_growth_steps()


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


## Bugfix 2026-11-16: golems walking along the shore died without a fight. A
## shore cell counts as walkable while the mean of its corners is above the sea,
## so a point on it can lie at the waterline; any terrain change nearby then
## drowned whoever stood there - and the giant's own levelling is such a change,
## at his feet, every few seconds, lowering the shore towards the waterline.
## So the golem drowns only when the ground under him lies GOLEM_DROWN_DEPTH
## below the waterline - deeper than any walkable cell can dip (mean of the
## corners above the sea, at most MAX_SLOPE apart: never below SEA_LEVEL - 0.75).
## Wading along the shore is safe; sinking the land under him still kills him.
## (The giant's levelling also leaves the shore alone now: _next_to_water.)
func is_flooded_on(td: TerrainData) -> bool:
	if crosses_water():
		return false   # from 30 m on she wades through any water (user spec 2026-11-18)
	return td.get_height(position.x, position.z) \
		<= TerrainData.SEA_LEVEL - Balance.GOLEM_DROWN_DEPTH


## From GOLEM_WATER_WALK_HEIGHT on she does not drown and walks through water (user spec
## 2026-11-18): on the sea bed, straight lines only (giant_line_clear with water allowed).
func crosses_water() -> bool:
	return height_m() >= Balance.GOLEM_WATER_WALK_HEIGHT - 0.0001


## Whole hull is clickable; the selection ring encloses the body.
func pick_size_m() -> Vector2:
	return Vector2(body_half_width() * 2.0, Balance.GOLEM_HEIGHT) * size_factor()


func selection_ring_scale() -> float:
	return 2.43 * size_factor()   # ring radius 0,83 m around the 1,55-m-wide body


## Radius of the selection ring (the ring mesh is 0,34 m at scale 1).
func selection_ring_radius() -> float:
	return SELECTION_RING_MESH_RADIUS * selection_ring_scale()


## Others strike her as a big object (user spec 2026-11-16): they are in range
## once within their range of a circle half the selection ring's radius
## (GOLEM_TARGET_RADIUS_SHARE) — they attack from further away instead of
## crowding right under her. The giant levels the ground only in this circle.
func target_radius() -> float:
	var r: float = selection_ring_radius() * Balance.GOLEM_TARGET_RADIUS_SHARE
	if is_crabbing():
		# In the crab stand her whole body is the target (user spec 2026-11-18).
		return maxf(r * Balance.GOLEM_SIT_TARGET_RADIUS_FACTOR, crab_body_radius())
	return r * Balance.GOLEM_SIT_TARGET_RADIUS_FACTOR if _seat_center != Vector3.INF else r


# --- Lifetime -----------------------------------------------------------------------

func tick(delta: float) -> void:
	super.tick(delta)
	if state != State.DEAD:
		_slew_heading(delta)
		_tick_stance(delta)
		_tick_crab(delta)
		_tick_stretch(delta)
	_tick_pending_attack(delta)
	if state != State.DEAD and not doomed and not garrison_housed:
		_tick_sit_damage(delta)
		_tick_sit_combat(delta)
		_tick_air_strike(delta)
		_tick_air_chase(delta)
		_tick_level_regen(delta)
		_tick_trample(delta)
		_tick_flatten(delta)
		_tick_sit_levelling(delta)
		_tick_golem_separation(delta)   # after the trampling: being pushed is not walking
		# From the final-bonus level on the lifetime no longer runs out (user spec).
		if has_lifetime():
			life_left -= delta
			if life_left <= 0.0:
				_crumble()
	if state == State.IDLE:
		_closing_in = false
	if _seat_center != Vector3.INF and position.y < _seat_floor_y:
		position.y = _seat_floor_y
		_sync_soa_pos()
	_tick_pos = position
	_tick_visual(delta)


# --- Levels -------------------------------------------------------------------------

## Kills needed for `p_level` in total: the sum of GOLEM_LEVEL_KILLS up to it
## (5, 11, 18, 25, 33, 42 and 87 for the giant).
static func kills_for_level(p_level: int) -> int:
	var kills_needed: int = 0
	for i in range(mini(p_level, Balance.GOLEM_LEVEL_KILLS.size())):
		kills_needed += Balance.GOLEM_LEVEL_KILLS[i]
	return kills_needed


## Most targets ONE damage tick of the golem strikes (slam, kick; trampling: per
## second): GOLEM_MAX_TARGETS by level, plus one for every
## GOLEM_GROWTH_STEPS_PER_TARGET growth steps beyond level 7.
static func max_targets_for(p_level: int, p_growth_steps: int) -> int:
	var table: Array[int] = Balance.GOLEM_MAX_TARGETS
	return table[clampi(p_level, 0, table.size() - 1)] \
		+ p_growth_steps / Balance.GOLEM_GROWTH_STEPS_PER_TARGET


func max_targets() -> int:
	return max_targets_for(level, growth_steps)


## Share of the base target count (max_targets) the attack `kind` strikes, in
## per cent: slam (and trampling) the base, kick 40 % fewer, drum a quarter more,
## stomp twice as many — twice the trampling's (user spec 2026-11-16).
static func target_percent(kind: StringName) -> int:
	if kind == ATTACK_KICK:
		return Balance.GOLEM_TARGET_PERCENT_KICK
	if kind == ATTACK_DRUM:
		return Balance.GOLEM_TARGET_PERCENT_DRUM
	if kind == ATTACK_STOMP:
		return Balance.GOLEM_TARGET_PERCENT_STOMP
	return 100


## The cap for ONE landing of the attack `kind`: its share of the base count,
## rounded DOWN, at least one.
func max_targets_of(kind: StringName) -> int:
	return maxi(max_targets() * target_percent(kind) / 100, 1)


## Permanent healing per second right now: GOLEM_LEVEL_REGEN per level, and
## GOLEM_FULL_SIZE_REGEN on top for the full-grown golem.
func regen_per_second() -> float:
	var regen: float = Balance.GOLEM_LEVEL_REGEN * float(level)
	return regen + Balance.GOLEM_FULL_SIZE_REGEN if is_full_size() else regen


## Health ceiling right now: GOLEM_MAX_HP_CAP, plus GOLEM_GROWTH_MAX_HP for every
## growth step beyond level 7.
func max_health_cap() -> int:
	return Balance.GOLEM_MAX_HP_CAP + Balance.GOLEM_GROWTH_MAX_HP * growth_steps


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
	return speed_for_size(size_factor_for(p_level))


## Ground speed of ANY golem of this size (user spec 2026-11-17: the same size
## walks equally fast): the root of the size up to the giant's (level 7), beyond
## it only GOLEM_GROWTH_SPEED_EXPONENT of the growth.
static func speed_for_size(s: float) -> float:
	var giant: float = size_factor_for(Balance.GOLEM_MAX_LEVEL)
	var v: float = Balance.GOLEM_SPEED * sqrt(minf(s, giant))
	if s > giant:
		v *= pow(s / giant, Balance.GOLEM_GROWTH_SPEED_EXPONENT)
	return v


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


## Factor of the strike areas from the growth beyond level 7 (1 below that): the
## body's growth since then to GOLEM_GROWTH_AREA_EXPONENT — far slower.
func growth_area_factor() -> float:
	if growth_steps <= 0:
		return 1.0
	return pow(size_factor() / size_factor_for(Balance.GOLEM_MAX_LEVEL),
		Balance.GOLEM_GROWTH_AREA_EXPONENT)


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


## From GOLEM_BODY_SCALE_HEIGHT on, areas and reach grow exactly with the body (user spec
## 2026-11-18, all three golems): the normal golem's values at its first seated size, times
## her body width over its width there. Below, each golem's own (slower) growth.
func body_scaled() -> bool:
	return height_m() >= Balance.GOLEM_BODY_SCALE_HEIGHT - 0.0001


## Her body width (model scale x size) over the normal golem's at its first seated size.
func body_anchor_ratio() -> float:
	return model_scale().x * size_factor() / Balance.GOLEM_BODY_ANCHOR_WIDTH


## Scale of the SIZE of both strike areas at the current level (the slam's
## radius, the lane's width) — the slow one, 10 % a level. Where the areas lie and
## how far she reaches follows limb_factor() since 2026-11-16. From 30 m: with the body.
func reach_factor() -> float:
	if body_scaled():
		return Balance.GOLEM_BODY_REACH_FACTOR_AT_ANCHOR * body_anchor_ratio()
	return _base_reach_factor()


func _base_reach_factor() -> float:
	return reach_factor_for(level) * growth_area_factor()


## Scale of the slam's (and the drum's) circle: the slow area growth up to level
## 7, and beyond it an even growth per step up to GOLEM_SLAM_RADIUS_AT_MAX at
## 100 m — stronger than the 0,75 percent the other areas take there.
func slam_scale() -> float:
	if body_scaled():
		return Balance.GOLEM_BODY_SLAM_SCALE_AT_ANCHOR * body_anchor_ratio()
	return _base_slam_scale()


func _base_slam_scale() -> float:
	var base: float = reach_factor_for(level)
	var steps: int = max_growth_steps()
	if growth_steps <= 0 or steps <= 0:
		return base
	var at_max: float = Balance.GOLEM_SLAM_RADIUS_AT_MAX / SLAM_RADIUS
	return base * pow(at_max / reach_factor_for(Balance.GOLEM_MAX_LEVEL),
		float(growth_steps) / float(steps))


## Radius of the slam's circle right now (metres).
func slam_radius() -> float:
	return SLAM_RADIUS * slam_scale()


## Radius of the circle around the hands for the ground attack `kind`: the drum's
## is GOLEM_DRUM_RADIUS_FACTOR larger than the slam's (user spec 2026-11-16).
func ground_radius(kind: StringName) -> float:
	return slam_radius() * _ground_factor(kind)


static func _ground_factor(kind: StringName) -> float:
	return Balance.GOLEM_DRUM_RADIUS_FACTOR if kind == ATTACK_DRUM else 1.0


## Exponent of the limb factor: chosen so that at GOLEM_LIMB_ANCHOR_HEIGHT (the
## old 100 m) the limbs are GOLEM_LIMB_SHARE_AT_MAX of what a body-proportional
## growth would give.
static func limb_exponent() -> float:
	return 1.0 + log(Balance.GOLEM_LIMB_SHARE_AT_MAX) / log(limb_anchor_size())


## Size factor at GOLEM_LIMB_ANCHOR_HEIGHT (user spec 2026-11-17: the limbs keep
## their curve although the golem stops at 80 m — levels 1-6 stay unchanged).
static func limb_anchor_size() -> float:
	return Balance.GOLEM_LIMB_ANCHOR_HEIGHT / Balance.GOLEM_HEIGHT


## How much longer her arms and legs are than a fresh golem's: the size factor,
## damped (size ^ 0,83), and its GAIN over 1 raised by GOLEM_LIMB_GROWTH_BONUS —
## level 6: 2,63, level 7: 3,73, 100 m: 13,9. Scales the reach, the length of the
## kick's lane and how far ahead the hands come down.
func limb_factor() -> float:
	if body_scaled():
		return Balance.GOLEM_BODY_LIMB_FACTOR_AT_ANCHOR * body_anchor_ratio()
	return _base_limb_factor()


func _base_limb_factor() -> float:
	return limb_factor_for(size_factor())


static func limb_factor_for(size: float) -> float:
	return 1.0 + (pow(size, limb_exponent()) - 1.0) * Balance.GOLEM_LIMB_GROWTH_BONUS


## How much longer the kick's lane is than a fresh golem's: the limb factor's
## gain over 1, shortened so that at GOLEM_LIMB_ANCHOR_HEIGHT the lane is
## GOLEM_KICK_LENGTH_SHARE_AT_MAX of what the limbs alone would give.
func kick_limb_factor() -> float:
	if body_scaled():
		return Balance.GOLEM_BODY_KICK_LIMB_AT_ANCHOR * body_anchor_ratio()
	return 1.0 + (limb_factor() - 1.0) * kick_growth_share()


static func kick_growth_share() -> float:
	var top: float = limb_factor_for(limb_anchor_size())
	return (Balance.GOLEM_KICK_LENGTH_SHARE_AT_MAX * top - 1.0) / (top - 1.0)


## The distance at which she strikes — it grows with her limbs.
func reach() -> float:
	return REACH * limb_factor()


## How close she walks up when she has to walk to her target anyway (user spec
## 2026-11-17): until it lies well inside the slam's circle — the spot where the
## hands come down plus GOLEM_CLOSE_IN_SLAM_SHARE of the circle's radius —, never
## farther out than her reach. From a standstill she keeps striking at reach().
func strike_distance() -> float:
	return minf(reach(), SLAM_FORWARD * limb_factor()
		+ slam_radius() * Balance.GOLEM_CLOSE_IN_SLAM_SHARE)


## Flat damage bonus of the current level: GOLEM_LEVEL_DAMAGE per level — level 7
## too since 2026-11-17 (user spec; before it added none).
func level_damage_bonus() -> int:
	return Balance.GOLEM_LEVEL_DAMAGE * level


## Damage of an attack at the current level.
func attack_damage(kind: StringName) -> int:
	var base: int = Balance.GOLEM_KICK_DAMAGE if kind == ATTACK_KICK else Balance.GOLEM_SLAM_DAMAGE
	if kind == ATTACK_DRUM:
		# All three hits together: every hit's own damage, plus the flat level
		# bonus once for the whole attack.
		return Balance.GOLEM_DRUM_HITS.size() * _drum_own_hit_damage() + level_damage_bonus()
	if kind == ATTACK_STOMP:
		# From the size, like the trampling it doubles — no level bonus on top.
		return Balance.GOLEM_STOMP_TRAMPLE_MULT * trample_damage()
	return base + level_damage_bonus()


## What every single hit of the drum brings by itself: GOLEM_DRUM_HIT_DAMAGE,
## plus GOLEM_DRUM_LEVEL_DAMAGE_PER_HIT for every level (like the flat bonus).
func _drum_own_hit_damage() -> int:
	return Balance.GOLEM_DRUM_HIT_DAMAGE + Balance.GOLEM_DRUM_LEVEL_DAMAGE_PER_HIT * level


## Damage of ONE of the drum's hits: its own damage (14, +1 per level) plus its
## share of the flat level bonus (+5 per level for the whole attack, split over
## the hits; the last one takes the remainder).
func drum_hit_damage(hit: int) -> int:
	var hits: int = Balance.GOLEM_DRUM_HITS.size()
	var shared: int = level_damage_bonus()
	var each: int = shared / hits
	return _drum_own_hit_damage() + (shared - each * (hits - 1) if hit >= hits - 1 else each)


## Trample damage comes from the SIZE (user spec 2026-11-15): body height in
## metres / GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE, rounded, at least 1.
func trample_damage() -> int:
	return maxi(1, int(round(height_m() / Balance.GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE)))


## Body height in metres right now.
func height_m() -> float:
	return Balance.GOLEM_HEIGHT * size_factor()


## Radius around the golem's centre it tramples in: its body. It grows WITH the
## body, also beyond level 7 (user spec 2026-11-15 — until then it only took the
## slow area growth there and the 100-m giant trampled a 5-m circle).
func trample_radius() -> float:
	return body_half_width() * size_factor()


## Radius of the stomp around her own centre: the body circle and two thirds more.
func stomp_radius() -> float:
	return trample_radius() * Balance.GOLEM_STOMP_RADIUS_FACTOR


## 0 at the starting size, 1 at GOLEM_MAX_HEIGHT — linear in the body height.
## Drives everything that changes "slowly with the size": the attack cooldown,
## the turn rate, the catapult's bonus damage.
func growth_t() -> float:
	return clampf((height_m() - Balance.GOLEM_HEIGHT)
		/ (Balance.GOLEM_MAX_HEIGHT - Balance.GOLEM_HEIGHT), 0.0, 1.0)


func is_stretching() -> bool:
	return _stretch_time > 0.0


## How long the stretch takes at her size (user spec 2026-11-18): GOLEM_GROW_TIME at the starting size,
## slightly exponentially up to GOLEM_GROW_TIME_MAX at GOLEM_GROW_TIME_MAX_HEIGHT.
func grow_time() -> float:
	return Golem.grow_time_for(height_m())


static func grow_time_for(h: float) -> float:
	var t: float = clampf((h - Balance.GOLEM_HEIGHT) / (Balance.GOLEM_GROW_TIME_MAX_HEIGHT - Balance.GOLEM_HEIGHT), 0.0, 1.0)
	return Balance.GOLEM_GROW_TIME * pow(Balance.GOLEM_GROW_TIME_MAX / Balance.GOLEM_GROW_TIME, t)


## Seated: is the stretch running (sit_grow)? Then she neither strikes nor turns.
func sit_stretching() -> bool:
	return _sit_stretch_left > 0.0


## She grows (level-up or growth step): the stretch is owed.
func _queue_stretch() -> void:
	_stretch_queued = true


## The stretch of a growing golem (user spec 2026-11-16): it starts as soon as no
## attack is wound up and the last attack's animation has played out, takes
## GOLEM_GROW_TIME, and leaves her STANDING and free to strike at once (and to
## bend down again at once — the stance's minimum time does not count here).
func _tick_stretch(delta: float) -> void:
	_attack_anim_left = maxf(_attack_anim_left - delta, 0.0)
	if is_stretching():
		_stretch_time -= delta
		if _stretch_time <= 0.0:
			_stretch_time = 0.0
			_stance_age = 1000.0
		return
	if is_sit_locked():
		# Growing while seated (user spec 2026-11-17): she stays seated and stretches her legs
		# (sit_grow). On the way down or up it waits until she sits — and (user spec 2026-11-18)
		# it queues like the standing one: not before her wound-up attacks have landed and their
		# clips have played out. The growth itself (size, health) is there at once.
		_sit_stretch_left = maxf(_sit_stretch_left - delta, 0.0)
		if _stretch_queued and stance == STANCE_SIT and not is_switching_stance() and _sit_stretch_left <= 0.0 \
				and not _sit_layers_busy() and not is_crabbing():
			_stretch_queued = false
			var t: float = grow_time()
			_sit_stretch_left = t
			_play_sfx(&"golem_grow")
			if _sit_anim != null and _sit_anim.is_active():
				_sit_anim.fire(GolemSitAnim.LAYER_FULL, GolemSitAnim.CLIP_GROW, t)
			# The stretched legs strike like the kick, in both legs' lanes (user spec
			# 2026-11-17), when they are stretched out in the clip.
			if sit_combat == null:
				sit_combat = GolemSitCombat.new(self)
			sit_combat.grow_strike(t * GROW_STRIKE_SHARE)
		return
	if not _stretch_queued or _pending_attack != &"" or _attack_anim_left > 0.0 \
			or is_switching_stance():
		return
	_stretch_queued = false
	_stretch_time = grow_time()
	_stomp_landed = false   # the stretch gets her up by itself
	stance = STANCE_STAND
	_stance_target = STANCE_STAND
	_play_sfx(&"golem_grow")
	_play_clip(CLIP_GROW, GROW_CLIP_LENGTH / _stretch_time, true)


## Seated: is an attack wound up, or does a clip still play on her leg, arm or body layer?
func _sit_layers_busy() -> bool:
	if sit_combat != null and sit_combat.is_busy():
		return true
	if _sit_anim != null and _sit_anim.is_active():
		for layer in [GolemSitAnim.LAYER_LEGS, GolemSitAnim.LAYER_ARMS, GolemSitAnim.LAYER_FULL]:
			if _sit_anim.layer_running(layer):
				return true
	return false


## The stance an attack needs: the ground attacks are struck crouched,
## everything else standing.
static func stance_for(kind: StringName) -> int:
	return STANCE_CROUCH if kind == ATTACK_SLAM or kind == ATTACK_DRUM else STANCE_STAND


## KNOCKBACK BY SIZE (user spec 2026-11-16, see GOLEM_KNOCK_* in Balance): below
## GOLEM_KNOCK_MIN_HEIGHT nothing is thrown or rolled; from there each chance
## climbs `per_step` every `step_m` metres — the first step counts from exactly
## that height on — up to `cap`.
static func knock_chance(height: float, step_m: float, per_step: float, cap: float) -> float:
	if height < Balance.GOLEM_KNOCK_MIN_HEIGHT - 0.0001:
		return 0.0
	var steps: int = int(floor((height - Balance.GOLEM_KNOCK_MIN_HEIGHT) / step_m + 0.0001)) + 1
	return minf(per_step * float(steps), cap)


## Body height the knockback is read at (tests may pin it).
func knock_height() -> float:
	return knock_height_override if knock_height_override >= 0.0 else height_m()


## Chance that a survivor of the kick is thrown.
func kick_throw_chance() -> float:
	return knock_chance(knock_height(), Balance.GOLEM_KICK_THROW_STEP_M,
		Balance.GOLEM_KICK_THROW_PER_STEP, Balance.GOLEM_KICK_THROW_MAX)


## Chances that a survivor of the slam is whirled up / sent rolling.
func slam_lift_chance() -> float:
	return knock_chance(knock_height(), Balance.GOLEM_SLAM_LIFT_STEP_M,
		Balance.GOLEM_SLAM_LIFT_PER_STEP, Balance.GOLEM_SLAM_LIFT_MAX)


func slam_roll_chance() -> float:
	return knock_chance(knock_height(), Balance.GOLEM_SLAM_ROLL_STEP_M,
		Balance.GOLEM_SLAM_ROLL_PER_STEP, Balance.GOLEM_SLAM_ROLL_MAX)


## The drum never throws; its last hit sends survivors rolling with this chance.
func drum_roll_chance() -> float:
	return knock_chance(knock_height(), Balance.GOLEM_DRUM_ROLL_STEP_M,
		Balance.GOLEM_DRUM_ROLL_PER_STEP, Balance.GOLEM_DRUM_ROLL_MAX)


## The stance in words, for the sidebar panel.
func stance_name() -> String:
	if stance == STANCE_SIT:
		return "sitzend"
	return "gebückt" if stance == STANCE_CROUCH else "stehend"


## Big enough to sit (GOLEM_SIT_MIN_HEIGHT)?
func can_sit() -> bool:
	return height_m() >= Balance.GOLEM_SIT_MIN_HEIGHT - 0.0001


## The player asks her to sit (key V, sidebar). Whatever she was doing ends; she
## bends down — moving onto a free seat nearby on the way, if hers is taken —, sits
## and stays seated until stand_up(). Returns false when she will not: too small,
## already sitting / on her way, or no free seat (find_seat).
func sit_down() -> bool:
	if state == State.DEAD or doomed or garrison_housed or not can_sit() or is_sit_locked():
		return false
	var feet: Vector3 = find_seat()
	if feet == Vector3.INF:
		return false
	_on_sit_requested()
	_end_attack()
	_clear_building_target()
	_ordered_building = null
	_chase_ship = null
	waypoint_queue.clear()
	_pending_target = Vector3.INF
	_clear_path()
	_closing_in = false
	if state != State.IDLE:
		_set_state(State.IDLE)
	_sit_shift = Vector3(feet.x - position.x, 0.0, feet.z - position.z)
	_wants_sit = true
	return true


## Hook for subclasses: the sit request ends their own business (the Genesis
## golem's harvest).
func _on_sit_requested() -> void:
	pass


## The player calls her up: sit -> crouch -> stand, without the stance's waiting
## time; she stays sit-locked until she stands. Also cancels a sit still on its way
## down. Returns false when she was not sitting or on her way.
func stand_up() -> bool:
	if not _wants_sit:
		return false
	_wants_sit = false
	_sit_shift = Vector3.ZERO
	_leaving_sit = stance != STANCE_STAND or is_switching_stance()
	_crab_clear_goals()   # in the crab stand she sits down first (crab_down), then gets up
	_crab_focus = null
	return true


func is_sitting() -> bool:
	return stance == STANCE_SIT


## From the request to sit until she stands again: no orders, no walking, no
## attacks, not pushed by other golems (user spec 2026-11-17).
func is_sit_locked() -> bool:
	return _wants_sit or stance == STANCE_SIT or _leaving_sit


## Seated or on her way: she takes no orders — only stand_up() reaches her. Not stationary and
## seated (or in the crab stand) she takes move and attack orders: she crab-walks (user spec 2026-11-18).
func can_take_orders() -> bool:
	return super.can_take_orders() and not sit_refuses_orders()


## Sit-locked and no crab walk possible right now: move and attack orders do not reach her
## (TribeCommands, SelectionManager: rejected cue).
func sit_refuses_orders() -> bool:
	return is_sit_locked() and not crab_ready()


## May she crab-walk now? Not stationary, seated for good (not on her way down or up) — or
## already in the crab stand.
func crab_ready() -> bool:
	return not sit_stationary and _wants_sit and not _leaving_sit and stance == STANCE_SIT \
		and not is_switching_stance() and state != State.DEAD and not doomed


## Seconds sitting down / getting up from the sit takes: GOLEM_SIT_TIME at
## GOLEM_SIT_REF_HEIGHT, with the root of the height, no cap (user spec 2026-11-17).
func sit_switch_time() -> float:
	return Balance.GOLEM_SIT_TIME * sqrt(height_m() / Balance.GOLEM_SIT_REF_HEIGHT)


## How far behind her feet the middle of the seat lies at her size (metres).
func seat_back_m() -> float:
	return Balance.GOLEM_SIT_SEAT_BACK * model_scale().z * size_factor()


## Half extents of the seat at her size: x across, y along her heading.
func seat_half_extent() -> Vector2:
	return Vector2(Balance.GOLEM_SIT_SEAT_WIDTH * 0.5 * model_scale().x,
		Balance.GOLEM_SIT_SEAT_LENGTH * 0.5 * model_scale().z) * size_factor()


## Where her FEET have to stand for a free seat: her own spot, else a spot up to
## GOLEM_SIT_SEARCH_SHARE of her body radius aside (two rings of eight); INF = none.
func find_seat() -> Vector3:
	var fwd: Vector3 = heading()
	var back: float = seat_back_m()
	var half: Vector2 = seat_half_extent()
	var search: float = trample_radius() * Balance.GOLEM_SIT_SEARCH_SHARE
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for ring in [0.5, 1.0]:
		for k in range(8):
			offsets.append(Vector2.from_angle(float(k) * TAU / 8.0) * search * ring)
	for off in offsets:
		var feet: Vector3 = Vector3(position.x + off.x, position.y, position.z + off.y)
		if seat_free(feet - fwd * back, fwd, half) and sit_pose_ok(feet - fwd * back, fwd):
			return feet
	return Vector3.INF


## Where her feet and hands rest when she sits facing `fwd` with the middle of the seat at
## `seat` (clip sit_idle): left foot, right foot, left hand, right hand.
func sit_contacts(seat: Vector3, fwd: Vector3) -> Array[Vector3]:
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var sx: float = model_scale().x * size_factor()
	var sz: float = model_scale().z * size_factor()
	var feet: Vector3 = seat + fwd * seat_back_m()
	var foot: Vector3 = right * (Balance.GOLEM_SIT_FOOT_SIDE * sx)
	var hands: Vector3 = feet - fwd * (Balance.GOLEM_SIT_HAND_BACK * sz)
	var hand: Vector3 = right * (Balance.GOLEM_SIT_HAND_SIDE * sx)
	return [feet + foot, feet - foot, hands + hand, hands - hand]


## Can she sit like this (user spec 2026-11-18)? The seat and every foot and hand on ground (not the
## void), and from the middle of the seat to each of them no cliff she could not walk up
## (giant_line_clear: GOLEM_GIANT_STEP_SHARE of her height per metre). Water does not count.
func sit_pose_ok(seat: Vector3, fwd: Vector3) -> bool:
	if terrain_data == null:
		return true
	if not terrain_data.has_ground(seat.x, seat.z):
		return false
	var limit: float = giant_step_limit()
	for p in sit_contacts(seat, fwd):
		if not terrain_data.has_ground(p.x, p.z) or not giant_line_clear(terrain_data, seat, p, limit, true):
			return false
	return true


## Seated: may she face `fwd`? Her limbs on possible ground (sit_pose_ok). Buildings do not
## count here — only when she sits down (seat_free; user spec 2026-11-18).
func sit_heading_ok(fwd: Vector3) -> bool:
	return sit_pose_ok(position, fwd)


## Is the seat (middle, long axis, half extents) free: wholly inside the disc (water is
## fine since 2026-11-18 — she sits from 30 m on, and from there she wades), touching no
## building or construction site of any tribe?
func seat_free(center: Vector3, fwd: Vector3, half: Vector2) -> bool:
	if not seat_on_disc(center, fwd, half):
		return false
	if building_manager != null:
		var c: Vector2 = Vector2(center.x, center.z)
		var f: Vector2 = Vector2(fwd.x, fwd.z)
		for b in building_manager.buildings:
			if not is_instance_valid(b):
				continue
			var box: Rect2 = Rect2(Vector2(b.cell) * TerrainData.CELL_SIZE,
				Vector2(b.footprint) * TerrainData.CELL_SIZE)
			if seat_overlaps_box(c, f, half, box):
				return false
	return true


## Does the seat lie wholly on the disc (water is fine)? From the crab walk this is all the seat
## needs — she may sit down on buildings then (user spec 2026-11-18).
func seat_on_disc(center: Vector3, fwd: Vector3, half: Vector2) -> bool:
	if terrain_data == null:
		return true
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	for i in range(-2, 3):
		for j in range(-2, 3):
			var p: Vector3 = center + right * (half.x * float(i) / 2.0) + fwd * (half.y * float(j) / 2.0)
			if not terrain_data.has_ground(p.x, p.z):
				return false
	return true


## Does the seat rectangle (middle c, long axis fwd, half extents half: x
## across, y along) overlap or touch the axis-aligned box? Separating axes.
static func seat_overlaps_box(c: Vector2, fwd: Vector2, half: Vector2, box: Rect2) -> bool:
	var right: Vector2 = Vector2(fwd.y, -fwd.x)
	var bh: Vector2 = box.size * 0.5
	var d: Vector2 = box.get_center() - c
	if absf(d.x) > bh.x + absf(right.x) * half.x + absf(fwd.x) * half.y:
		return false
	if absf(d.y) > bh.y + absf(right.y) * half.x + absf(fwd.y) * half.y:
		return false
	if absf(d.dot(right)) > half.x + absf(right.x) * bh.x + absf(right.y) * bh.y:
		return false
	if absf(d.dot(fwd)) > half.y + absf(fwd.x) * bh.x + absf(fwd.y) * bh.y:
		return false
	return true


## Is the point p on the seat she sat down on (the rectangle fixed then)?
func on_seat(p: Vector3) -> bool:
	if _seat_center == Vector3.INF:
		return false
	var d: Vector3 = Vector3(p.x - _seat_center.x, 0.0, p.z - _seat_center.z)
	var right: Vector3 = Vector3(_seat_fwd.z, 0.0, -_seat_fwd.x)
	return absf(d.dot(right)) <= _seat_half.x and absf(d.dot(_seat_fwd)) <= _seat_half.y


## GOLEM_SIT_SEAT_LEAD before she touches down, her logic position moves from the
## feet onto the middle of the seat (the model is drawn that far forward again,
## _tick_visual — the figure does not jump; the selection ring does). The seat is
## fixed now, and she lies no lower than the ground under feet, seat and hands.
func _move_onto_seat() -> void:
	if _seat_center != Vector3.INF:
		return
	if _sit_shift != Vector3.ZERO:
		position += _sit_shift
		_sit_shift = Vector3.ZERO
		_snap_to_ground()
	_seat_fwd = heading()
	facing = _seat_fwd   # no slewing left over: seated she turns only on purpose
	_seat_half = seat_half_extent()
	_seat_floor_y = _seat_floor_height(position, _seat_fwd)
	position -= _seat_fwd * seat_back_m()
	_snap_to_ground()
	position.y = maxf(position.y, _seat_floor_y)
	_seat_center = position
	_after_seat_shift()


## The highest ground under the seated figure with her feet at `feet`: feet, seat,
## both hands (user spec 2026-11-17: she may lie higher, never lower).
func _seat_floor_height(feet: Vector3, fwd: Vector3) -> float:
	if terrain_data == null:
		return feet.y
	var s: float = model_scale().z * size_factor()
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var hand_back: Vector3 = fwd * (-Balance.GOLEM_SIT_HAND_BACK * s)
	var side: Vector3 = right * (Balance.GOLEM_SIT_HAND_SIDE * model_scale().x * size_factor())
	var h: float = terrain_data.get_height(feet.x, feet.z)
	for p in [feet - fwd * seat_back_m(), feet + hand_back + side, feet + hand_back - side]:
		h = maxf(h, terrain_data.get_height(p.x, p.z))
	return h


## Ground moved under her (TerrainMorph): seated, she never sinks below her seat level.
func settle_on_ground(h: float) -> void:
	position.y = maxf(h, _seat_floor_y) if _seat_center != Vector3.INF else h


## She sits down (sit_down step begins): the ground in her selection circle around the
## middle of the seat comes down to the height of her feet (never raised) over the time she takes
## (user spec 2026-11-18; until then the whole figure at once). The rest of her body
## follows while she sits (_tick_sit_levelling). Needs the terrain context.
func _start_sit_levelling(feet: Vector3 = Vector3.INF, duration: float = -1.0) -> void:
	_sit_level_y = INF
	if terrain_ctx == null or terrain_data == null or path_service == null:
		return
	if feet == Vector3.INF:
		feet = position + _sit_shift
	if duration < 0.0:
		duration = sit_switch_time() - Balance.GOLEM_SIT_SEAT_LEAD
	_sit_level_y = maxf(terrain_data.get_height(feet.x, feet.z),
		TerrainData.SEA_LEVEL + Balance.GOLEM_FLATTEN_ABOVE_WATER)
	_sit_level_timer = Balance.GOLEM_FLATTEN_INTERVAL
	var seat: Vector3 = feet - heading() * seat_back_m()
	var plan: Dictionary = sit_level_plan(terrain_data, seat, heading(), 0.0, 0.0, 0.0,
		_sit_level_y, Balance.GOLEM_FLATTEN_SLOPE,
		TerrainData.SEA_LEVEL + Balance.GOLEM_FLATTEN_ABOVE_WATER, _sit_blocked_cells(),
		INF, selection_ring_radius())
	if (plan.indices as PackedInt32Array).is_empty():
		return
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(terrain_ctx, plan, maxf(duration, 0.1))
	path_service.register_projectile(morph)
	_sit_level_morph = morph


## The height map that evens out the ground under a seated figure: every vertex in
## the rectangle from `front` ahead of `feet` to `back` behind them, `half_w` to each
## (since 2026-11-18 only LOWERED: what lies above `level` comes down, nothing is raised)
## side, goes to `level` (raised or lowered); around it a bank of at most `slope`
## metres per metre joins the old ground. Untouched: vertices on a `blocked` cell
## (buildings), the sea bed and the shore; nothing goes below `floor_height`. Plan
## format as flatten_plan.
##
## `max_step`: no vertex moves further than this (the gradual levelling while she sits).
## `circle_r` > 0: the region is the circle of that radius around `feet` instead of the
## rectangle (the selection circle when she sits down).
static func sit_level_plan(td: TerrainData, feet: Vector3, fwd: Vector3, front: float,
		back: float, half_w: float, level: float, slope: float, floor_height: float,
		blocked: Array[Rect2i] = [], max_step: float = INF, circle_r: float = -1.0) -> Dictionary:
	var cs: float = TerrainData.CELL_SIZE
	var empty: Dictionary = {"indices": PackedInt32Array(), "targets": PackedFloat32Array(),
		"rect": Rect2i()}
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	level = maxf(level, floor_height)
	var corners: Array = []
	if circle_r > 0.0:
		front = circle_r
		back = circle_r
		half_w = circle_r
	for a in [front, -back]:
		for b in [half_w, -half_w]:
			corners.append(feet + fwd * a + right * b)
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for c in corners:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
	# How far the bank reaches: the biggest step inside the rectangle, at the slope.
	var spread: float = 0.0
	for vz in range(maxi(int(floor(lo.y / cs)), 0), mini(int(ceil(hi.y / cs)), td.verts - 1) + 1):
		for vx in range(maxi(int(floor(lo.x / cs)), 0), mini(int(ceil(hi.x / cs)), td.verts - 1) + 1):
			spread = maxf(spread, absf(td.heights[vz * td.verts + vx] - level))
	var bank: float = spread / maxf(slope, 0.05) + cs
	var indices: PackedInt32Array = PackedInt32Array()
	var targets: PackedFloat32Array = PackedFloat32Array()
	var min_v: Vector2i = Vector2i(td.verts, td.verts)
	var max_v: Vector2i = Vector2i(-1, -1)
	for vz in range(maxi(int(floor((lo.y - bank) / cs)), 0), mini(int(ceil((hi.y + bank) / cs)), td.verts - 1) + 1):
		for vx in range(maxi(int(floor((lo.x - bank) / cs)), 0), mini(int(ceil((hi.x + bank) / cs)), td.verts - 1) + 1):
			var idx: int = vz * td.verts + vx
			var h: float = td.heights[idx]
			if h <= floor_height or _next_to_water(td, vx, vz):
				continue   # sea bed and shore stay
			var on_building: bool = false
			for r in blocked:
				if r.has_point(Vector2i(vx, vz)) or r.has_point(Vector2i(vx - 1, vz - 1)):
					on_building = true
					break
			if on_building:
				continue
			var d: Vector3 = Vector3(float(vx) * cs - feet.x, 0.0, float(vz) * cs - feet.z)
			var along: float = d.dot(fwd)
			var outside: float
			if circle_r > 0.0:
				outside = maxf(Vector2(d.x, d.z).length() - circle_r, 0.0)
			else:
				var dx: float = maxf(absf(d.dot(right)) - half_w, 0.0)
				var dz: float = maxf(maxf(along - front, -back - along), 0.0)
				outside = sqrt(dx * dx + dz * dz)
			var dev: float = outside * slope
			# Only lowered, never raised (user spec 2026-11-18): ground below her feet stays as it is.
			var target: float = minf(h, level + dev)
			target = maxf(target, minf(h, floor_height + 0.0))
			target = maxf(target, h - max_step)
			if absf(target - h) < 0.01:
				continue
			indices.append(idx)
			targets.append(target)
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


## Building footprints (with a cell of margin) the levelling under her leaves alone.
func _sit_blocked_cells() -> Array[Rect2i]:
	var blocked: Array[Rect2i] = []
	if building_manager != null:
		for b in building_manager.buildings:
			if is_instance_valid(b):
				blocked.append(b.footprint_rect().grow(1))
	return blocked


## While she sits (user spec 2026-11-18): the ground under her whole body — the rectangle of
## the seated figure as she faces NOW (turning, it turns with her) — evens out toward the height
## of her feet when she sat down, every GOLEM_FLATTEN_INTERVAL at most GOLEM_FLATTEN_RATE metres
## a second — only lowered, lower ground stays. One step at a time.
func _tick_sit_levelling(delta: float) -> void:
	if stance != STANCE_SIT or is_switching_stance() or _seat_center == Vector3.INF or _sit_level_y == INF \
			or is_crabbing():
		return
	if terrain_ctx == null or terrain_data == null or path_service == null:
		return
	_sit_level_timer -= delta
	if _sit_level_timer > 0.0:
		return
	_sit_level_timer = Balance.GOLEM_FLATTEN_INTERVAL
	if _sit_level_step != null and is_instance_valid(_sit_level_step) and not _sit_level_step.done:
		return
	_sit_level_step = null
	var fwd: Vector3 = heading()
	var feet: Vector3 = position + fwd * seat_back_m()   # seated, her position is the middle of the seat
	# The ground under feet, seat and hands has moved (or she has turned): she lies on what is
	# there now — never lower than it, but no longer on a bump that has come down.
	_seat_floor_y = _seat_floor_height(feet, fwd)
	settle_on_ground(terrain_data.get_height(position.x, position.z))
	var s: Vector2 = Vector2(model_scale().x, model_scale().z) * size_factor()
	var plan: Dictionary = sit_level_plan(terrain_data, feet, fwd,
		Balance.GOLEM_SIT_LEVEL_FRONT * s.y, Balance.GOLEM_SIT_LEVEL_BACK * s.y,
		Balance.GOLEM_SIT_LEVEL_HALF_WIDTH * s.x, _sit_level_y, Balance.GOLEM_FLATTEN_SLOPE,
		TerrainData.SEA_LEVEL + Balance.GOLEM_FLATTEN_ABOVE_WATER, _sit_blocked_cells(),
		Balance.GOLEM_FLATTEN_RATE * Balance.GOLEM_FLATTEN_INTERVAL)
	if (plan.indices as PackedInt32Array).is_empty():
		return
	var morph: TerrainMorph = TerrainMorph.new()
	morph.setup(terrain_ctx, plan, Balance.GOLEM_FLATTEN_DURATION)
	path_service.register_projectile(morph)
	_sit_level_step = morph


## She has touched down: whoever is under the seat now takes the first sit damage
## (the position moved onto the seat already, _move_onto_seat).
func _on_seated() -> void:
	_move_onto_seat()
	_sit_victims.clear()
	if path_service != null:
		var reach_r: float = _seat_half.length()
		for u in path_service.get_units_in_radius(_seat_center, reach_r):
			if u == self or u.state == State.DEAD or u.doomed or u is Golem:
				continue
			if u is CrewedVehicle:
				if u is Airship or u.tribe_id == tribe_id:
					continue
			elif not u.is_targetable() or u.is_airborne():
				continue
			if on_seat(u.position):
				_sit_victims.append(u)
	# Enemy buildings under the seat (she may sit down on them from the crab walk).
	_sit_buildings.clear()
	if building_manager != null:
		var c: Vector2 = Vector2(_seat_center.x, _seat_center.z)
		var f: Vector2 = Vector2(_seat_fwd.x, _seat_fwd.z)
		for b in building_manager.buildings:
			if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == tribe_id or not b.is_attackable():
				continue
			var box: Rect2 = Rect2(Vector2(b.cell) * TerrainData.CELL_SIZE,
				Vector2(b.footprint) * TerrainData.CELL_SIZE)
			if seat_overlaps_box(c, f, _seat_half, box):
				_sit_buildings.append(b)
	_sit_damage_tick()
	_sit_damage_timer = Balance.GOLEM_SIT_DAMAGE_INTERVAL


## She gets up from the sit: back onto her feet (they lie in front of the seat).
func _on_rising() -> void:
	if _seat_center == Vector3.INF:
		return
	position += heading() * seat_back_m()
	_snap_to_ground()
	_seat_center = Vector3.INF
	_seat_floor_y = -INF
	facing = heading()
	if sit_combat != null:
		sit_combat.reset()
	_sit_victims.clear()
	_sit_buildings.clear()
	_after_seat_shift()


func _after_seat_shift() -> void:
	_sync_soa_pos()
	_tick_pos = position
	_last_pos = position
	_apply_speed()   # the manager's copy of the target radius


## While she sits (and is not getting up): the attacks of her limbs (GolemSitCombat).
func _tick_sit_combat(delta: float) -> void:
	if stance != STANCE_SIT or is_switching_stance() or _seat_center == Vector3.INF \
			or not sit_attacks_enabled or is_crabbing():
		return
	if sit_combat == null:
		sit_combat = GolemSitCombat.new(self)
	sit_combat.tick(delta)


## One tick of turning on the seat (GolemSitCombat): she turns about her hips —
## her logic position — and the seat turns with her (the victims stay who they were).
func sit_turn_tick() -> void:
	_seat_fwd = heading()


## A sit attack has been wound up: play it on its animation layer, if the model can.
func sit_attack_started(kind: StringName, windup: float) -> void:
	if _sit_anim != null and _sit_anim.is_active():
		_sit_anim.fire(GolemSitCombat.layer_of(kind), kind, windup)


## Is she turning on the seat right now?
func is_sit_turning() -> bool:
	return sit_combat != null and sit_combat.turning


## Every GOLEM_SIT_DAMAGE_INTERVAL while she sits: the damage on whoever is still
## under the seat.
func _tick_sit_damage(delta: float) -> void:
	if stance != STANCE_SIT or is_switching_stance() or _seat_center == Vector3.INF or is_crabbing():
		return
	_sit_damage_timer -= delta
	if _sit_damage_timer > 0.0:
		return
	_sit_damage_timer += Balance.GOLEM_SIT_DAMAGE_INTERVAL
	_sit_damage_tick()


## One tick of the sit damage: GOLEM_SIT_DAMAGE_MULT x the trample damage on every
## unit she sat down on that is still under the seat — of any tribe; enemy ground
## vehicles take a crush hit. Who left the seat drops out for good. Only enemy
## victims count as kills.
func _sit_damage_tick() -> void:
	var damage: int = Balance.GOLEM_SIT_DAMAGE_MULT * trample_damage()
	var kept: Array = []
	for u in _sit_victims:
		if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
			continue
		if not on_seat(u.position):
			continue
		if u is CrewedVehicle:
			_crush_vehicle(u)
			if is_instance_valid(u) and u.state != State.DEAD:
				kept.append(u)
			continue
		var hp: int = kill_hp_of(u)
		var foe: bool = u.tribe_id != tribe_id
		u.take_damage(damage, self)
		if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
			if foe:
				_credit_kill(hp)
			continue
		kept.append(u)
	_sit_victims = kept
	# Enemy buildings she sat down on (from the crab walk, user spec 2026-11-18): half the sit
	# damage in hit points, like every golem attack on a building.
	var standing: Array = []
	for b in _sit_buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		_strike_building(b, building_damage_for(damage))
		if is_instance_valid(b) and b.health > 0:
			standing.append(b)
	_sit_buildings = standing


## The victims she sat down on that are still in the list (tests, panel).
func sit_victims() -> Array:
	return _sit_victims


## Enemy buildings she sat down on that still stand (tests).
func sit_buildings() -> Array:
	return _sit_buildings


# --- Crab walk (user spec 2026-11-18) -------------------------------------------------
# With the switch "stationary" off a seated golem crawls on all fours, feet first: for a move
# order, toward an ordered target until a sit attack reaches it, and of her own accord toward a
# foe in her aggro radius when nothing is within reach from the seat — and toward an airship,
# which only the strike from the crab stand can hit. At the goal she sits down again (also on
# buildings; the ground rules of the seat stay, the sit damage strikes anew). Phases: crab_up ->
# crab stand (crab_idle / crab_walk) -> crab_down. She stays in STANCE_SIT throughout; her logic
# position stays the middle of her body (as on the seat), the model is drawn forward as there.

func is_crabbing() -> bool:
	return _crab != CRAB_NONE


## In the crab stand and free to walk (not winding up the airship strike).
func crab_walking() -> bool:
	return _crab == CRAB_STAND and _crab_air_ship == null


## Rooted: seated (or getting into / out of the crab stand) — other golems do not push her.
func is_rooted() -> bool:
	return is_sit_locked() and _crab != CRAB_STAND


## Her collision circle (other golems, vehicles' clearance) and the catapult's: the body circle —
## in the crab stand her whole body (user spec 2026-11-18: bigger, and open to attacks).
func collision_radius() -> float:
	return crab_body_radius() if is_crabbing() else trample_radius()


func crab_body_radius() -> float:
	return Balance.GOLEM_CRAB_BODY_RADIUS * model_scale().z * size_factor()


## Radius of the circle each limb treads in the crab walk.
func crab_limb_radius() -> float:
	return Balance.GOLEM_CRAB_LIMB_RADIUS * model_scale().x * size_factor()


## Where her feet and hands rest in the crab stand: left foot, right foot, left hand, right hand
## (the feet a little further ahead, the hands a little further back than on the seat).
func crab_contacts() -> Array[Vector3]:
	var fwd: Vector3 = heading()
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var sx: float = model_scale().x * size_factor()
	var sz: float = model_scale().z * size_factor()
	var sit_feet: Vector3 = position + fwd * seat_back_m()
	var feet: Vector3 = sit_feet + fwd * (Balance.GOLEM_CRAB_FOOT_FORWARD * sz)
	var foot: Vector3 = right * (Balance.GOLEM_SIT_FOOT_SIDE * sx)
	var hands: Vector3 = sit_feet - fwd * ((Balance.GOLEM_SIT_HAND_BACK + Balance.GOLEM_CRAB_HAND_BACK) * sz)
	var hand: Vector3 = right * (Balance.GOLEM_SIT_HAND_SIDE * sx)
	return [feet + foot, feet - foot, hands + hand, hands - hand]


## Seconds crab_up / crab_down take: GOLEM_CRAB_SWITCH_TIME at GOLEM_SIT_REF_HEIGHT, with the root of
## the height like sitting down.
func crab_switch_time() -> float:
	return Balance.GOLEM_CRAB_SWITCH_TIME * sqrt(height_m() / Balance.GOLEM_SIT_REF_HEIGHT)


## Ground one loop of crab_walk covers at 4 m (each model its own, measured on the export).
func crab_stride() -> float:
	return CRAB_CLIP_STRIDE


## Ground one loop of crab_walk covers at size factor 1 (world metres).
func crab_clip_speed() -> float:
	return crab_stride() * model_scale().z


## The switch "stationary" (sidebar). Switched on during a crawl she sits down where she is.
func set_sit_stationary(on: bool) -> void:
	sit_stationary = on
	if on:
		_crab_clear_goals()
		_crab_focus = null


## Sends her crawling: to `goal` (a move order; INF = none) or toward `target` (unit, building,
## airship) until she can strike it. False when she may not crab-walk now.
func crab_to(goal: Vector3, target: Object) -> bool:
	if not crab_ready():
		return false
	_crab_goal = goal
	_crab_target = target
	_crab_aimed = Vector3.INF
	_crab_fails = 0
	_crab_repath = 0.0
	_crab_think = 0.0
	if _crab == CRAB_STAND:
		_crab_plan()
	return true


func _crab_clear_goals() -> void:
	_crab_goal = Vector3.INF
	_crab_target = null
	_crab_aimed = Vector3.INF


## The goal of the current crawl (tests, panel): the move goal, else the target's place, else INF.
func crab_goal() -> Vector3:
	if _crab_goal != Vector3.INF:
		return _crab_goal
	if _crab_target_alive(_crab_target):
		return _crab_target_point(_crab_target)
	return Vector3.INF


func crab_target() -> Object:
	return _crab_target


## Is `o` still worth crawling to? A living, targetable enemy unit; a crewed enemy airship; a
## standing, attackable enemy building.
func _crab_target_alive(o: Object) -> bool:
	if o == null or not is_instance_valid(o):
		return false
	if o is Airship:
		return (o as Airship).state != State.DEAD and (o as Airship).tribe_id != tribe_id \
			and (o as Airship).auto_attackable()
	if o is Unit:
		var u: Unit = o as Unit
		return u.state != State.DEAD and not u.doomed and u.tribe_id != tribe_id and u.is_targetable()
	return o.health > 0 and o.tribe_id != tribe_id and o.is_attackable()


func _crab_target_point(o: Object) -> Vector3:
	return (o as Unit).position if o is Unit else o.center_world()


## Would she reach `o` from where she is, facing as she does? An airship: within reach of the
## strike behind her head once she turns her back to it. Anything else: inside the area of one of
## her single sit attacks (legs or arms) — she sits down there and strikes.
func _crab_reaches(o: Object) -> bool:
	if o is Airship:
		return _flat_dist(position, (o as Airship).position) <= crab_air_reach()
	if sit_combat == null:
		sit_combat = GolemSitCombat.new(self)
	var kinds: Array[StringName] = [GolemSitCombat.STOMP_L, GolemSitCombat.STOMP_R, GolemSitCombat.KICK_L,
		GolemSitCombat.KICK_R, GolemSitCombat.WIPE_L, GolemSitCombat.WIPE_R, GolemSitCombat.DOUBLE_STOMP]
	for k in kinds:
		if o is Unit:
			if sit_combat.in_area(k, (o as Unit).position):
				return true
		elif sit_combat.building_in_area(k, o):
			return true
	return false


## GolemSitCombat found nothing within reach and did not turn: not stationary, she crawls toward
## the target the player ordered (her focus), else toward the nearest foe in her aggro radius
## (user spec 2026-11-18: "wenn er nichts mehr zum Angreifen hat").
func sit_nothing_in_reach(foes: Array[Unit]) -> void:
	if not crab_ready() or is_crabbing() or _crab_goal != Vector3.INF or _crab_target != null:
		return
	if _crab_target_alive(_crab_focus):
		crab_to(Vector3.INF, _crab_focus)
		return
	_crab_focus = null
	var best: Unit = null
	var best_d: float = aggro_radius()
	for u in foes:
		if not _crab_target_alive(u) or u.is_airborne():
			continue
		var d: float = _flat_dist(position, u.position)
		if d <= best_d:
			best_d = d
			best = u
	if best != null:
		crab_to(Vector3.INF, best)


## One tick of the crab walk (after the stance logic).
func _tick_crab(delta: float) -> void:
	if stance != STANCE_SIT or is_switching_stance():
		if _crab != CRAB_NONE:
			_crab = CRAB_NONE   # (cannot happen: the stance waits for the crab walk)
		return
	if _crab == CRAB_NONE:
		_tick_crab_seated(delta)
		return
	_tick_crab_air(delta)
	match _crab:
		CRAB_UP:
			_crab_time -= delta
			if _crab_time <= 0.0:
				_crab_time = 0.0
				_crab = CRAB_STAND
				_crab_plan()
		CRAB_STAND:
			_tick_crab_stand(delta)
		CRAB_DOWN:
			if _crab_shift != Vector3.ZERO:
				var step: Vector3 = _crab_shift * clampf(delta / maxf(_crab_time, delta), 0.0, 1.0)
				position += step
				_crab_shift -= step
				_snap_to_ground()
				_sync_soa_pos()
			_crab_time -= delta
			if _crab_time <= 0.0:
				_crab_seated()
				return
	if _crab != CRAB_NONE:
		# Her body moves with her: the seat layout (model offset, floor) follows.
		_seat_center = position
		_seat_fwd = heading()
		_seat_floor_y = _seat_floor_height(position + _seat_fwd * seat_back_m(), _seat_fwd)


## Seated and not stationary: every CRAB_THINK she checks whether to get up into the crab stand —
## for an order, or an airship in her aggro radius (only the crab stand strikes those).
func _tick_crab_seated(delta: float) -> void:
	_crab_think -= delta
	if _crab_think > 0.0:
		return
	_crab_think = CRAB_THINK
	if not crab_ready():
		return
	if sit_stretching() or _stretch_queued or _sit_layers_busy():
		return   # a wound-up attack lands and a stretch runs out first
	if _crab_goal == Vector3.INF and _crab_target == null and can_strike_air():
		_crab_target = _crab_ship_near(aggro_radius())
	if _crab_goal != Vector3.INF:
		if _flat_dist(position, _crab_goal) <= arrive_eps() + 0.5:
			_crab_goal = Vector3.INF   # she sits there already
			return
		_begin_crab_up()
		return
	if _crab_target == null:
		return
	if not _crab_target_alive(_crab_target):
		_crab_target = null
		return
	if _crab_target is Airship or not _crab_reaches(_crab_target):
		_begin_crab_up()
	else:
		_crab_target = null   # within reach from the seat: the sit attacks take it


func _begin_crab_up() -> void:
	_crab = CRAB_UP
	_crab_time = crab_switch_time()
	if sit_combat != null:
		sit_combat.reset()   # (a turn on the seat ends)
	facing = heading()
	_sit_victims.clear()   # no sit damage on the way (user spec 2026-11-18)
	_sit_buildings.clear()
	_sit_level_y = INF   # the levelling of the old seat stops
	_crab_fails = 0
	_crab_aimed = Vector3.INF
	_after_seat_shift()   # the target radius grows to her whole body


## In the crab stand: (re)plans the crawl toward the move goal or the target.
func _crab_plan() -> void:
	move_aggressive = false
	waypoint_queue.clear()
	if _crab_goal != Vector3.INF:
		_crab_aimed = _crab_goal
		_start_path_to(_crab_goal)
		return
	if _crab_target_alive(_crab_target) and not _crab_reaches(_crab_target):
		_crab_aimed = _crab_target_point(_crab_target)
		_crab_repath = CRAB_REPATH
		_start_path_to(_crab_aimed)


func _crab_stop() -> void:
	if state == State.MOVE:
		_clear_path()
		_pending_target = Vector3.INF
		_set_state(State.IDLE)


func _tick_crab_stand(delta: float) -> void:
	if _crab_air_ship != null:
		return   # winding up the strike at an airship: she stands
	if not _wants_sit:
		_crab_clear_goals()
		_crab_stop()
		_begin_crab_down()   # called up: she sits down first, then gets up
		return
	_crab_repath -= delta
	_crab_wait -= delta
	if _crab_target != null and not _crab_target_alive(_crab_target):
		if _crab_focus == _crab_target:
			_crab_focus = null
		_crab_target = null
		if _crab_goal == Vector3.INF:
			_crab_stop()
	if _crab_goal == Vector3.INF and _crab_target == null and not sit_stationary and can_strike_air():
		var ship: Airship = _crab_ship_near(aggro_radius())
		if ship != null:
			_crab_target = ship
			_crab_fails = 0
			_crab_plan()
	if _crab_goal != Vector3.INF:
		if state == State.MOVE:
			return
		_crab_goal = Vector3.INF   # arrived (or no way further)
	if _crab_target != null:
		if _crab_reaches(_crab_target):
			_crab_stop()
			_crab_fails = 0
			if _crab_target is Airship:
				# She turns her back to it: the strike lands behind her head.
				var away: Vector3 = position - (_crab_target as Airship).position
				away.y = 0.0
				if away.length_squared() > 0.0001:
					facing = away.normalized()
				return
			_crab_target = null
			_try_crab_down()
			return
		if state != State.MOVE:
			_crab_fails += 1
			if _crab_fails > CRAB_MAX_FAILS:
				if _crab_focus == _crab_target:
					_crab_focus = null
				_crab_target = null   # no way to it: she sits down where she is
			else:
				_crab_plan()
			return
		if _crab_repath <= 0.0:
			_crab_repath = CRAB_REPATH
			if _flat_dist(_crab_target_point(_crab_target), _crab_aimed) > 1.0:
				_crab_plan()
		return
	_try_crab_down()


## Nowhere to go any more: she sits down — if she can sit here (or nearby); else she stays in the
## crab stand and looks again every CRAB_REPATH.
func _try_crab_down() -> void:
	if _crab_wait > 0.0:
		return
	if not _begin_crab_down():
		_crab_wait = CRAB_REPATH


## Sits down from the crab stand. Called up (stand_up) anywhere; otherwise only where the seat lies
## on the disc and her feet and hands rest on possible ground — buildings do not matter here (user
## spec 2026-11-18), up to half her body radius aside (she shifts there on the way down).
func _begin_crab_down() -> bool:
	_crab_stop()
	facing = heading()
	var shift: Vector3 = Vector3.ZERO
	if _wants_sit:
		var spot: Vector3 = _crab_seat_spot()
		if spot == Vector3.INF:
			return false
		shift = Vector3(spot.x - position.x, 0.0, spot.z - position.z)
		_start_sit_levelling(spot + heading() * seat_back_m(), crab_switch_time())
	_crab_shift = shift
	_crab = CRAB_DOWN
	_crab_time = crab_switch_time()
	return true


## Where the middle of her seat can go down from the crab stand: here, else up to
## GOLEM_SIT_SEARCH_SHARE of her body radius aside (as find_seat, but buildings do not count).
func _crab_seat_spot() -> Vector3:
	var fwd: Vector3 = heading()
	var half: Vector2 = seat_half_extent()
	var search: float = trample_radius() * Balance.GOLEM_SIT_SEARCH_SHARE
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for ring in [0.5, 1.0]:
		for k in range(8):
			offsets.append(Vector2.from_angle(float(k) * TAU / 8.0) * search * ring)
	for off in offsets:
		var c: Vector3 = Vector3(position.x + off.x, position.y, position.z + off.y)
		if seat_on_disc(c, fwd, half) and sit_pose_ok(c, fwd):
			return c
	return Vector3.INF


## crab_down has played out: she sits — the seat fixed anew, the sit damage strikes who is under it now.
func _crab_seated() -> void:
	_crab = CRAB_NONE
	_crab_time = 0.0
	if _crab_shift != Vector3.ZERO:
		position += _crab_shift
		_snap_to_ground()
	_crab_shift = Vector3.ZERO
	var fwd: Vector3 = heading()
	facing = fwd
	_seat_fwd = fwd
	_seat_half = seat_half_extent()
	_seat_floor_y = _seat_floor_height(position + fwd * seat_back_m(), fwd)
	position.y = maxf(position.y, _seat_floor_y)
	_seat_center = position
	_after_seat_shift()
	_crab_think = 0.0
	if _wants_sit:
		_on_seated()


# --- The airship strike from the crab stand (user spec 2026-11-18) ---------------------------
# The only way a seated golem hits an airship: in the crab stand, area behind her head. Like the
# standing swat a hull hit (two bring a ship down), with the swat's wind-up and cooldown.

## Middle of the area behind her head.
func crab_air_center() -> Vector3:
	return position - heading() * (Balance.GOLEM_CRAB_AIR_BACK * model_scale().z * size_factor())


func crab_air_radius() -> float:
	return Balance.GOLEM_CRAB_AIR_RADIUS * model_scale().z * size_factor()


## How far from her middle an airship may be to come into the area once she turns her back to it.
func crab_air_reach() -> float:
	return Balance.GOLEM_CRAB_AIR_BACK * model_scale().z * size_factor() + crab_air_radius()


func in_crab_air_zone(p: Vector3, slack: float = 1.0) -> bool:
	return _flat_dist(p, crab_air_center()) <= crab_air_radius() * slack


## Nearest crewed enemy airship within `radius` of her middle.
func _crab_ship_near(radius: float) -> Airship:
	if not can_strike_air() or path_service == null:
		return null
	var best: Airship = null
	var best_d: float = INF
	for u in path_service.get_enemy_vehicles_in_radius(position, radius, tribe_id):
		if not (u is Airship) or not (u as Airship).auto_attackable():
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d:
			best_d = d
			best = u as Airship
	return best


## Nearest crewed enemy airship inside the area behind her head.
func _crab_ship_in_zone() -> Airship:
	if not can_strike_air() or path_service == null:
		return null
	var best: Airship = null
	var best_d: float = INF
	for u in path_service.get_enemy_vehicles_in_radius(position, crab_air_reach(), tribe_id):
		if not (u is Airship) or not (u as Airship).auto_attackable() or not in_crab_air_zone(u.position):
			continue
		var d: float = _flat_dist(crab_air_center(), u.position)
		if d < best_d:
			best_d = d
			best = u as Airship
	return best


func _tick_crab_air(delta: float) -> void:
	_crab_air_cooldown = maxf(_crab_air_cooldown - delta, 0.0)
	if _crab_air_ship != null:
		_crab_air_time -= delta
		if _crab_air_time <= 0.0:
			var ship: Airship = _crab_air_ship
			_crab_air_ship = null
			_land_crab_swat(ship)
		return
	if _crab != CRAB_STAND or _crab_air_cooldown > 0.0:
		return
	var target: Airship = _crab_ship_in_zone()
	if target == null:
		return
	_crab_air_ship = target
	_crab_air_time = current_windup(ATTACK_SWAT)
	_crab_air_cooldown = cooldown_for(ATTACK_SWAT)
	_no_combat_timer = 0.0
	_play_clip(CLIP_CRAB_SWAT, Balance.GOLEM_CRAB_AIR_IMPACT / maxf(_crab_air_time, 0.05), true)


## Is the strike from the crab stand wound up (tests)?
func crab_air_pending() -> bool:
	return _crab_air_ship != null


## The strike lands: a hull hit on the ship, if it is still in the area (a little slack for its drift).
func _land_crab_swat(ship: Airship) -> bool:
	_no_combat_timer = 0.0
	if ship == null or not is_instance_valid(ship) or ship.state == State.DEAD \
			or ship.tribe_id == tribe_id or not ship.auto_attackable():
		return false
	if not in_crab_air_zone(ship.position, SWAT_SLACK):
		return false
	_play_strike_sfx(ATTACK_SWAT)
	ship.register_hull_hit(position)
	return true


## Seconds a stance switch takes at the current size.
func stance_switch_time() -> float:
	return minf(Balance.GOLEM_STANCE_SWITCH_TIME * sqrt(size_factor()),
		Balance.GOLEM_STANCE_SWITCH_MAX)


func is_switching_stance() -> bool:
	return _stance_switch > 0.0


## May she change the stance of her own accord again? (Not right after the last
## change — she would rock up and down.)
func stance_settled() -> bool:
	return _stance_age >= Balance.GOLEM_STANCE_MIN_TIME


## Starts the next step toward the stance `target`: bending down / getting up,
## sitting down / getting up from the sit. The stances lie in a row (stand -
## crouch - sit) and one switch goes ONE step — from standing, sitting down is two
## switches (see _tick_stance). Returns false when nothing was started.
func _begin_stance(target: int) -> bool:
	if is_switching_stance() or is_stretching() or stance == target:
		return false
	var step: int = stance + (1 if target > stance else -1)
	_stance_target = step
	if stance == STANCE_SIT:
		_on_rising()
	if step == STANCE_SIT:
		_start_sit_levelling()
	if step == STANCE_SIT or stance == STANCE_SIT:
		_stance_switch = sit_switch_time()
		_play_clip(CLIP_SIT_DOWN if step == STANCE_SIT else CLIP_SIT_UP,
			SIT_CLIP_LENGTH / _stance_switch, true)
		return true
	_stance_switch = stance_switch_time()
	var clip: StringName = CLIP_CROUCH_DOWN if step == STANCE_CROUCH else CLIP_CROUCH_UP
	_play_clip(clip, STANCE_CLIP_LENGTH / _stance_switch, true)
	return true


## Runs a stance switch to its end, and gets her up on her own when the crouch
## no longer serves: she has to walk (at once), or she has nothing to strike any
## more (once the stance has settled).
func _tick_stance(delta: float) -> void:
	_stance_age += delta
	if is_switching_stance():
		if _wants_sit and _stance_target == STANCE_SIT and _seat_center == Vector3.INF \
				and _stance_switch - delta <= Balance.GOLEM_SIT_SEAT_LEAD:
			_move_onto_seat()   # the selection ring moves a little ahead of the touch-down
		if _wants_sit and _sit_shift != Vector3.ZERO and _seat_center == Vector3.INF:
			# On the way down she moves onto the free seat (find_seat), evenly.
			var step: Vector3 = _sit_shift * clampf(delta / _stance_switch, 0.0, 1.0)
			position += step
			_sit_shift -= step
			_snap_to_ground()
			_after_seat_shift()
		_stance_switch -= delta
		if _stance_switch <= 0.0:
			_stance_switch = 0.0
			# Up from the sit she is only passing through the crouch: no waiting time.
			_stance_age = 1000.0 if stance == STANCE_SIT else 0.0
			stance = _stance_target
			if stance == STANCE_SIT:
				_sit_shift = Vector3.ZERO
				_on_seated()
			elif stance == STANCE_STAND:
				_leaving_sit = false
		return
	if _stomp_landed:
		# The stomp left her crouched (_land_attack). While its clip still settles
		# she stays put. Then she stays down if she means to strike on from there —
		# or gets up again at once: that getting-up still belongs to the attack and
		# does not wait for the stance's minimum time.
		if _attack_anim_left > 0.0 or _pending_attack != &"":
			return
		_stomp_landed = false
		if not _stays_down_after_stomp():
			_begin_stance(STANCE_STAND)
		return
	if stance == STANCE_SIT:
		if is_crabbing():
			return   # in the crab stand she sits down first (_tick_crab)
		# Only stand_up() gets her up (user spec 2026-11-17) — through the crouch.
		if not _wants_sit:
			_leaving_sit = true
			_begin_stance(STANCE_CROUCH)
		return
	if _wants_sit:
		# A blow already wound up or an attack clip still playing comes first.
		if _pending_attack == &"" and _attack_anim_left <= 0.0 and not is_stretching():
			_begin_stance(STANCE_SIT)   # bending down first, then sitting down: one step each
		return
	if _leaving_sit:
		_begin_stance(STANCE_STAND)   # up from the sit: on to standing, no waiting time
		return
	if stance != STANCE_CROUCH or _pending_attack != &"":
		return
	if state == State.ATTACK and (_in_melee or _target_in_reach()):
		return   # striking from here: the attack choice decides (see _attack_or_switch)
	if state == State.IDLE and not stance_settled():
		return   # nothing to do, but she only just bent down
	_begin_stance(STANCE_STAND)


## Is her current target (unit or building) within reach right now? Asked by the
## stance logic instead of trusting `_in_melee` alone: every target switch
## (_begin_attack -> _end_attack) clears that flag, and _tick_attack only sets it
## again in the NEXT tick. In between, _tick_stance took the switch for "she has to
## walk" and got her up — with a new target right in front of her — and the
## stance's minimum time then left her nothing but kicks (user report 2026-11-16:
## "bueckt sich, steht wieder auf und tritt"; 32 of 36 stand-ups mid-fight in
## tests/diag_golem_fight.gd happened on such a switch).
func _target_in_reach() -> bool:
	if _unit_target_attackable(attack_target) and attack_target.tribe_id != tribe_id:
		return not attack_target.is_airborne() \
			and _flat_dist(position, attack_target.position) <= reach()
	if _building_target_valid():
		return attack_building.footprint_distance_to(Vector2(position.x, position.z)) <= reach() - 0.5
	return false


## After a stomp: does she stay crouched? Only while she stands in the fight and
## her best attack from down there is a ground attack (the plain choice, seen
## from the crouch). With nothing to strike, a march ahead or an owed stretch she
## gets up.
func _stays_down_after_stomp() -> bool:
	if _stretch_queued or not (state == State.ATTACK and (_in_melee or _target_in_reach())):
		return false
	return stance_for(_choose_attack()) == STANCE_CROUCH


## The attack is due: strike — or change the stance first when the best attack
## needs the other one. `building` = the assault target, if any.
func _attack_or_switch(building = null) -> void:
	if _stretch_queued:
		return   # she has grown: the stretch comes first (see _tick_stretch)
	if stance == STANCE_SIT:
		return   # she gets up first (_tick_stance); nothing is struck from the sit
	var ship: Airship = _airship_in_reach()
	if ship != null:
		# An airship overhead goes before the crowd at her feet — standing.
		if stance == STANCE_STAND:
			_swat(ship)
			return
		if stance_settled():
			_begin_stance(STANCE_STAND)
			return
	var kind: StringName = _choose_attack()
	if stance_for(kind) != stance:
		# Not right after the last change (she would rock up and down) — unless
		# she cannot strike anything at all from the stance she is in.
		var stay: StringName = _attack_in_stance()
		if (stance_settled() or attack_worth(stay) <= 0.0) \
				and _begin_stance(stance_for(kind)):
			return
		kind = stay   # too early to change again: make do
	_wind_up(kind, building)


## The best attack she can strike WITHOUT changing the stance.
func _attack_in_stance() -> StringName:
	if stance != STANCE_CROUCH:
		return ATTACK_KICK
	return ATTACK_DRUM if attack_value(ATTACK_DRUM) > attack_value(ATTACK_SLAM) else ATTACK_SLAM


## What the attack `kind` would be worth if it landed right now: for every unit
## it would strike (same area, same target cap as the real landing) the damage it
## really takes — never more than the unit has left —, plus
## GOLEM_STRUCTURE_VALUE for every building or vehicle.
func attack_worth(kind: StringName) -> float:
	if kind == ATTACK_KICK:
		return _pick_kick_leg()
	return _worth_now(kind)


## Each leg kicks into its own lane (user spec 2026-11-18): weighs both, keeps the better in
## kick_side and returns its worth. A tie: the leg on the side of her target, else the other
## leg than last time.
func _pick_kick_leg() -> float:
	kick_side = 1.0
	var right: float = _worth_now(ATTACK_KICK)
	kick_side = -1.0
	var left: float = _worth_now(ATTACK_KICK)
	if absf(right - left) > 0.0001:
		kick_side = 1.0 if right > left else -1.0
	else:
		kick_side = _kick_side_of_target()
	return maxf(right, left)


## The leg on the side of her target (unit or building); none, or straight ahead: the other
## leg than last time.
func _kick_side_of_target() -> float:
	var at: Vector3 = Vector3.INF
	if _target_valid(attack_target):
		at = attack_target.position
	elif _building_target_valid():
		at = attack_building.center_world()
	if at != Vector3.INF:
		var side: float = (at - position).dot(_heading_frame()[1])
		if absf(side) > 0.05:
			return signf(side)
	return -_last_kick_side


## Where the lane of the kicking leg runs: this far to the side of her middle (+ right).
## Grows with the body; from GOLEM_BODY_SCALE_HEIGHT on it is half the lane's width, so the
## two lanes just touch in the middle — below, the lane is wider and they overlap.
func kick_leg_offset() -> float:
	return KICK_HALF_WIDTH * Balance.GOLEM_BODY_REACH_FACTOR_AT_ANCHOR * body_anchor_ratio()


func _worth_now(kind: StringName) -> float:
	var struck: Dictionary = _struck_targets(kind)
	var worth: float = 0.0
	if kind == ATTACK_DRUM:
		worth = _drum_unit_worth()
	else:
		var damage: float = float(attack_damage(kind))
		for u in struck.units:
			worth += minf(damage, float(u.health))
	# A building: the hit points it really loses (2026-11-18), a vehicle: GOLEM_STRUCTURE_VALUE.
	var per_building: float = float(building_damage_total(kind))
	for b in struck.buildings:
		if is_instance_valid(b):
			worth += minf(per_building, float(b.health))
	return worth + Balance.GOLEM_STRUCTURE_VALUE * float((struck.vehicles as Array).size())


## What one hit worth `amount` against a unit takes off a building (user spec 2026-11-18):
## GOLEM_BUILDING_DAMAGE_SHARE of it, at least 1.
static func building_damage_for(amount: int) -> int:
	return maxi(int(floor(float(amount) * Balance.GOLEM_BUILDING_DAMAGE_SHARE)), 1)


## All the hit points the attack `kind` takes off one building (the drum: its three hits).
func building_damage_total(kind: StringName) -> int:
	if kind == ATTACK_DRUM:
		var sum: int = 0
		for hit in range(Balance.GOLEM_DRUM_HITS.size()):
			sum += building_damage_for(drum_hit_damage(hit))
		return sum
	return building_damage_for(attack_damage(kind))


## The drum's worth on units, hit by hit (Bugfix 2026-11-16): every one of the
## three hits picks its own targets (its own cap), so whoever the first hits kill
## is replaced by the next unit in the area. Counting the drum as one blow of its
## whole damage on one cap of targets undervalued it against crowds of weak units.
func _drum_unit_worth() -> float:
	var order: Array[Unit] = _ordered_victims(ATTACK_DRUM)
	var room: int = max_targets_of(ATTACK_DRUM)
	if _building_target_valid() and _buildings_in_area(ATTACK_DRUM).has(attack_building):
		room -= 1
	var left: Array[float] = []
	for u in order:
		left.append(float(u.health))
	var worth: float = 0.0
	for hit in range(Balance.GOLEM_DRUM_HITS.size()):
		var damage: float = float(drum_hit_damage(hit))
		var struck: int = 0
		for i in range(left.size()):
			if struck >= room:
				break
			if left[i] <= 0.0:
				continue
			var dealt: float = minf(damage, left[i])
			worth += dealt
			left[i] -= dealt
			struck += 1
	return worth


## The seconds the attack `kind` costs from the current stance: its cooldown,
## plus a share of the stance switch when it needs the other stance (the switch
## pays off over several attacks — GOLEM_STANCE_PLAN_ATTACKS).
func attack_time(kind: StringName) -> float:
	var t: float = cooldown_for(kind)
	if stance_for(kind) != stance:
		t += stance_switch_time() / float(Balance.GOLEM_STANCE_PLAN_ATTACKS)
	# A directed attack waits until the body has turned (2026-11-16): that time
	# is a lead-in like the stance switch. The stomp needs no aim.
	if kind != ATTACK_STOMP:
		t += turn_time_needed() / float(Balance.GOLEM_STANCE_PLAN_ATTACKS)
	return t


## Seconds the body still has to turn before a directed attack may begin: the
## angle to the facing beyond GOLEM_ATTACK_ALIGN_DEG at turn_rate(). 0 when
## aligned. While the choice is weighed as if already turned (see
## _stomp_while_turning) the real value is held in _assumed_turn_time.
func turn_time_needed() -> float:
	if _assumed_turn_time >= 0.0:
		return _assumed_turn_time
	var want: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if want.length_squared() < 0.000001:
		return 0.0
	var angle: float = acos(clampf(heading().dot(want.normalized()), -1.0, 1.0))
	var left: float = angle - deg_to_rad(Balance.GOLEM_ATTACK_ALIGN_DEG)
	return maxf(left, 0.0) / maxf(turn_rate(), 0.001)


## The stomp needs no aim (user spec 2026-11-16): while the body is still
## turning toward its target, she may jump right away — when the stomp is her
## best plan, with the turn counted against every directed attack. The other
## attacks are weighed as if she were already turned (their areas lie ahead of
## the body), only their time carries the turn. Returns true when she jumped.
func _stomp_while_turning(building = null) -> bool:
	if _stretch_queued or not can_stomp() or _airship_in_reach() != null:
		return false
	var want: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if want.length_squared() < 0.000001:
		return false
	var saved: Vector3 = _heading
	_assumed_turn_time = turn_time_needed()
	_heading = want.normalized()
	var kind: StringName = _choose_attack()
	_heading = saved
	_assumed_turn_time = -1.0
	if kind != ATTACK_STOMP:
		return false
	_wind_up(ATTACK_STOMP, building)
	return true


## Expected damage per second of the attack `kind` right now (see attack_worth).
## Read as a PLAN this is "a lead-in plus GOLEM_STANCE_PLAN_ATTACKS attacks":
## without a lead-in the attack's worth over its cooldown, with a stance switch
## the switch's time spread over those attacks (attack_time). The stomp is a
## lead-in of its own kind — see stomp_plan_value.
func attack_value(kind: StringName) -> float:
	if kind == ATTACK_STOMP:
		return stomp_plan_value()
	return attack_worth(kind) / attack_time(kind)


## Seconds the clip of the attack `kind` plays at the current size.
func attack_duration(kind: StringName) -> float:
	return float(CLIP_LENGTH.get(kind, 0.0)) / (attack_speed(kind) * clip_rate(kind))


## The stomp as a plan (damage per second over the whole plan): it costs its
## cooldown, brings its own damage and leaves her crouched — so the ground
## attacks follow without a stance switch. Or she gets up again afterwards (the
## cooldown, or the clip plus the switch if that takes longer) and goes on
## kicking. The better continuation counts. A stomp that would strike nothing is
## worth nothing: she never jumps just to get down.
func stomp_plan_value() -> float:
	var lead: float = attack_worth(ATTACK_STOMP)
	if lead <= 0.0:
		return 0.0
	var n: float = float(Balance.GOLEM_STANCE_PLAN_ATTACKS)
	var cooldown: float = cooldown_for(ATTACK_STOMP)
	# The stomp itself needs no aim; she turns while she jumps, and only what is
	# left of the turn afterwards delays the directed attacks that follow.
	var turn: float = turn_time_needed()
	var best: float = 0.0
	for kind in [ATTACK_SLAM, ATTACK_DRUM]:
		best = maxf(best, (lead + n * attack_worth(kind))
			/ (maxf(cooldown, turn) + n * cooldown_for(kind)))
	var up: float = maxf(cooldown, attack_duration(ATTACK_STOMP) + stance_switch_time())
	return maxf(best, (lead + n * attack_worth(ATTACK_KICK))
		/ (maxf(up, turn) + n * cooldown_for(ATTACK_KICK)))


## May she jump right now? Only standing, and not right after a stance change
## (the stomp ends crouched: she would rock up and down).
func can_stomp() -> bool:
	return stomp_enabled and stance == STANCE_STAND and not is_switching_stance() and stance_settled()


## Seconds between two attacks at the current size (1,8 s .. 3 s at 80 m).
func strike_cooldown() -> float:
	return lerpf(STRIKE_COOLDOWN, Balance.GOLEM_STRIKE_COOLDOWN_MAX, growth_t())


## The cooldown the attack `kind` leaves behind: the drum takes longer.
## The slam is struck crouched and comes back faster; the drum takes the plain rhythm.
func cooldown_for(kind: StringName) -> float:
	if kind == ATTACK_DRUM:
		return strike_cooldown()   # three hits: the plain attack rhythm (1,8 s at the start)
	if kind == ATTACK_SLAM:
		return strike_cooldown() * Balance.GOLEM_SLAM_COOLDOWN / Balance.GOLEM_STRIKE_COOLDOWN
	if kind == ATTACK_STOMP:
		# As long as its clip: whoever stays down strikes on right after settling.
		return strike_cooldown() * Balance.GOLEM_STOMP_COOLDOWN / Balance.GOLEM_STRIKE_COOLDOWN
	return strike_cooldown()


## How fast the body turns (rad/s): GOLEM_TURN_RATE at the starting size, down to
## GOLEM_TURN_RATE_FULL_SHARE of the fire ram's rate at 80 m. Seated: sit_turn_rate().
func turn_rate() -> float:
	if is_crabbing():
		return standing_turn_rate(height_m()) * Balance.GOLEM_CRAB_TURN_SHARE
	return sit_turn_rate() if stance == STANCE_SIT else standing_turn_rate(height_m())


## The standing turn rate of a golem `h` metres tall (rad/s).
static func standing_turn_rate(h: float) -> float:
	var t: float = clampf((h - Balance.GOLEM_HEIGHT) / (Balance.GOLEM_MAX_HEIGHT - Balance.GOLEM_HEIGHT), 0.0, 1.0)
	return lerpf(Balance.GOLEM_TURN_RATE, Balance.FIRERAM_TURN_RATE * Balance.GOLEM_TURN_RATE_FULL_SHARE, t)


## The seated turn rate (rad/s, user spec 2026-11-18): GOLEM_SIT_TURN_SHARE of the standing
## rate at GOLEM_SIT_MIN_HEIGHT, falling linearly in the height to GOLEM_SIT_TURN_RATE_AT_MAX_DEG
## at GOLEM_MAX_HEIGHT and on at the same slope beyond, never below GOLEM_SIT_TURN_RATE_MIN_DEG.
func sit_turn_rate() -> float:
	return Golem.sit_turn_rate_at(height_m())


static func sit_turn_rate_at(h: float) -> float:
	var lo: float = Balance.GOLEM_SIT_MIN_HEIGHT
	var at_lo: float = standing_turn_rate(lo) * Balance.GOLEM_SIT_TURN_SHARE
	var at_max: float = deg_to_rad(Balance.GOLEM_SIT_TURN_RATE_AT_MAX_DEG)
	var r: float = at_lo + (at_max - at_lo) * (h - lo) / (Balance.GOLEM_MAX_HEIGHT - lo)
	return maxf(r, deg_to_rad(Balance.GOLEM_SIT_TURN_RATE_MIN_DEG))


## Has her body turned to within `deg` degrees of the flat direction `dir`?
func is_turned_to(dir: Vector3, deg: float) -> bool:
	var d: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.000001:
		return true
	return heading().dot(d.normalized()) >= cos(deg_to_rad(deg))


## The direction the body really points (flat): `_heading` once it has been
## slewed, `facing` before the first tick.
func heading() -> Vector3:
	var h: Vector3 = _heading if _heading != Vector3.ZERO else facing
	h.y = 0.0
	return h.normalized() if h.length_squared() > 0.000001 else Vector3(0, 0, 1)


## Turns the body at once into the facing (tests, summoning).
func snap_heading() -> void:
	_heading = Vector3.ZERO


## Rotates the body toward `facing` at turn_rate() — the fire ram's slew.
func _slew_heading(delta: float) -> void:
	var want_dir: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if want_dir.length_squared() < 0.000001:
		return
	want_dir = want_dir.normalized()
	if _heading == Vector3.ZERO:
		_heading = want_dir
		return
	var cur: float = atan2(_heading.x, _heading.z)
	var diff: float = wrapf(atan2(want_dir.x, want_dir.z) - cur, -PI, PI)
	var step: float = turn_rate() * delta
	if absf(diff) <= step:
		_heading = want_dir
	else:
		var a: float = cur + signf(diff) * step
		_heading = Vector3(sin(a), 0.0, cos(a))


## Has the body turned to within GOLEM_ATTACK_ALIGN_DEG of the facing? Attacks
## only begin then.
func is_turned_to_facing() -> bool:
	var want_dir: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if want_dir.length_squared() < 0.000001:
		return true
	return heading().dot(want_dir.normalized()) >= cos(deg_to_rad(Balance.GOLEM_ATTACK_ALIGN_DEG))


## While the body is still turning toward where it wants to go it walks slower
## (it does not glide sideways): full speed when aligned, down to
## GOLEM_TURN_MIN_SPEED_SHARE when it would have to walk backward.
func _slope_speed(slope: float) -> float:
	var crab: bool = crab_walking()
	if not crab and (stance != STANCE_STAND or is_switching_stance() or is_stretching()):
		return 0.0   # crouched, bending down, getting up or stretching: rooted
	var want_dir: Vector3 = Vector3(facing.x, 0.0, facing.z)
	var share: float = 1.0
	if want_dir.length_squared() > 0.000001:
		share = maxf(Balance.GOLEM_TURN_MIN_SPEED_SHARE, heading().dot(want_dir.normalized()))
	if crab:
		share *= Balance.GOLEM_CRAB_SPEED_SHARE   # a third of her walking speed (user spec 2026-11-18)
	return super._slope_speed(slope) * share


## Ground speed right now: that of her size (speed_for_size).
func current_speed() -> float:
	return speed_for_size(size_factor())


## From level 1 the golem walks straight through other units (and tramples the
## enemies among them).
func ignores_unit_collision() -> bool:
	return level >= 1


## SWITCHES of the level system (2026-11-16). The base golem answers them from
## its level; the demon golem (DemonGolem) has no levels and answers them from
## its height. Everything that used to ask `level` directly for one of these
## asks here.
## Does she trample what stands under her while she walks? (From level 1.)
func tramples() -> bool:
	return level >= 1


## The giant's package (level 7): levels the ground, walks straight, tramples
## buildings and wrecks vehicles.
func is_giant() -> bool:
	return level >= Balance.GOLEM_MAX_LEVEL


## Does he level the ground under him? Every golem from GOLEM_FLATTEN_MIN_HEIGHT on (user spec
## 2026-11-18; before: the giant of level 7, the genesis golem from stage 4).
func flattens() -> bool:
	return height_m() >= Balance.GOLEM_FLATTEN_MIN_HEIGHT - 0.0001


## Does the lifetime still run out? (Until the final-bonus level.)
func has_lifetime() -> bool:
	return level < Balance.GOLEM_FINAL_BONUS_LEVEL


## A kill — by an attack or underfoot: buys time, raises the health limit, patches
## the construct up (to that limit) and counts toward the next level.
## `_victim_hp`: the victim's health limit (kill_hp_of), -1 for one without health
## (building, vehicle, the ritual chamber's reward) — only the demon golem uses it.
func _credit_kill(_victim_hp: int = -1) -> void:
	kills += 1
	life_left += Balance.GOLEM_LIFE_PER_KILL
	while level < level_for_kills(kills):
		_level_up()
	var steps: int = growth_steps_for_kills(kills)
	if steps != growth_steps:
		growth_steps = steps
		_apply_speed()
		_queue_stretch()
	# The ceiling: +5 per kill up to 1000; the giant has the full 1000 at once,
	# and every growth step beyond level 7 lifts it by GOLEM_GROWTH_MAX_HP.
	if level >= Balance.GOLEM_MAX_LEVEL:
		max_health = max_health_cap()
	else:
		max_health = mini(max_health + Balance.GOLEM_MAX_HP_PER_KILL, max_health_cap())
	health = mini(health + Balance.GOLEM_HP_PER_KILL, max_health)


## Health limit of a victim for the kill reward: a unit's max_health, -1 for a
## vehicle (it has no health) — read BEFORE the blow, the victim may be gone after.
static func kill_hp_of(u) -> int:
	if u is CrewedVehicle or not (u is Unit) or u.max_health <= 1:
		return -1
	return u.max_health


func _level_up() -> void:
	level += 1
	_queue_stretch()
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
		# The target radius grows with the body (ranges against her).
		(path_service as UnitManager).soa_reach[_idx] = target_radius()


## Radius of the ground the giant levels: only where others can strike him —
## his target radius (user spec 2026-11-16; before: his whole body).
func flatten_radius() -> float:
	return target_radius()


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
			if floor_height > -INF and _next_to_water(td, vx, vz):
				continue   # the shore itself stays: lowering it moves the sea inland
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


## Whether a vertex touches the sea (one of its eight neighbours at or below the
## waterline). Bugfix 2026-11-16: lowering such a vertex pulled the waterline
## inland - right under the giant who was levelling there, who then drowned.
static func _next_to_water(td: TerrainData, vx: int, vz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx: int = vx + dx
			var nz: int = vz + dz
			if (dx == 0 and dz == 0) or nx < 0 or nz < 0 or nx >= td.verts or nz >= td.verts:
				continue
			if td.heights[nz * td.verts + nx] <= TerrainData.SEA_LEVEL + WATER_EPS:
				return true
	return false


## Level 7, the giant: the ground he stands on becomes level — it sinks to the
## lowest spot under his body (user spec) — gradually, at most GOLEM_FLATTEN_RATE
## metres per second. Checked every GOLEM_FLATTEN_INTERVAL, one morph at a time; the usual terrain rules apply (TerrainMorph: buildings on
## a new edge burst, the flooded drown, everything rides the moving ground).
func _tick_flatten(delta: float) -> void:
	if not flattens() or terrain_ctx == null or terrain_data == null \
			or path_service == null or is_sit_locked():
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
	if regen_per_second() <= 0.0 or health >= max_health:
		_level_regen_frac = 0.0
		return
	_level_regen_frac += regen_per_second() * delta
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
	var crab: bool = crab_walking()
	if not tramples() or path_service == null or _tick_pos == Vector3.INF or delta <= 0.0 \
			or (is_sit_locked() and not crab):
		return
	var walked: float = Vector2(position.x - _tick_pos.x, position.z - _tick_pos.z).length()
	if walked / delta < Balance.GOLEM_TRAMPLE_MIN_SPEED:
		return
	# Target cap (max_targets): at most that many things are under his feet "at
	# once" — everything trampled stays in _trampled for its interval (units 1 s,
	# vehicles 2 s, buildings 4 s), and while that list is full nothing new is
	# trampled. Units first (nearest first), then vehicles, then buildings.
	var room: int = max_targets() - _trampled.size()
	if room <= 0:
		return
	var damage: int = trample_damage()
	# Where she treads: her body circle — in the crab walk only her four limbs (user spec
	# 2026-11-18), one circle each; the target cap counts for all four together.
	var circles: PackedVector3Array = _trample_circles()
	var radius: float = collision_radius() if crab else trample_radius()
	var under: Array[Unit] = []
	for u in path_service.get_units_in_radius(position, radius):
		if not crab or _trample_gap(circles, u.position) <= 0.0:
			under.append(u)
	under.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _trample_gap(circles, a.position) < _trample_gap(circles, b.position))
	for u in under:
		if room <= 0:
			return
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		var id: int = u.get_instance_id()
		if _trampled.has(id):
			continue
		_trampled[id] = Balance.GOLEM_TRAMPLE_INTERVAL
		room -= 1
		_no_combat_timer = 0.0
		var hp: int = kill_hp_of(u)
		u.take_damage(damage, self)
		if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
			_credit_kill(hp)
	if not is_giant():
		return
	# The giant (maximum level) also walks over vehicles that do not fly his
	# flag: one crush hit per vehicle every GOLEM_TRAMPLE_VEHICLE_INTERVAL.
	for u in under:
		if room <= 0:
			return
		if u == self or not crushes_vehicle(u):
			continue
		var vid: int = u.get_instance_id()
		if _trampled.has(vid):
			continue
		_trampled[vid] = Balance.GOLEM_TRAMPLE_VEHICLE_INTERVAL
		room -= 1
		_no_combat_timer = 0.0
		_crush_vehicle(u)
	# ... and walks buildings down as well: half the trampling damage in hit points every
	# GOLEM_TRAMPLE_BUILDING_INTERVAL for each enemy building under him (2026-11-18).
	if building_manager == null:
		return
	for b in building_manager.buildings.duplicate():
		if room <= 0:
			return
		if not is_instance_valid(b) or b.health <= 0 or b.tribe_id == tribe_id \
				or not b.is_attackable():
			continue
		var touched: bool = false
		for c in circles:
			if b.footprint_distance_to(Vector2(c.x, c.z)) <= c.y:
				touched = true
				break
		if not touched:
			continue
		var bid: int = b.get_instance_id()
		if _trampled.has(bid):
			continue
		_trampled[bid] = Balance.GOLEM_TRAMPLE_BUILDING_INTERVAL
		room -= 1
		_no_combat_timer = 0.0
		_strike_building(b, building_damage_for(damage))


## Where she treads (x, z = middle, y = radius): her body circle, in the crab walk her four limbs.
func _trample_circles() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	if crab_walking():
		var r: float = crab_limb_radius()
		for p in crab_contacts():
			out.append(Vector3(p.x, r, p.z))
	else:
		out.append(Vector3(position.x, trample_radius(), position.z))
	return out


## How far p lies outside the nearest of the circles (negative: inside).
static func _trample_gap(circles: PackedVector3Array, p: Vector3) -> float:
	var best: float = INF
	for c in circles:
		best = minf(best, Vector2(p.x - c.x, p.z - c.z).length() - c.y)
	return best


## Golems never stand inside one another (user spec 2026-11-16): whichever
## level or tribe, two of them keep the sum of their body radii apart. While they
## overlap each steps away from the other — the smaller body yields more —, the
## pair at most at walking speed, and never onto ground it could not walk on. (The ordinary
## unit separation is switched off for golems from level 1 on, so they need their
## own.)
func _tick_golem_separation(delta: float) -> void:
	if not (path_service is UnitManager) or delta <= 0.0 or is_rooted():
		return   # (a sitting golem is not pushed: the other one yields all the way)
	var mine: float = collision_radius()
	var push: Vector2 = Vector2.ZERO
	for u in (path_service as UnitManager).vehicles:
		if u == self or not is_instance_valid(u) or not (u is Golem) or u.state == State.DEAD:
			continue
		var other: Golem = u as Golem
		var theirs: float = other.collision_radius()
		var need: float = _golem_need(other)
		var away: Vector2 = Vector2(position.x - other.position.x, position.z - other.position.z)
		var dist: float = away.length()
		if dist >= need:
			continue
		if dist < 0.001:
			# Exactly on top of each other: a fixed direction per pair, no dice.
			away = Vector2(1.0, 0.0) if get_instance_id() < other.get_instance_id() \
				else Vector2(-1.0, 0.0)
			dist = 0.0
		else:
			away /= dist
		# The pair closes its overlap at most at the faster one's walking speed, and
		# each takes its share of that: the bigger the OTHER body, the more she
		# yields — so a giant hardly moves for a small golem.
		var close: float = minf(need - dist, maxf(current_speed(), other.current_speed()) * delta)
		var share: float = 1.0 if other.is_rooted() else theirs / (mine + theirs)
		push += away * close * share
	if push == Vector2.ZERO:
		_tick_golem_yield(delta)
		return
	var next: Vector3 = Vector3(position.x + push.x, position.y, position.z + push.y)
	if not _can_be_pushed_to(next):
		return
	position = next
	_snap_to_ground()
	_sync_soa_pos()


## Distance at which this golem and `other` touch (centre to centre).
func _golem_need(other: Golem) -> float:
	return golem_pair_need(collision_radius(), height_m(), other.collision_radius(), other.height_m())


## Touching distance of two golems with body radii `ra`, `rb` and heights `ha`, `hb`: GOLEM_BODY_GAP of
## the sum of the radii — but a golem that reaches no higher than the other's knees
## (GOLEM_KNEE_HEIGHT_SHARE) only meets that one's legs: GOLEM_LEG_RADIUS_SHARE of its radius (user spec
## 2026-11-18). The same number for both of the pair.
static func golem_pair_need(ra: float, ha: float, rb: float, hb: float) -> float:
	if ha <= hb * Balance.GOLEM_KNEE_HEIGHT_SHARE:
		rb *= Balance.GOLEM_LEG_RADIUS_SHARE
	elif hb <= ha * Balance.GOLEM_KNEE_HEIGHT_SHARE:
		ra *= Balance.GOLEM_LEG_RADIUS_SHARE
	return (ra + rb) * Balance.GOLEM_BODY_GAP


## Is another golem (or a ground vehicle) standing right in her way toward `point`
## — touching her and ahead of her (within 60 degrees of the direction)? Then she
## does not shove it (user spec 2026-11-17): the attack is struck from the full
## reach.
func _golem_in_the_way(point: Vector3) -> bool:
	var dir: Vector2 = Vector2(point.x - position.x, point.z - position.z)
	if dir.length_squared() < 0.000001:
		return false
	dir = dir.normalized()
	var contact: float = maxf(Balance.GOLEM_CONTACT_MIN,
		trample_radius() * Balance.GOLEM_CONTACT_SHARE)
	for other in CrewedVehicle.big_bodies_near(self):
		var rel: Vector2 = Vector2(other.position.x - position.x, other.position.z - position.z)
		var d: float = rel.length()
		if d > CrewedVehicle.clearance(self, other) + contact or d < 0.001:
			continue
		if rel.dot(dir) / d >= 0.5:
			return true
	return false


## The goal of her march is taken by other golems or ground vehicles (her body
## would not fit there)
## and she is already close to it — closer than the blocker's touching distance
## plus GOLEM_BLOCKED_ARRIVE_BODIES of her own body radii (user spec 2026-11-17:
## near enough counts as arrived; she does not try to push them off the spot).
func blocked_goal_reached(goal: Vector3) -> bool:
	var to_goal: float = _flat_dist(position, goal)
	var slack: float = trample_radius() * Balance.GOLEM_BLOCKED_ARRIVE_BODIES
	for other in CrewedVehicle.big_bodies_near(self):
		var need: float = CrewedVehicle.clearance(self, other)
		if _flat_dist(goal, other.position) < need and to_goal <= need + slack:
			return true
	return false


## A march whose goal other golems occupy ends close to it (blocked_goal_reached).
func _tick_move(delta: float) -> void:
	if _pending_target == Vector3.INF and _has_path() \
			and blocked_goal_reached(_path[_path.size() - 1]):
		_clear_path()
		_on_path_finished()
		return
	super._tick_move(delta)


## Out of the way (user spec 2026-11-17): an idle, standing golem that another golem
## or a ground vehicle is marching into steps aside — across its course, toward the
## side she already leans to — instead of being shoved along in front of it
## (CrewedVehicle.yield_offset). Not when the walker wants to get to the very spot
## she stands on (it stops short, see blocked_goal_reached) or stops before it gets
## to her.
func _tick_golem_yield(delta: float) -> void:
	if state != State.IDLE or stance != STANCE_STAND or is_switching_stance() 			or is_stretching() or _pending_attack != &"":
		return
	var step_max: float = current_speed() * Balance.BODY_YIELD_SPEED_SHARE * delta
	for other in CrewedVehicle.big_bodies_near(self):
		var off: Vector2 = CrewedVehicle.yield_offset(self, other,
			CrewedVehicle.clearance(self, other), step_max)
		if off == Vector2.ZERO:
			continue
		for s in [1.0, -1.0]:
			var next: Vector3 = Vector3(position.x + off.x * s, position.y, position.z + off.y * s)
			if _can_be_pushed_to(next):
				position = next
				_snap_to_ground()
				_sync_soa_pos()
				return
		return


## May another golem push her onto this spot? Only where she could walk herself.
func _can_be_pushed_to(next: Vector3) -> bool:
	if terrain_data == null:
		return true
	if walks_straight():
		return giant_line_clear(terrain_data, position, next, giant_step_limit(), crosses_water())
	if crosses_water() and terrain_data.get_height(next.x, next.z) <= TerrainData.SEA_LEVEL + WATER_EPS:
		return giant_line_clear(terrain_data, position, next, giant_step_limit(), true)
	return nav_grid == null or nav_grid.is_cell_walkable(nav_grid.world_to_cell(next))


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
	if (state == State.MOVE and not move_aggressive) or is_sit_locked():
		return
	super._maybe_retaliate(attacker)


## Melee cannot reach flyers — _is_ranged() would otherwise let the base lock
## onto airborne targets.
func _begin_attack(enemy: Unit) -> void:
	if is_sit_locked():
		return   # seated (or on the way): no attacks in this first stage
	if enemy != null and is_instance_valid(enemy) and enemy.is_airborne():
		return
	# Out of a march (attack-move) or while already walking up to a target she
	# closes in; from a standstill she strikes at full reach (user spec 2026-11-17).
	var walking: bool = state == State.MOVE or (state == State.ATTACK and _closing_in)
	super._begin_attack(enemy)
	_closing_in = walking


## Lean attack loop without the group machinery: close to REACH, then attack on
## cooldown. Stays object-ticked (no SoA melee hold) — there are only ever a
## handful of golems.
##
## Target discipline (user feedback 2026-09-06): the golem does NOT run after a
## target it just hurled away while other enemies stand within reach — it turns
## on the nearest one in reach instead. Only when nobody is in reach does it
## chase; a target still in the air is waited for, not followed.
## That holds for targets she picked HERSELF. An ordered target (order_attack:
## player, AI) is kept and followed through the crowd (user report 2026-11-16).
##
## While an attack is wound up she stands and finishes it: no retargeting, no
## chasing in mid-swing.
func _tick_attack(delta: float) -> void:
	if _pending_attack != &"" or is_switching_stance() or is_stretching():
		_attack_cooldown -= delta
		return
	if not _unit_target_attackable(attack_target) or attack_target.tribe_id == tribe_id:
		_tick_no_unit_target(delta)
		return
	var target: Unit = attack_target
	if has_ordered_building() and not _near_ordered_building(target):
		_retarget_or_idle()   # it left the building's surroundings: next one there, or the building
		return
	var dist: float = _flat_dist(position, target.position)
	if dist > reach() or target.is_airborne():
		# An ORDERED target is kept (user report 2026-11-16: the order was ignored
		# while others fought around her — a golem is never tied down in melee):
		# she walks after it through the crowd. Only a target she picked herself
		# gives way to whoever stands in reach.
		var near: Unit = null if _target_ordered else _nearest_enemy_in_reach()
		if near != null and has_ordered_building() and not _near_ordered_building(near):
			near = null
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
		_closing_in = true   # she has to walk: she will close in to strike distance
		if not _approach(target.position, delta):
			_mark_target_unreachable(target)
			_retarget_or_idle()
			return
		_face_point(target.position)
		return
	if _keeps_closing_in(dist, target.position) and _approach(target.position, delta):
		_in_melee = false
		_attack_cooldown -= delta   # the next blow is ready when she gets there
		_face_point(target.position)
		return
	_closing_in = false
	if _has_path():
		_clear_path()
	_in_melee = true
	_face_point(target.position)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		if not is_turned_to_facing():
			# Still turning toward it (see turn_rate) — only the stomp needs
			# no aim and may come at once, when it is the best plan.
			_stomp_while_turning()
			return
		_attack_or_switch()


## Does she walk on although the target (`dist` away) is already within her reach?
## Only when she had to walk to it anyway (_closing_in), stands upright, it is
## still beyond strike_distance() and no other golem stands in her way — then the
## full reach will do (user spec 2026-11-17).
func _keeps_closing_in(dist: float, point: Vector3) -> bool:
	return _closing_in and stance == STANCE_STAND and dist > strike_distance() \
		and not _golem_in_the_way(point)


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
	if _pending_attack != &"" or is_switching_stance() or is_stretching():
		_attack_cooldown -= delta
		return
	var center: Vector3 = building.center_world()
	var flat: Vector2 = Vector2(position.x, position.z)
	var gap: float = building.footprint_distance_to(flat)
	if gap > reach() - 0.5:
		_in_melee = false
		_closing_in = true   # she has to walk: she will close in to strike distance
		# Never path onto the footprint itself (unwalkable): stop short of it.
		_approach(stand_off_point(position, center, reach() * APPROACH_RANGE_FRACTION), delta)
		_face_point(center)
		return
	# Closing in on the building: toward the nearest point of its footprint (the
	# A* goal snaps off the footprint itself).
	if _keeps_closing_in(gap + 0.5, center) \
			and _approach(stand_off_point(position, center, 0.0), delta):
		_in_melee = false
		_attack_cooldown -= delta
		_face_point(center)
		return
	_closing_in = false
	if _has_path():
		_clear_path()
	_in_melee = true
	_face_point(center)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		if not is_turned_to_facing():
			_stomp_while_turning(building)   # the stomp needs no aim
			return
		_attack_or_switch(building)


## True when the point at (along, side) in the heading frame lies inside the
## slam: the circle around the spot where the hands come down. `scale` = the
## golem's reach_factor() (1 = level 0) and sizes the circle; `limb` = her
## limb_factor() and says how far ahead the hands land (omitted: like `scale`).
static func in_slam_area(along: float, side: float, scale: float = 1.0,
		limb: float = -1.0) -> bool:
	var a: float = along - SLAM_FORWARD * (limb if limb > 0.0 else scale)
	var r: float = SLAM_RADIUS * scale
	return a * a + side * side <= r * r


## True when the point lies in the kick's lane: straight ahead of the golem and,
## for the backswing, a shorter stretch behind her.
## `scale` sizes the lane's width, `limb` its length (omitted: like `scale`).
static func in_kick_lane(along: float, side: float, scale: float = 1.0,
		limb: float = -1.0) -> bool:
	var long: float = limb if limb > 0.0 else scale
	return along >= -KICK_BACK * long and along <= KICK_LENGTH * long \
		and absf(side) <= KICK_HALF_WIDTH * scale


static func in_attack_area(kind: StringName, along: float, side: float,
		scale: float = 1.0, limb: float = -1.0) -> bool:
	if kind == ATTACK_KICK:
		return in_kick_lane(along, side, scale, limb)
	return in_slam_area(along, side, scale, limb)


static func attack_windup(kind: StringName) -> float:
	if kind == ATTACK_SWAT:
		return Balance.GOLEM_SWAT_WINDUP
	if kind == ATTACK_DRUM:
		return Balance.GOLEM_DRUM_HITS[0]
	if kind == ATTACK_STOMP:
		return Balance.GOLEM_STOMP_WINDUP   # the landing
	return Balance.GOLEM_KICK_WINDUP if kind == ATTACK_KICK else Balance.GOLEM_SLAM_WINDUP


## Playback speed of an attack animation: a bigger body swings slower (with the
## root of its size, like the stride) — but never so slow that the animation
## would outlast the attack's cooldown. At that limit one attack flows straight
## into the next; she no longer stands idle in between. The cooldown itself grows
## with the size (strike_cooldown), so the animations of a giant stretch further.
func attack_speed(kind: StringName) -> float:
	var slowest: float = float(CLIP_LENGTH.get(kind, STRIKE_COOLDOWN)) / clip_rate(kind) \
		/ cooldown_for(kind)
	return clampf(1.0 / sqrt(size_factor()), minf(slowest, 1.0), 1.0)


## Where in its clip an attack's impact lies (seconds, golem_bewegung.mjs) — only
## for attacks whose wind-up was tuned away from the clip afterwards.
const CLIP_IMPACT: Dictionary = {&"slam": 0.35}

## How much faster than the animation was built an attack's clip has to play so
## that its impact meets the wind-up (slam: 0,35 s in the clip, 0,3 s wind-up).
static func clip_rate(kind: StringName) -> float:
	if not CLIP_IMPACT.has(kind):
		return 1.0
	return float(CLIP_IMPACT[kind]) / attack_windup(kind)


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
	return is_giant()


## The tallest step the giant still takes: metres of height per metre of way.
func giant_step_limit() -> float:
	return height_m() * Balance.GOLEM_GIANT_STEP_SHARE


## True when a giant can walk the straight line from `from` to `to`: ground all
## the way (no void), never the sea, and no cliff taller than `max_step` metres
## within one metre of way. Buildings and the walkability grid are NOT asked —
## that is the point.
## `allow_water`: the sea does not stop the line (golems from 30 m on, user spec 2026-11-18).
static func giant_line_clear(td: TerrainData, from: Vector3, to: Vector3,
		max_step: float, allow_water: bool = false) -> bool:
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
		if h <= TerrainData.SEA_LEVEL + WATER_EPS and not allow_water:
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
	var wet: bool = crosses_water() and terrain_data.has_ground(target.x, target.z) \
		and terrain_data.get_height(target.x, target.z) <= TerrainData.SEA_LEVEL + WATER_EPS
	if nav_grid != null and not wet:   # (from 30 m a goal in the water stays where it is)
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
		if giant_line_clear(terrain_data, anchor, path[last], limit, crosses_water()):
			far = last
		else:
			var lo: int = i
			var hi: int = last - 1
			while lo < hi:
				var mid: int = (lo + hi + 1) / 2
				if giant_line_clear(terrain_data, anchor, path[mid], limit, crosses_water()):
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
	if (walks_straight() or crosses_water()) and terrain_data != null:
		var goal: Vector3 = _giant_goal(target)
		if _straight_ok(position, goal):
			_clear_soa_hold()
			_pending_target = Vector3.INF   # cancels a queued request, like set_path
			_path = PackedVector3Array([goal])
			_path_index = 0
			_set_state(State.MOVE)
			return
	super._start_path_to(target)


func _plan_path_to(target: Vector3, allow_partial: bool = false) -> bool:
	if not (walks_straight() or crosses_water()) or terrain_data == null:
		return super._plan_path_to(target, allow_partial)
	var goal: Vector3 = _giant_goal(target)
	if _straight_ok(position, goal):
		_path = PackedVector3Array([goal])
		_path_index = 0
		return true
	if not super._plan_path_to(target, allow_partial):
		return false
	if not walks_straight():
		return true
	_path = _straighten(_path)
	_path_index = 0
	return true


## May she take the straight line from `a` to `b`? The giant always when it is clear (from 30 m
## also through water); a golem of 30 m or more that does not walk straight otherwise (the genesis
## golem) only where the line crosses water — on land she keeps her paths.
func _straight_ok(a: Vector3, b: Vector3) -> bool:
	if not giant_line_clear(terrain_data, a, b, giant_step_limit(), crosses_water()):
		return false
	return walks_straight() or line_touches_water(terrain_data, a, b)


## Does the straight line from `a` to `b` run over water anywhere (sampled every metre)?
static func line_touches_water(td: TerrainData, a: Vector3, b: Vector3) -> bool:
	var d: float = Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var n: int = maxi(1, int(ceil(d)))
	for i in range(n + 1):
		var p: Vector3 = a.lerp(b, float(i) / float(n))
		if td.get_height(p.x, p.z) <= TerrainData.SEA_LEVEL + WATER_EPS:
			return true
	return false


## A path from the PathWorker (the game's path queue). It starts with the centre
## of the cell she stands in — the synchronous planner drops that point
## (_trim_own_cell_waypoint), this route did not. Standing off-centre, the point
## lies BEHIND or beside her, and with her slow turn the body first swung up to
## 170 degrees the wrong way before it turned toward the goal (user report
## 2026-11-16). Dropped here as well.
func _apply_worker_path(request_id: int, cells: PackedVector2Array) -> void:
	super._apply_worker_path(request_id, cells)
	if _has_path() and _path_index == 0:
		_path = _trim_own_cell_waypoint(_path)
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
			giant_step_limit(), crosses_water()):
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
	if not can_strike_air() or is_sit_locked():
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
	if is_sit_locked():
		# Seated: only stand_up() reaches her — unless she may crab-walk (user spec 2026-11-18).
		if crab_ready():
			_crab_focus = null
			crab_to(target, null)
		return
	if not _own_order:
		_chase_ship = null
	_ordered_building = null
	super.order_move(target, queue_up, aggressive)


func order_attack(enemy: Unit) -> void:
	if is_sit_locked():
		if crab_ready() and enemy != null and is_instance_valid(enemy) and enemy.tribe_id != tribe_id:
			_crab_focus = enemy   # crawl within reach, sit down, strike (user spec 2026-11-18)
			crab_to(Vector3.INF, enemy)
		return
	_chase_ship = null
	_ordered_building = null
	super.order_attack(enemy)


func order_attack_building(building) -> void:
	if is_sit_locked():
		if crab_ready() and building != null and is_instance_valid(building) and building.tribe_id != tribe_id:
			_crab_focus = building
			crab_to(Vector3.INF, building)
		return
	_chase_ship = null
	var walking: bool = state == State.MOVE or (state == State.ATTACK and _closing_in)
	super.order_attack_building(building)
	_ordered_building = attack_building if attack_building == building else null
	_closing_in = walking


## EXPLICIT BUILDING ORDER (user report 2026-11-16): sent against a building she
## still went for units that did not stand anywhere near it — the base takes any
## enemy in the aggro radius (for her up to 60 m). While the ordered building
## stands she only fights units in reach OF THE BUILDING (footprint distance up to
## her reach: the ones she strikes from her place there anyway); the others she
## lets be. A unit that moves out of that range is dropped, and she goes back to
## the building. A building she picked herself keeps the old rule (units first).
func has_ordered_building() -> bool:
	if _ordered_building == null:
		return false
	if attack_building != _ordered_building or not _building_target_valid():
		_ordered_building = null
		return false
	return true


## Is `u` within her reach of the ordered building's footprint?
func _near_ordered_building(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and has_ordered_building() \
		and _ordered_building.footprint_distance_to(Vector2(u.position.x, u.position.z)) <= reach()


## Nearest enemy unit she may fight during the ordered assault (see above), or null.
func _enemy_near_ordered_building() -> Unit:
	if path_service == null:
		return null
	var b = _ordered_building
	var centre: Vector3 = b.center_world()
	var half: float = Vector2(b.footprint.x, b.footprint.y).length() * 0.5 * TerrainData.CELL_SIZE
	var best: Unit = null
	var best_d: float = INF
	for u in path_service.get_units_in_radius(centre, half + reach()):
		if u == self or u.tribe_id == tribe_id or u.state == State.DEAD or u.state == State.SIT:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue
		if not _near_ordered_building(u):
			continue
		var d: float = _flat_dist(position, u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


## The base's enemy scan (assault fallback, retargeting) — during the ordered
## assault only units near the building count.
func _scan_for_enemy(radius: float, max_examined: int = 0) -> Unit:
	if is_sit_locked():
		return null
	if has_ordered_building():
		return _enemy_near_ordered_building()
	return super._scan_for_enemy(radius, max_examined)


## Retargeting after a fight: during the ordered assault no "fight on against my
## own attackers" (they may stand anywhere) — the next unit near the building,
## else back to the building.
func _retarget_or_idle() -> void:
	if not has_ordered_building():
		super._retarget_or_idle()
		return
	_end_attack()
	var enemy: Unit = _enemy_near_ordered_building()
	if enemy != null:
		_begin_attack(enemy)
		return
	_set_state(State.ATTACK)


## Winds up the upward strike at `ship`.
func _swat(ship: Airship) -> void:
	_face_point(ship.position)
	_wind_up(ATTACK_SWAT, null, ship)


## Swats at an airship in reach while NOT in the melee loop (idle, walking,
## closing in on something) — in melee the attack loop does it on its own
## cooldown. One shared cadence: _wind_up resets _air_cooldown.
func _tick_air_strike(delta: float) -> void:
	_air_cooldown = maxf(_air_cooldown - delta, 0.0)
	if _air_cooldown > 0.0 or _pending_attack != &"" or not can_strike_air() or is_sit_locked():
		return
	if stance != STANCE_STAND or is_switching_stance() or is_stretching() or _stretch_queued:
		return   # the strike at an airship is a standing one; a stretch goes first
	if state == State.ATTACK and _in_melee:
		return
	var ship: Airship = _airship_in_reach()
	if ship != null:
		_swat(ship)


## Heading frame of the golem: [forward, right], flat in XZ.
func _heading_frame() -> Array[Vector3]:
	var forward: Vector3 = heading()   # where the body really points
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
	for u in path_service.get_units_in_radius(position, _hit_zone_reach(kind)):
		if u == self or u.state == State.DEAD or u.tribe_id == tribe_id:
			continue
		if not u.is_targetable() or u.is_airborne() or u is CrewedVehicle:
			continue   # protected reserves, flyers, and devices (no HP) are out
		if _in_hit_zone(kind, u.position, forward, right):
			out.append(u)
	return out


## Radius around the golem that contains the whole hit zone of `kind` (broad phase).
func _hit_zone_reach(kind: StringName) -> float:
	var size: float = reach_factor()
	if kind == ATTACK_KICK:
		var ext: Vector2 = _kick_extent()
		return Vector2(maxf(ext.x, ext.y), KICK_HALF_WIDTH * size + kick_leg_offset()).length() + 0.5
	if kind == ATTACK_STOMP:
		return stomp_radius() + 0.5
	return maxf(SLAM_FORWARD * limb_factor() + ground_radius(kind), trample_radius()) + 0.5


## How far the kick's lane reaches ahead (x) and behind her (y): its own length,
## but never shorter than her body — the lane always runs through the whole body
## circle. (Only matters late in the growth beyond level 7, when the body
## outgrows the slowly growing lane.) Its length follows kick_limb_factor.
func _kick_extent() -> Vector2:
	var long: float = kick_limb_factor()   # the leg's length, not the lane's width
	var body: float = trample_radius()
	var front: float = Balance.GOLEM_BODY_KICK_FRONT_SHARE if body_scaled() else 1.0   # 2026-11-18
	return Vector2(maxf(KICK_LENGTH * long * front, body), maxf(KICK_BACK * long, body))


## Is this point struck by the attack `kind`? (User spec 2026-11-15.)
##  * KICK: the lane of the kicking leg (kick_side, offset kick_leg_offset), nothing else —
##    it runs through her body circle, but it is NOT widened to the body there.
##  * SLAM: the circle around the hands, nothing else (since 2026-11-18 without the front
##    half of her body circle — the circle grows with the body from 30 m on).
##  * STOMP: the circle around her own centre (stomp_radius), all around.
func _in_hit_zone(kind: StringName, point: Vector3, forward: Vector3, right: Vector3) -> bool:
	var rel: Vector3 = point - position
	if kind == ATTACK_STOMP:
		return rel.x * rel.x + rel.z * rel.z <= stomp_radius() * stomp_radius()
	var along: float = rel.x * forward.x + rel.z * forward.z
	var side: float = rel.x * right.x + rel.z * right.z
	if kind == ATTACK_KICK:
		var ext: Vector2 = _kick_extent()
		return along >= -ext.y and along <= ext.x \
			and absf(side - kick_side * kick_leg_offset()) <= KICK_HALF_WIDTH * reach_factor() + Balance.GOLEM_KICK_LANE_SLACK
	return in_slam_area(along, side, slam_scale() * _ground_factor(kind), limb_factor())


## What ONE landing of the attack `kind` strikes, after the target cap
## (max_targets): {"units", "vehicles", "buildings"}. Units go before vehicles
## and buildings, within each the nearest to the blow first. The target she is
## attacking — unit or building — is always struck and counts toward the cap.
func _struck_targets(kind: StringName) -> Dictionary:
	var room: int = max_targets_of(kind)
	var units: Array[Unit] = _ordered_victims(kind)
	var buildings: Array = _buildings_in_area(kind)
	var prime_building = null
	if _building_target_valid() and buildings.has(attack_building):
		prime_building = attack_building
		buildings.erase(prime_building)
		room -= 1
	if units.size() > room:
		units.resize(maxi(room, 0))
	room -= units.size()
	var vehicles: Array = _vehicles_in_area(kind)
	if vehicles.size() > room:
		vehicles.resize(maxi(room, 0))
	room -= vehicles.size()
	if buildings.size() > room:
		buildings.resize(maxi(room, 0))
	if prime_building != null:
		buildings.push_front(prime_building)
	return {"units": units, "vehicles": vehicles, "buildings": buildings}


## Every unit in the area of the attack `kind`, in the order the cap picks them:
## the current target first, then the nearest to the point of impact.
func _ordered_victims(kind: StringName) -> Array[Unit]:
	var origin: Vector3 = position
	if kind != ATTACK_KICK and kind != ATTACK_STOMP:
		origin += _heading_frame()[0] * (SLAM_FORWARD * limb_factor())
	var units: Array[Unit] = _victims(kind)
	units.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _flat_dist(a.position, origin) < _flat_dist(b.position, origin))
	if state == State.ATTACK and _target_valid(attack_target) and units.has(attack_target):
		units.erase(attack_target)
		units.push_front(attack_target)
	return units


## Enemy buildings the attack `kind` would strike right now.
func _buildings_in_area(kind: StringName) -> Array:
	var out: Array = []
	if building_manager == null:
		return out
	var forward: Vector3 = _heading_frame()[0]
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		if b.tribe_id == tribe_id or not b.is_attackable():
			continue
		if _building_in_area(b, kind, forward):
			out.append(b)
	return out


## Whether the giant's blows and feet wreck this vehicle (maximum level only):
## every GROUND vehicle that does not fly his own tribe's flag — manned or
## abandoned. Vehicles under his own flag are always spared, also while their
## crew fights on foot beside them or before a crew has arrived (ownership
## follows the crew, so an abandoned ENEMY vehicle keeps the enemy flag).
## Airships fly above feet and ground blows; the swat is theirs.
func crushes_vehicle(v) -> bool:
	if not is_giant() or not (v is CrewedVehicle) or v is Airship:
		return false
	if not is_instance_valid(v) or v.state == State.DEAD:
		return false
	return v.tribe_id != tribe_id


## Ground vehicles the attack `kind` would wreck right now (see crushes_vehicle).
func _vehicles_in_area(kind: StringName) -> Array:
	var out: Array = []
	if not is_giant() or path_service == null:
		return out
	var frame: Array[Vector3] = _heading_frame()
	for u in path_service.get_units_in_radius(position, _hit_zone_reach(kind)):
		if u != self and crushes_vehicle(u) and _in_hit_zone(kind, u.position, frame[0], frame[1]):
			out.append(u)
	return out


## One blow or one step on a vehicle: its own damage steps apply (catapult gone
## at once, fire ram three lives). A wrecked vehicle counts as ONE kill.
func _crush_vehicle(v) -> void:
	(v as CrewedVehicle).take_crush_hit(position)
	if not is_instance_valid(v) or v.state == State.DEAD:
		_credit_kill()


## Slam when a crowd stands around her, kick otherwise (single targets and
## buildings): the kick hurts more but only clears a lane.
##
## Everything the slam would strike counts — units, enemy BUILDINGS and (for the
## giant) vehicles: three huts around her are a crowd too (user report
## 2026-11-15: she only ever kicked buildings, one at a time).
##
## Since 2026-11-16 by DAMAGE (user spec): the attack with the highest expected
## damage per second wins (attack_value) — what it would strike right now, without
## overkill, over the time it costs including a share of a stance switch. A tie
## goes to the attack of the current stance, otherwise to the kick; with nothing
## to strike at all she kicks.
##
## With the stomp (2026-11-16) the same comparison reads as PLANS — a lead-in
## plus GOLEM_STANCE_PLAN_ATTACKS attacks, valued by damage per second over the
## whole plan (attack_value): no lead-in (the attack of the stance she is in), a
## stance switch (costs time, brings nothing), or — standing only — the stomp
## (costs its cooldown, brings its own damage, and ends crouched). The returned
## kind is what she does FIRST; the stomp comes last in the order, so a tie goes
## to the plain attacks.
func _choose_attack() -> StringName:
	var order: Array[StringName] = [ATTACK_KICK, ATTACK_SLAM, ATTACK_DRUM]
	if stance == STANCE_CROUCH:
		order = [ATTACK_SLAM, ATTACK_DRUM, ATTACK_KICK]
	elif can_stomp():
		order.append(ATTACK_STOMP)
	var best: StringName = ATTACK_KICK
	var best_value: float = 0.0
	for kind in order:
		var value: float = attack_value(kind)
		if value > best_value + 0.0001:
			best = kind
			best_value = value
	return best


## The clip an attack plays. The kick alternates its leg; the strike at an
## airship follows the ship's height against her body (see GOLEM_AIR_*_SHARE).
## A model without the extra clips falls back on the plain one.
func _clip_for(kind: StringName, ship: Airship = null) -> StringName:
	var clip: StringName = kind
	if kind == ATTACK_SLAM:
		clip = CLIP_SLAM_LOW
	elif kind == ATTACK_DRUM:
		clip = CLIP_DRUM_LOW
	elif kind == ATTACK_KICK:
		clip = ATTACK_KICK if kick_side > 0.0 else CLIP_KICK_LEFT   # right leg: kick, left: kick_l
	elif kind == ATTACK_SWAT and ship != null and is_instance_valid(ship):
		var share: float = (ship.position.y - position.y) / maxf(height_m(), 0.01)
		if share < Balance.GOLEM_AIR_LOW_SHARE:
			clip = _next_kick_clip()
		elif share < Balance.GOLEM_AIR_HIGH_SHARE:
			clip = CLIP_SWIPE
	if _anim != null and not _anim.has_animation(clip):
		return kind
	return clip


func _next_kick_clip() -> StringName:
	_kick_left = not _kick_left
	return ATTACK_KICK if _kick_left else CLIP_KICK_LEFT


## Begins an attack: the animation starts now, the damage lands after the
## wind-up (_tick_pending_attack). `building` = the assault target, if any.
func _wind_up(kind: StringName, building = null, ship: Airship = null) -> void:
	# Called directly (tests, the swat) the stance simply follows the attack.
	if not is_switching_stance() and stance != stance_for(kind):
		stance = stance_for(kind)
		_stance_age = 0.0
	if kind == ATTACK_KICK:
		if not _kick_leg_locked:
			_pick_kick_leg()   # the leg that strikes more (its lane is fixed until it lands)
		_kick_leg_locked = false
		_last_kick_side = kick_side
	_pending_attack = kind
	_pending_time = current_windup(kind)
	_pending_hit = 0
	_pending_building = building
	_pending_airship = ship
	# One shared cadence: whatever she strikes with, the next attack — on the
	# ground or at an airship — waits for this attack's cooldown.
	_attack_cooldown = cooldown_for(kind)
	_air_cooldown = cooldown_for(kind)
	attack_anim = kind
	anim_base_name = attack_anim
	anim_start_ms = Time.get_ticks_msec()
	_arm_anim = 0.0
	_no_combat_timer = 0.0
	var clip: StringName = _clip_for(kind, ship)
	var rate: float = attack_speed(kind) * clip_rate(kind)
	_attack_anim_left = float(CLIP_LENGTH.get(kind, 0.0)) / rate
	_play_clip(clip, rate, true)


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
	# The drum lands three times; she stays wound up until the last hit.
	if kind == ATTACK_DRUM and _pending_hit < Balance.GOLEM_DRUM_HITS.size() - 1:
		_land_attack(kind, _pending_hit)
		_pending_time += (Balance.GOLEM_DRUM_HITS[_pending_hit + 1]
			- Balance.GOLEM_DRUM_HITS[_pending_hit]) / attack_speed(kind)
		_pending_hit += 1
		return
	_pending_attack = &""
	_pending_building = null
	_pending_airship = null
	if kind == ATTACK_SWAT:
		_land_swat(ship)
		return
	var struck: Dictionary = _land_attack(kind, _pending_hit)
	if building != null and is_instance_valid(building) and building.health > 0 \
			and not struck.has(building) and state == State.ATTACK \
			and attack_building == building and kind != ATTACK_STOMP:
		_strike_building(building, building_damage_for(drum_hit_damage(Balance.GOLEM_DRUM_HITS.size() - 1)
			if kind == ATTACK_DRUM else attack_damage(kind)))   # (the stomp only strikes what stands around her)


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
	_play_strike_sfx(ATTACK_SWAT)
	ship.register_hull_hit(position)
	return true


## Sound of an attack landing: every attack has its own key (golem_kick,
## golem_slam, golem_drum — once per hit —, golem_swat). As long as its file is
## missing the common golem_strike plays instead.
const STRIKE_SFX: Dictionary = {
	&"kick": &"golem_kick", &"slam": &"golem_slam", &"drum": &"golem_drum", &"swat": &"golem_swat",
	&"stomp": &"golem_stomp"}

static func strike_sfx_key(kind: StringName) -> StringName:
	return STRIKE_SFX.get(kind, &"golem_strike")


func _play_strike_sfx(kind: StringName) -> void:
	if not _audio_checked:
		_audio_checked = true
		if is_inside_tree():
			_audio_node = get_node_or_null("/root/AudioManager")
	if _audio_node == null:
		return
	var key: StringName = strike_sfx_key(kind)
	if not _audio_node.has_sfx(key):
		key = &"golem_strike"
	_audio_node.play_sfx(key, position, 200)


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
##
## The DRUM lands three times (`hit` 0..2): each hit deals its share of the
## damage to the units in the slam's area; only the LAST one throws them and
## strikes vehicles and buildings.
##
## The STOMP lands around her own centre, throws nobody — and leaves her
## crouched (_tick_stance decides what follows once its clip has settled).
func _land_attack(kind: StringName, hit: int = 0) -> Dictionary:
	_no_combat_timer = 0.0
	_play_strike_sfx(kind)
	var frame: Array[Vector3] = _heading_frame()
	var forward: Vector3 = frame[0]
	var kick: bool = kind == ATTACK_KICK
	var drum: bool = kind == ATTACK_DRUM
	var stomp: bool = kind == ATTACK_STOMP
	if stomp:
		stance = STANCE_CROUCH
		_stance_target = STANCE_CROUCH
		_stance_age = 0.0
		_stomp_landed = true
	var last_hit: bool = not drum or hit >= Balance.GOLEM_DRUM_HITS.size() - 1
	var damage: int = drum_hit_damage(hit) if drum else attack_damage(kind)
	# Everything struck is collected first: a kill can raise the level, and the
	# area and the target cap of THIS attack must not grow while it lands.
	var struck: Dictionary = _struck_targets(kind)
	for u in struck.units:
		var hp: int = kill_hp_of(u)
		u.take_damage(damage, self)
		if not is_instance_valid(u) or u.state == State.DEAD or u.doomed:
			_credit_kill(hp)
			continue
		if kick:
			# Thrown or not: the size decides (kick_throw_chance). No dice at 0 or
			# 100 percent — the seeded random stream stays as it was there.
			var throw_chance: float = kick_throw_chance()
			if throw_chance <= 0.0 or (throw_chance < 1.0 and randf() >= throw_chance):
				continue
			# In front she kicks them away forward; whoever the backswing catches
			# behind her flies off backward.
			var rel: Vector3 = u.position - position
			var ahead: bool = rel.x * forward.x + rel.z * forward.z >= 0.0
			u.apply_lift(forward if ahead else -forward,
				Balance.GOLEM_KICK_PUSH, Balance.GOLEM_KICK_UP)
			continue
		if not last_hit or stomp:
			continue   # the drum's first two hits and the stomp only hurt
		# Whirled up, rolled or only hurt: one roll of the dice against the chances of
		# her size (the drum never throws) — and none at all where both are 0.
		var lift_chance: float = 0.0 if drum else slam_lift_chance()
		var roll_chance: float = drum_roll_chance() if drum else slam_roll_chance()
		if lift_chance + roll_chance <= 0.0:
			continue
		var away: Vector3 = Vector3(u.position.x - position.x, 0.0,
			u.position.z - position.z)
		var dice: float = 0.0 if lift_chance + roll_chance >= 1.0 and lift_chance <= 0.0 else randf()
		match Fireball.impact_outcome(dice, lift_chance, roll_chance):
			Fireball.OUTCOME_LIFT:
				u.apply_lift(away, Balance.GOLEM_LIFT_PUSH, Balance.GOLEM_LIFT_UP)
			Fireball.OUTCOME_ROLL:
				if away.length_squared() < 0.000001:
					away = forward
				u.start_roll(away.normalized(), Balance.GOLEM_ROLL_DURATION,
					Balance.GOLEM_ROLL_SPEED)
	# Buildings lose hit points with every hit — the drum's three as well (2026-11-18).
	var struck_buildings: Dictionary = {}
	var to_building: int = building_damage_for(damage)
	for b in struck.buildings:
		if not is_instance_valid(b) or b.health <= 0:
			continue
		struck_buildings[b] = true
		_strike_building(b, to_building)
	if not last_hit:
		return struck_buildings
	# The giant's blows wreck vehicles too.
	for v in struck.vehicles:
		_crush_vehicle(v)
	return struck_buildings


## `amount` hit points off a building (since 2026-11-18 its stages fall by hit points, as under
## every other attacker). A building the golem brings down counts as ONE kill, like a unit (user
## spec 2026-11-15).
func _strike_building(b, amount: int) -> void:
	b.take_damage(amount)
	if not is_instance_valid(b) or b.health <= 0:
		_credit_kill()


## One whole destruction stage of `b` in hit points (a construction site: all it has — sites are
## fragile, as under the spells).
static func _stage_hp(b) -> int:
	if b.under_construction:
		return maxi(b.health, 1)
	return int(ceil(Building.STAGE_DAMAGE * float(b.max_health)))


## Does the attack's area touch the building's footprint? Slam: the footprint
## comes within the radius of the impact point. Kick: centreline samples along
## the lane, each with the lane's half-width (like the fire ram's blast).
func _building_in_area(b, kind: StringName, forward: Vector3) -> bool:
	var size: float = reach_factor()
	if kind == ATTACK_STOMP:
		return Balance.GOLEM_STOMP_BUILDING_STAGES > 0 \
			and b.footprint_distance_to(Vector2(position.x, position.z)) <= stomp_radius()
	if kind != ATTACK_KICK:
		var hit: Vector3 = position + forward * (SLAM_FORWARD * limb_factor())
		return b.footprint_distance_to(Vector2(hit.x, hit.z)) <= ground_radius(kind)
	var ext: Vector2 = _kick_extent()
	var along: float = -ext.y + 0.5
	var leg: Vector3 = Vector3(-forward.z, 0.0, forward.x) * (kick_side * kick_leg_offset())   # the kicking leg's lane
	while along < ext.x:
		var sample: Vector3 = position + forward * along + leg
		if b.footprint_distance_to(Vector2(sample.x, sample.z)) <= KICK_HALF_WIDTH * size:
			return true
		along += 1.0
	return false


# --- Visuals (own 3D model, in-game only) -------------------------------------------

func _ready() -> void:
	_create_model()
	_refresh_flag_color()


## BUILD of the figure (2026-11-16): the base golem's is fixed; the demon golem
## (DemonGolem) brings its own model, is stockier and starts smaller.
## File of the model under assets/.
func model_file() -> String:
	return "models/units/golem.glb"


## Scale of the 4-m model at size factor 1.
func model_scale() -> Vector3:
	return Vector3(MODEL_SCALE, MODEL_SCALE_Y, MODEL_SCALE)


## Half the body box at size factor 1 (selection, shadow, trample radius).
func body_half_width() -> float:
	return BODY_HALF_WIDTH


func body_half_depth() -> float:
	return BODY_HALF_DEPTH


## Ground covered by one loop of the walk clip at size factor 1 (metres).
func walk_clip_speed() -> float:
	return WALK_CLIP_SPEED


## How deep under the ground the figure starts when it is summoned.
func rise_depth() -> float:
	return RISE_DEPTH


## User-provided model (assets/models/units/golem.glb) when present: built
## MODEL_HEIGHT (4 m) tall — scaled here to Balance.GOLEM_HEIGHT —, front +Z,
## origin at the feet. Optional parts: an AnimationPlayer with the
## clips idle / walk / slam / kick / death, a MeshInstance3D "Flag" that takes
## the tribe colour, a Node3D "Arm" that swings on an attack (models without
## clips). Otherwise a blocky stone figure of the same size.
func _create_model() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Model"
	root.scale = model_scale() * _shown_size   # (1 for the base golem; the demon golem starts small)
	add_child(root)
	_model = root
	var custom: Node3D = AssetLibrary.instantiate_model(model_file())
	if custom != null:
		root.add_child(custom)
		_arm = custom.find_child("Arm", true, false) as Node3D
		_flag_mesh = custom.find_child("Flag", true, false) as MeshInstance3D
		_anim = custom.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_prepare_clips()
		if _anim != null:
			_sit_anim = GolemSitAnim.new(_anim)
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
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_CROUCH_IDLE, CLIP_SIT_IDLE, GolemSitAnim.CLIP_TURN_L, GolemSitAnim.CLIP_TURN_R,
			CLIP_CRAB_IDLE, CLIP_CRAB_WALK]:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play_clip(CLIP_IDLE)


## The clip under the sit layers: sit_idle, while turning sit_turn_l / sit_turn_r.
func _sit_base_clip() -> StringName:
	if not is_sit_turning():
		return CLIP_SIT_IDLE
	var h: Vector3 = heading()
	var diff: float = wrapf(atan2(facing.x, facing.z) - atan2(h.x, h.z), -PI, PI)
	return GolemSitAnim.CLIP_TURN_L if diff > 0.0 else GolemSitAnim.CLIP_TURN_R


## The clip she dies with: seated or in the crab stand sit_death (user spec 2026-11-18), else death.
func death_clip() -> StringName:
	if stance == STANCE_SIT and _anim != null and _anim.has_animation(CLIP_SIT_DEATH):
		return CLIP_SIT_DEATH
	return CLIP_DEATH


## The crab walk's clips: crab_up / crab_down stretched to their time, in the stand crab_walk by the
## real speed (CRAB_CLIP_STRIDE per loop, or the hands and feet slide) or crab_idle; the strike at
## an airship (crab_swat) plays out first.
func _crab_visual(ground_speed: float) -> void:
	match _crab:
		CRAB_UP:
			_play_clip(CLIP_CRAB_UP, CRAB_CLIP_LENGTH / crab_switch_time())
		CRAB_DOWN:
			_play_clip(CLIP_CRAB_DOWN, CRAB_CLIP_LENGTH / crab_switch_time())
		_:
			if _clip == CLIP_CRAB_SWAT and _anim.is_playing():
				return
			if ground_speed > WALK_THRESHOLD:
				_play_clip(CLIP_CRAB_WALK, ground_speed / (crab_clip_speed() * _shown_size))
			else:
				_play_clip(CLIP_CRAB_IDLE)


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
		Vector2(body_half_width() * 2.6, body_half_depth() * 2.8) / model_scale().x)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.04 / model_scale().x
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
			# Seated or in the crab stand she dies sitting (sit_death); the model keeps its
			# seated offset. The layer tree hands the figure back to the player first.
			if _sit_anim != null and _sit_anim.is_active():
				_sit_anim.set_active(false)
			_play_clip(death_clip(), 1.0, true)
		_dead_time += delta
		# With a collapse clip the body falls first and sinks afterwards.
		if _dead_time >= SINK_DELAY or (_clip != CLIP_DEATH and _clip != CLIP_SIT_DEATH):
			position.y -= SINK_SPEED * delta
		return
	var body_dir: Vector3 = heading()
	rotation.y = atan2(body_dir.x, body_dir.z)
	if _model != null:
		# Seated, her logic position lies on the seat: the figure (origin at the
		# feet) is drawn that far forward again (_on_seated).
		_model.position.z = seat_back_m() * _shown_size / size_factor() \
			if _seat_center != Vector3.INF else 0.0
	# A level-up lets the figure grow over about a second.
	if _model != null and not is_equal_approx(_shown_size, size_factor()):
		_shown_size = move_toward(_shown_size, size_factor(), delta * GROW_SPEED)
		_model.scale = model_scale() * _shown_size
	if _rise < 1.0 and _model != null:
		_rise = minf(_rise + delta / RISE_TIME, 1.0)
		var left: float = 1.0 - _rise
		_model.position.y = -rise_depth() * left * left
	var ground_speed: float = 0.0
	if _last_pos != Vector3.INF and delta > 0.0:
		ground_speed = Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / delta
	_last_pos = position
	if _anim != null:
		# An attack clip plays out; afterwards walk or idle by the real speed.
		var attacking: bool = ATTACK_CLIPS.has(_clip) and _anim.is_playing()
		var layered: bool = _sit_anim != null and _sit_anim.usable() \
			and stance == STANCE_SIT and not is_switching_stance() and not is_crabbing()
		if _sit_anim != null and _sit_anim.is_active() != layered:
			_sit_anim.set_active(layered)
			if not layered:
				_clip = &""   # the player takes over again: replay its clip
		if layered:
			_sit_anim.set_base(_sit_base_clip())
		elif not attacking and not is_switching_stance() and not is_stretching():
			if is_crabbing():
				_crab_visual(ground_speed)
			elif stance == STANCE_SIT:
				_play_clip(CLIP_SIT_IDLE)
			elif stance == STANCE_CROUCH:
				_play_clip(CLIP_CROUCH_IDLE)
			elif ground_speed > WALK_THRESHOLD:
				# A bigger body covers more ground per stride.
				_play_clip(CLIP_WALK, ground_speed / (walk_clip_speed() * _shown_size))
			else:
				_play_clip(CLIP_IDLE)
	if _arm != null and _arm_anim < 1.0:
		_arm_anim = minf(_arm_anim + delta * 2.0, 1.0)
		# Raise, then slam down and settle: a half sine over the swing.
		_arm.rotation.x = -sin(_arm_anim * PI) * 1.3
