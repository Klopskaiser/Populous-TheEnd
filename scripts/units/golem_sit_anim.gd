class_name GolemSitAnim extends RefCounted

## ANIMATIONSEBENEN IM SITZEN (Vorarbeit 2026-11-17, plans/10l_golem_sitting.md):
## im Stand spielt der Golem genau einen Clip auf seinem AnimationPlayer. Im Sitzen
## greifen Beine und Arme UNABHAENGIG an — dafuer baut diese Klasse einen
## AnimationTree ueber denselben Player:
##
##   Grundclip (sit_idle, beim Drehen sit_turn_l / sit_turn_r)
##     -> KAMPFRUHE BEINE / ARME (Blend2 mit Filter, 2026-11-19): im Kampf halten Beine bzw. Arme
##        mit Nacken, Kopf und Oberkoerper die Ruhehaltung (erstes Bild von sit_idle) statt sit_idle
##        zu spielen — zwischen zwei Angriffen zuckte sonst der Kopf in die Idle-Bewegung und wurde
##        beim naechsten Angriff wieder herausgerissen (Nutzermeldung). Gesteuert von
##        GolemSitCombat.rest_wanted, weich ein- und ausgeblendet (REST_FADE_IN / _OUT).
##     -> Ebene BEINE  (OneShot, nur die Beinknochen: *UpperLeg, *LowerLeg, *Foot, *Toes)
##     -> Ebene ARME   (OneShot, nur Schulter, Ober-/Unterarm, Hand und Finger — und
##                      seit 2026-11-17 Nacken und Kopf: beim Wischer wendet sie den
##                      Kopf zur Seite des Arms)
##     -> Ebene ARME+OBERKOERPER (OneShot: beide Arme, Spine/Chest/UpperChest, Nacken, Kopf —
##                      der seitliche Handschlag, 2026-11-18: sie lehnt sich auf die Stuetzhand
##                      zurueck, neigt sich zur Schlagseite; laeuft im Arm-Kanal wie der Wischer)
##     -> Ebene KOERPER (OneShot ohne Filter: Po-Huepfer, Doppelklatscher, Doppelstampfer)
##     -> Ausgabe
##
## Jede Ebene hat ihr eigenes Tempo (TimeScale), damit der Aufschlag im Clip auf die
## Ausholzeit des Spiels faellt (SIT_CLIP_IMPACT). Welche Spuren zu Beinen und Armen
## gehoeren, liest sie aus den Spuren des Clips sit_idle (Knochennamen nach VRM).
##
## Der Baum wird nur aktiv, solange sie sitzt UND das Modell wenigstens einen der
## Sitzangriffs- oder Drehclips hat (usable()) — ohne diese Clips bleibt alles beim
## einfachen Player (sit_idle wie bisher).

const LAYER_LEGS: int = 0
const LAYER_ARMS: int = 1
const LAYER_FULL: int = 2
const LAYER_ARM_TORSO: int = 3
const LAYER_NAMES: Array[String] = ["legs", "arms", "full", "arm_torso"]

## Clips, die das Sitzen nutzt (Clipvertrag, LIESMICH_POPULOUS.md).
const CLIP_TURN_L: StringName = &"sit_turn_l"
const CLIP_TURN_R: StringName = &"sit_turn_r"
const CLIP_GROW: StringName = &"sit_grow"
const LAYER_CLIPS: Array[StringName] = [&"sit_stomp_l", &"sit_stomp_r", &"sit_kick_l",
	&"sit_kick_r", &"sit_wipe_l", &"sit_wipe_r", &"sit_hop", &"sit_clap",
	&"sit_double_stomp", CLIP_TURN_L, CLIP_TURN_R, CLIP_GROW, &"sit_hand_slam_l", &"sit_hand_slam_r"]
## Zeitpunkt des Aufschlags im Clip bei Tempo 1 (Sekunden) — VORSCHLAG fuer den
## Clipvertrag; der Clip wird so schnell gespielt, dass er auf die Ausholzeit faellt.
const SIT_CLIP_IMPACT: Dictionary = {
	&"sit_stomp_l": 0.35, &"sit_stomp_r": 0.35, &"sit_kick_l": 0.5, &"sit_kick_r": 0.5,
	&"sit_wipe_l": 0.35, &"sit_wipe_r": 0.35, &"sit_hop": 0.6, &"sit_clap": 0.35,
	&"sit_double_stomp": 0.35, &"sit_hand_slam_l": 0.35, &"sit_hand_slam_r": 0.35,
	&"sit_grow": 1.0,   # its whole clip: fired with the stretch's duration it plays that long
}
## Length of the sit attack clips at speed 1 (seconds, LIESMICH_POPULOUS.md). Model data, not balance:
## every sit attack plays its clip so that it fills the attack's cooldown (user spec 2026-11-19).
const SIT_CLIP_LENGTH: Dictionary = {
	&"sit_stomp_l": 0.9, &"sit_stomp_r": 0.9, &"sit_kick_l": 1.2, &"sit_kick_r": 1.2,
	&"sit_wipe_l": 1.0, &"sit_wipe_r": 1.0, &"sit_hop": 1.2, &"sit_clap": 0.9,
	&"sit_double_stomp": 1.0, &"sit_hand_slam_l": 0.9, &"sit_hand_slam_r": 0.9,
}

var player: AnimationPlayer = null
var tree: AnimationTree = null
var _blend: AnimationNodeBlendTree = null
var _base_clip: StringName = &""
## Track paths per layer as read from sit_idle (tests read them).
var leg_paths: Array[NodePath] = []
var arm_paths: Array[NodePath] = []
## Neck and head: they ride on the ARM layer too (user request 2026-11-17: the head
## turns to the side the arm wipes on — sit_wipe_l/_r carry that turn).
var head_paths: Array[NodePath] = []
## Spine, chest, upper chest: only the arm+torso layer (the side hand slam leans the upper body).
var torso_paths: Array[NodePath] = []


func _init(p_player: AnimationPlayer) -> void:
	player = p_player
	if player == null or player.get_parent() == null:
		return
	_read_paths()
	_build()


## Which part of the body a bone belongs to: 1 legs, 2 arms, 0 the rest.
static func part_of(bone: String) -> int:
	var b: String = bone.to_lower()
	if b.contains("upperleg") or b.contains("lowerleg") or b.contains("foot") or b.contains("toe"):
		return 1
	if b.contains("shoulder") or b.contains("arm") or b.contains("hand") or b.contains("thumb") \
			or b.contains("index") or b.contains("middle") or b.contains("ring") or b.contains("little"):
		return 2
	return 0


## Upper body bone (VRM names "spine", "chest", "upperChest")?
static func is_torso(bone: String) -> bool:
	var b: String = bone.to_lower()
	return b == "spine" or b == "chest" or b == "upperchest"


## Neck or head bone (VRM names "neck", "head")?
static func is_head(bone: String) -> bool:
	var b: String = bone.to_lower()
	return b == "neck" or b == "head"


func _read_paths() -> void:
	var source: StringName = Golem.CLIP_SIT_IDLE if player.has_animation(Golem.CLIP_SIT_IDLE) else &""
	if source == &"":
		return
	var anim: Animation = player.get_animation(source)
	for t in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		if is_head(String(path.get_subname(0))) and not head_paths.has(path):
			head_paths.append(path)
		if is_torso(String(path.get_subname(0))) and not torso_paths.has(path):
			torso_paths.append(path)
		match part_of(String(path.get_subname(0))):
			1:
				if not leg_paths.has(path):
					leg_paths.append(path)
			2:
				if not arm_paths.has(path):
					arm_paths.append(path)


## Combat rest (GolemSitCombat.COMBAT_REST_HOLD): the two groups, and how fast the rest pose blends
## in (seconds from none to full) and back out to sit_idle.
const REST_LEGS: int = 0
const REST_ARMS: int = 1
const REST_NAMES: Array[String] = ["rest_legs", "rest_arms"]
const REST_FADE_IN: float = 0.15
const REST_FADE_OUT: float = 0.4
var _rest: Array[float] = [0.0, 0.0]


## The base clips and their input names in the base transition (BASE_XFADE seconds
## of crossfade; each starts from its beginning — all three begin in the rest pose).
const BASE_INPUTS: Dictionary = {&"sit_idle": "idle", &"sit_turn_l": "turn_l", &"sit_turn_r": "turn_r"}
const BASE_XFADE: float = 0.3
## The turn clips (user spec 2026-11-19) play at the real turn rate over this rate, so the feet do not
## slide: at 1x the ground under her feet turns 2 x 0,075 rad in 0,72 s (DREH.fuss and anteilFuss in
## golem_bewegung_niedlich_sitzen.mjs, a step each second) — 0,208 rad/s, 11,9 degrees/s. The hands
## step slower (7,9 degrees/s); they slide a little. Same for all three golems.
const TURN_CLIP_RATE: float = 0.15 / 0.72


func _build() -> void:
	_blend = AnimationNodeBlendTree.new()
	# The base: sit_idle, or the turn clip while she turns (user report 2026-11-17: the
	# turn clip never showed — the base was ONE animation node whose clip was swapped,
	# so it ran on at sit_idle's clock and, not looping, froze after one pass).
	var base: AnimationNodeTransition = AnimationNodeTransition.new()
	base.xfade_time = BASE_XFADE
	var idx: int = 0
	for clip in BASE_INPUTS:
		base.add_input(BASE_INPUTS[clip])
		base.set_input_reset(idx, true)
		var a: AnimationNodeAnimation = AnimationNodeAnimation.new()
		a.animation = clip if player.has_animation(clip) else Golem.CLIP_SIT_IDLE
		_blend.add_node(StringName("base_" + BASE_INPUTS[clip]), a)
		idx += 1
	_blend.add_node(&"base", base)
	idx = 0
	for clip in BASE_INPUTS:
		var node: StringName = StringName("base_" + BASE_INPUTS[clip])
		if clip != Golem.CLIP_SIT_IDLE:
			# The turn clips run at the turn rate (set_turn_speed).
			var speed: StringName = StringName(String(node) + "_speed")
			_blend.add_node(speed, AnimationNodeTimeScale.new())
			_blend.connect_node(speed, 0, node)
			node = speed
		_blend.connect_node(&"base", idx, node)
		idx += 1
	var below: StringName = &"base"
	# Combat rest: the rest pose (sit_idle held at its first frame) over the base, per group.
	for group in [REST_LEGS, REST_ARMS]:
		var rn: String = REST_NAMES[group]
		var pose: AnimationNodeAnimation = AnimationNodeAnimation.new()
		pose.animation = Golem.CLIP_SIT_IDLE
		_blend.add_node(StringName(rn + "_pose"), pose)
		_blend.add_node(StringName(rn + "_hold"), AnimationNodeTimeScale.new())   # scale 0: frame 0
		var mix: AnimationNodeBlend2 = AnimationNodeBlend2.new()
		mix.filter_enabled = true
		for p in (leg_paths if group == REST_LEGS else arm_paths + head_paths + torso_paths):
			mix.set_filter_path(p, true)
		_blend.add_node(StringName(rn), mix)
		_blend.connect_node(StringName(rn + "_hold"), 0, StringName(rn + "_pose"))
		_blend.connect_node(StringName(rn), 0, below)
		_blend.connect_node(StringName(rn), 1, StringName(rn + "_hold"))
		below = StringName(rn)
	for layer in [LAYER_LEGS, LAYER_ARMS, LAYER_ARM_TORSO, LAYER_FULL]:
		var n: String = LAYER_NAMES[layer]
		var clip: AnimationNodeAnimation = AnimationNodeAnimation.new()
		clip.animation = Golem.CLIP_SIT_IDLE
		_blend.add_node(StringName(n + "_clip"), clip)
		_blend.add_node(StringName(n + "_speed"), AnimationNodeTimeScale.new())
		var shot: AnimationNodeOneShot = AnimationNodeOneShot.new()
		shot.fadein_time = 0.1
		shot.fadeout_time = 0.15
		if layer != LAYER_FULL:
			shot.filter_enabled = true
			for p in (leg_paths if layer == LAYER_LEGS else arm_paths):
				shot.set_filter_path(p, true)
			if layer != LAYER_LEGS:
				for p in head_paths:
					shot.set_filter_path(p, true)
			if layer == LAYER_ARM_TORSO:
				for p in torso_paths:
					shot.set_filter_path(p, true)
		_blend.add_node(StringName(n), shot)
		_blend.connect_node(StringName(n + "_speed"), 0, StringName(n + "_clip"))
		_blend.connect_node(StringName(n), 0, below)
		_blend.connect_node(StringName(n), 1, StringName(n + "_speed"))
		below = StringName(n)
	_blend.connect_node(&"output", 0, below)
	tree = AnimationTree.new()
	tree.name = "SitAnimationTree"
	tree.tree_root = _blend
	tree.active = false
	player.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	_base_clip = Golem.CLIP_SIT_IDLE
	tree.set("parameters/base/transition_request", "idle")   # the transition has no state until asked
	for rn in REST_NAMES:
		tree.set("parameters/%s_hold/scale" % rn, 0.0)
		tree.set("parameters/%s/blend_amount" % rn, 0.0)


## Does the model bring any clip the layers are for? Without one the tree stays off.
func usable() -> bool:
	if tree == null:
		return false
	for clip in LAYER_CLIPS:
		if player.has_animation(clip):
			return true
	return false


func is_active() -> bool:
	return tree != null and tree.active


func set_active(on: bool) -> void:
	if tree != null and tree.active != on:
		tree.active = on


## The clip under the layers: sit_idle, or the turn clip while she turns (if there).
func set_base(clip: StringName) -> void:
	if tree == null or clip == _base_clip or not player.has_animation(clip) or not BASE_INPUTS.has(clip):
		return
	_base_clip = clip
	tree.set("parameters/base/transition_request", BASE_INPUTS[clip])


func base_clip() -> StringName:
	return _base_clip


## Plays the turn clips at `rate` (rad/s, the body's real turn rate): TURN_CLIP_RATE is 1x — but at
## most Balance.GOLEM_TURN_CLIP_MAX_LOOPS loops a second (user spec 2026-11-19).
func set_turn_speed(rate: float) -> void:
	if tree == null:
		return
	var s: float = minf(absf(rate) / TURN_CLIP_RATE, Balance.GOLEM_TURN_CLIP_MAX_LOOPS * turn_clip_length())
	for input in ["turn_l", "turn_r"]:
		tree.set("parameters/base_%s_speed/scale" % input, s)


## Length of one loop of the turn clip (s; 2,0 s without the model's clip).
func turn_clip_length() -> float:
	return player.get_animation(CLIP_TURN_L).length if player != null and player.has_animation(CLIP_TURN_L) else 2.0


func turn_speed() -> float:
	return float(tree.get("parameters/base_turn_l_speed/scale")) if tree != null else 0.0


## Blends the combat rest of each group toward on (1) or off (0): in within REST_FADE_IN seconds,
## out within `fade_out` (REST_FADE_OUT; faster when a turn clip takes over).
func update_rest(legs_on: bool, arms_on: bool, delta: float, fade_out: float = REST_FADE_OUT) -> void:
	var want: Array[bool] = [legs_on, arms_on]
	for group in [REST_LEGS, REST_ARMS]:
		var target: float = 1.0 if want[group] else 0.0
		var fade: float = REST_FADE_IN if target > _rest[group] else maxf(fade_out, 0.01)
		var next: float = move_toward(_rest[group], target, delta / fade)
		if next != _rest[group]:
			_rest[group] = next
			if tree != null:
				tree.set("parameters/%s/blend_amount" % REST_NAMES[group], next)


## How far the combat rest of `group` is blended in (0..1).
func rest_amount(group: int) -> float:
	return _rest[group]


## Plays `clip` once on `layer`, so fast that its impact (SIT_CLIP_IMPACT) meets
## `windup` seconds from now. False when the clip is missing (the attack lands
## anyway, without a picture).
func fire(layer: int, clip: StringName, windup: float) -> bool:
	if tree == null or not player.has_animation(clip):
		return false
	var n: String = LAYER_NAMES[layer]
	(_blend.get_node(StringName(n + "_clip")) as AnimationNodeAnimation).animation = clip
	var impact: float = float(SIT_CLIP_IMPACT.get(clip, windup))
	tree.set("parameters/%s_speed/scale" % n, impact / maxf(windup, 0.05))
	tree.set("parameters/%s/request" % n, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


## Is a one-shot running on `layer` right now?
func layer_running(layer: int) -> bool:
	return tree != null and bool(tree.get("parameters/%s/active" % LAYER_NAMES[layer]))
