extends SceneTree

## ANGRIFFSWERTE ALLER GOLEMS — Stand- und Sitzangriffe, aus dem LEBENDEN Code gerechnet.
##
## Kein Test (keine Sollwerte, faellt nie durch): reine Auskunft und Schnappschuss. Wer die
## Angriffstabelle in Balance umbaut, kann die Ausgabe vorher und nachher vergleichen.
## Aufruf:
##   godot --headless -s res://tests/diag_golem_attack_table.gd
##
## Je Golem und Groesse eine Zeile "stand" (Schaden, Abklingzeit, Ausholzeit, Animationsdauer,
## Ziele, Flaechen) und ab Sitzgroesse je Sitzangriff eine Zeile "sit".

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")
const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")
const GENESIS_SCENE: PackedScene = preload("res://scenes/units/genesis_golem.tscn")

const STAND: Array[StringName] = [Golem.ATTACK_SLAM, Golem.ATTACK_KICK, Golem.ATTACK_DRUM,
	Golem.ATTACK_STOMP, Golem.ATTACK_SWAT]
const SIT: Array[StringName] = [GolemSitCombat.STOMP_L, GolemSitCombat.KICK_L, GolemSitCombat.WIPE_L,
	GolemSitCombat.HAND_SLAM_L, GolemSitCombat.HOP, GolemSitCombat.DOUBLE_STOMP, GolemSitCombat.CLAP]


func _initialize() -> void:
	print("golem | groesse m | angriff | schaden | ziele | abklingzeit s | ausholzeit s | animation s | flaeche")
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	for stage in range(0, Balance.GOLEM_MAX_LEVEL + 1):
		while g.level < stage:
			g._credit_kill()
		_rows("golem", g)
	for steps in [1, 8, 14, 20, Golem.max_growth_steps()]:
		while g.growth_steps < steps:
			g._credit_kill()
		_rows("golem", g)
	g.free()
	var d: DemonGolem = DEMON_SCENE.instantiate() as DemonGolem
	for h in [2, 20, 32, 50, 80, 119]:
		while d.height_m() < float(h) - 0.001 and d.growth_steps < DemonGolem.max_steps() - 1:
			d._credit_kill()
		_rows("demon", d)
	d.free()
	var e: GenesisGolem = GENESIS_SCENE.instantiate() as GenesisGolem
	for stage in [0, 4, 8]:
		while e.stage < stage:
			e._stage_up()
		_rows("genesis", e)
	for h in [50.0, 100.0]:
		while e.height_m() < h - 0.001:
			e.grow_by_wood(15.0)
		_rows("genesis", e)
	e.free()
	quit()


func _rows(name: String, g: Golem) -> void:
	var h: String = "%.3f" % g.height_m()
	for kind in STAND:
		print("%s | %s | %s | %d | %d | %.6f | %.6f | %.6f | %s" % [name, h, kind, g.attack_damage(kind),
			g.max_targets_of(kind), g.cooldown_for(kind), g.current_windup(kind), g.attack_duration(kind),
			_stand_area(g, kind)])
	if g.height_m() < Balance.GOLEM_SIT_MIN_HEIGHT - 0.0001:
		return
	var c: GolemSitCombat = GolemSitCombat.new(g)
	c._frame()
	for kind in SIT:
		var anim: float = float(GolemSitAnim.SIT_CLIP_LENGTH[kind]) * c.windup_of(kind) \
			/ float(GolemSitAnim.SIT_CLIP_IMPACT[kind])
		print("%s | %s | %s | %d | %d | %.6f | %.6f | %.6f | %s" % [name, h, kind, c.damage(kind),
			c.max_targets(kind), c.cooldown_of(kind), c.windup_of(kind), anim, _sit_area(c, kind)])


func _stand_area(g: Golem, kind: StringName) -> String:
	if kind == Golem.ATTACK_SLAM:
		return "r %.6f vor %.6f" % [g.slam_radius(), Balance.GOLEM_SLAM_FORWARD * g.limb_factor()]
	if kind == Golem.ATTACK_KICK:
		var lane: Vector2 = g._kick_extent()
		return "breit %.6f vor %.6f zurueck %.6f" % [float(Golem.stand_attack(kind)["area"]) * g.reach_factor(), lane.x, lane.y]
	if kind == Golem.ATTACK_DRUM:
		return "r %.6f schlaege %d/%d/%d" % [g.ground_radius(kind), g.drum_hit_damage(0), g.drum_hit_damage(1),
			g.drum_hit_damage(2)]
	if kind == Golem.ATTACK_STOMP:
		return "r %.6f" % g.stomp_radius()
	return "reichweite %.6f" % g.reach()


func _sit_area(c: GolemSitCombat, kind: StringName) -> String:
	match kind:
		GolemSitCombat.STOMP_L:
			return "r %.6f" % c.stomp_radius()
		GolemSitCombat.KICK_L:
			return "aussen %.6f" % c._c_kick_out
		GolemSitCombat.WIPE_L:
			return "reichweite %.6f" % c.wipe_reach()
		GolemSitCombat.HAND_SLAM_L:
			return "r %.6f" % c.hand_slam_radius()
		GolemSitCombat.HOP:
			return "r %.6f" % c.hop_radius()
		GolemSitCombat.DOUBLE_STOMP:
			return "r %.6f" % c.double_stomp_radius()
	return "r %.6f" % c.clap_radius()
