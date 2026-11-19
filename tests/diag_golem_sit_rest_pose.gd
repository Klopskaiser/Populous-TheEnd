extends SceneTree

## RUHEHALTUNG DER SITZCLIPS — misst an allen drei Golem-Modellen, wie weit Anfang und Ende jedes
## Sitzangriffsclips von der Ruhehaltung (erstes Bild von sit_idle) abweichen, und wie weit sit_idle
## selbst sich davon wegbewegt. Kein Test (faellt nie durch). Grundlage der Kampfruhe in GolemSitAnim:
## im Kampf halten Arme/Kopf und Beine die Ruhehaltung, statt dazwischen sit_idle zu spielen.
## Aufruf:
##   godot --headless -s res://tests/diag_golem_sit_rest_pose.gd
## Ausgabe je Clip: groesster Winkel (Grad) ueber alle Knochen am Anfang / am Ende, und der Knochen dazu.
## Danach mit echten Frames (der AnimationTree rechnet erst im Frame): wie weit der Kopf im Baum von der
## Ruhehaltung abweicht — ohne Kampfruhe (sit_idle laeuft) und mit Kampfruhe der Arme.

const MODELS: Array[String] = ["res://assets/models/units/golem.glb",
	"res://assets/models/units/golem_demon.glb", "res://assets/models/units/golem_genesis.glb"]


func _initialize() -> void:
	for path in MODELS:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			print("%s: fehlt" % path)
			continue
		var root: Node = scene.instantiate()
		var player: AnimationPlayer = _find_player(root)
		if player == null or not player.has_animation(&"sit_idle"):
			print("%s: kein sit_idle" % path)
			root.free()
			continue
		var idle: Animation = player.get_animation(&"sit_idle")
		print("== %s (sit_idle %.2f s)" % [path.get_file(), idle.length])
		var sway: Array = _max_dev(idle, idle, 0.0, -1.0)
		print("  sit_idle bewegt sich bis %.1f Grad weg (%s)" % [sway[0], sway[1]])
		for clip in GolemSitAnim.SIT_CLIP_LENGTH:
			if not player.has_animation(clip):
				print("  %s: fehlt" % clip)
				continue
			var a: Animation = player.get_animation(clip)
			var start: Array = _max_dev(a, idle, 0.0, 0.0)
			var end: Array = _max_dev(a, idle, a.length, 0.0)
			print("  %-18s %.2f s  Anfang %5.1f Grad (%s)  Ende %5.1f Grad (%s)" % [clip, a.length,
				start[0], start[1], end[0], end[1]])
		root.free()
	_tree_check()


var _root: Node3D
var _layers: GolemSitAnim
var _skel: Skeleton3D
var _rest_q: Quaternion
var _frame: int = 0


func _tree_check() -> void:
	_root = (load(MODELS[0]) as PackedScene).instantiate()
	get_root().add_child(_root)
	var player: AnimationPlayer = _find_player(_root)
	_layers = GolemSitAnim.new(player)
	_skel = _root.find_children("*", "Skeleton3D", true, false)[0]
	var idle: Animation = player.get_animation(&"sit_idle")
	_rest_q = idle.rotation_track_interpolate(idle.find_track(_layers.head_paths[_layers.head_paths.size() - 1],
		Animation.TYPE_ROTATION_3D), 0.0)
	_layers.set_active(true)


func _process(_delta: float) -> bool:
	if _layers == null:
		return true
	_frame += 1
	var bone: int = _skel.find_bone("head")
	if _frame == 3:
		_layers.tree.advance(5.0)
		print("== AnimationTree (golem.glb): Kopf nach 5 s sit_idle %.1f Grad neben der Ruhehaltung"
			% rad_to_deg(_rest_q.angle_to(_skel.get_bone_pose_rotation(bone))))
	elif _frame == 4:
		_layers.update_rest(false, true, 1.0)
		_layers.tree.advance(0.01)
		print("   mit Kampfruhe der Arme: %.2f Grad" % rad_to_deg(_rest_q.angle_to(_skel.get_bone_pose_rotation(bone))))
		_root.queue_free()
		return true
	return false


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var p: AnimationPlayer = _find_player(c)
		if p != null:
			return p
	return null


## Largest rotation difference (degrees) between `a` at time `t` and `ref` at `t_ref` over the
## rotation tracks both have; t_ref < 0: the largest over the whole of `ref` against its first frame.
func _max_dev(a: Animation, ref: Animation, t: float, t_ref: float) -> Array:
	var worst: float = 0.0
	var bone: String = "-"
	for i in range(ref.get_track_count()):
		if ref.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path: NodePath = ref.track_get_path(i)
		var q_ref: Quaternion = ref.rotation_track_interpolate(i, 0.0)
		if t_ref < 0.0:
			var steps: int = 40
			for s in range(steps + 1):
				var q: Quaternion = ref.rotation_track_interpolate(i, ref.length * float(s) / float(steps))
				var d: float = rad_to_deg(q_ref.angle_to(q))
				if d > worst:
					worst = d
					bone = String(path.get_subname(0))
			continue
		var j: int = a.find_track(path, Animation.TYPE_ROTATION_3D)
		if j < 0:
			continue
		var q_a: Quaternion = a.rotation_track_interpolate(j, t)
		var dev: float = rad_to_deg(q_ref.angle_to(q_a))
		if dev > worst:
			worst = dev
			bone = String(path.get_subname(0))
	return [worst, bone]
