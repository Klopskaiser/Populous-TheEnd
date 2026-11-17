class_name GolemSitAnim extends RefCounted

## ANIMATIONSEBENEN IM SITZEN (Vorarbeit 2026-11-17, plans/10l_golem_sitting.md):
## im Stand spielt der Golem genau einen Clip auf seinem AnimationPlayer. Im Sitzen
## greifen Beine und Arme UNABHAENGIG an — dafuer baut diese Klasse einen
## AnimationTree ueber denselben Player:
##
##   Grundclip (sit_idle, beim Drehen sit_turn_l / sit_turn_r)
##     -> Ebene BEINE  (OneShot, nur die Beinknochen: *UpperLeg, *LowerLeg, *Foot, *Toes)
##     -> Ebene ARME   (OneShot, nur Schulter, Ober-/Unterarm, Hand und Finger)
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
const LAYER_NAMES: Array[String] = ["legs", "arms", "full"]

## Clips, die das Sitzen nutzt (Clipvertrag, LIESMICH_POPULOUS.md).
const CLIP_TURN_L: StringName = &"sit_turn_l"
const CLIP_TURN_R: StringName = &"sit_turn_r"
const CLIP_GROW: StringName = &"sit_grow"
const LAYER_CLIPS: Array[StringName] = [&"sit_stomp_l", &"sit_stomp_r", &"sit_kick_l",
	&"sit_kick_r", &"sit_wipe_l", &"sit_wipe_r", &"sit_hop", &"sit_clap",
	&"sit_double_stomp", CLIP_TURN_L, CLIP_TURN_R, CLIP_GROW]
## Zeitpunkt des Aufschlags im Clip bei Tempo 1 (Sekunden) — VORSCHLAG fuer den
## Clipvertrag; der Clip wird so schnell gespielt, dass er auf die Ausholzeit faellt.
const SIT_CLIP_IMPACT: Dictionary = {
	&"sit_stomp_l": 0.35, &"sit_stomp_r": 0.35, &"sit_kick_l": 0.5, &"sit_kick_r": 0.5,
	&"sit_wipe_l": 0.35, &"sit_wipe_r": 0.35, &"sit_hop": 0.6, &"sit_clap": 0.35,
	&"sit_double_stomp": 0.35,
}

var player: AnimationPlayer = null
var tree: AnimationTree = null
var _blend: AnimationNodeBlendTree = null
var _base_clip: StringName = &""
## Track paths per layer as read from sit_idle (tests read them).
var leg_paths: Array[NodePath] = []
var arm_paths: Array[NodePath] = []


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


func _read_paths() -> void:
	var source: StringName = Golem.CLIP_SIT_IDLE if player.has_animation(Golem.CLIP_SIT_IDLE) else &""
	if source == &"":
		return
	var anim: Animation = player.get_animation(source)
	for t in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		match part_of(String(path.get_subname(0))):
			1:
				if not leg_paths.has(path):
					leg_paths.append(path)
			2:
				if not arm_paths.has(path):
					arm_paths.append(path)


func _build() -> void:
	_blend = AnimationNodeBlendTree.new()
	var base: AnimationNodeAnimation = AnimationNodeAnimation.new()
	base.animation = Golem.CLIP_SIT_IDLE
	_blend.add_node(&"base", base)
	var below: StringName = &"base"
	for layer in [LAYER_LEGS, LAYER_ARMS, LAYER_FULL]:
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
	if tree == null or clip == _base_clip or not player.has_animation(clip):
		return
	_base_clip = clip
	(_blend.get_node(&"base") as AnimationNodeAnimation).animation = clip


func base_clip() -> StringName:
	return _base_clip


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
