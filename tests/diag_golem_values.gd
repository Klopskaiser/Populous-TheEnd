extends SceneTree

## GOLEM-WERTE je Stufe — Nachschlagetabelle, aus dem LEBENDEN Code gerechnet.
##
## Kein Test (keine Sollwerte, faellt nie durch): reine Auskunft, wie diag_ttk.gd.
## Aufruf:
##   godot --headless -s res://tests/diag_golem_values.gd
##
## Eine Zeile je Stufe 0-7, eine einen Wachstumsschritt vor dem Ende und eine fuer
## das Wachstumsende (100 m). Jede Zeile steht fuer den Golem in dem Moment, in
## dem er die Stufe ERREICHT (die Lebensobergrenze waechst mit weiteren Kills noch
## bis 1000).

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")


func _initialize() -> void:
	var g: Golem = GOLEM_SCENE.instantiate() as Golem
	print("Stufe | Kills | Groesse m | Koerperradius m | Auswahlkreis m | LP max | Heilung/s | Tempo m/s"
		+ " | Reichweite m | Aggro m | Ziele Grund/Tritt/Trommeln/Sprung | Takt s Tritt/Handschlag/Trommeln/Sprung | Haltungswechsel s | Drehrate Grad/s"
		+ " | Handschlag: Schaden, Kreis r, Mitte vor, Flaeche m2 | Tritt: Schaden, breit x vor + zurueck, Flaeche m2"
		+ " | Trommeln: Kreis r | Trampeln | Sprung: Schaden, Kreis r, Landung nach s | Ausholen Hand/Tritt/Luft s | Lebenszeit | Klippe bis m"
		+ " | erleidet: Brand/s, Blitz, Katapult-Volltreffer")
	for stage in range(0, Balance.GOLEM_MAX_LEVEL + 1):
		while g.level < stage:
			g._credit_kill()
		_row(g, str(stage))
	while g.growth_steps < Golem.max_growth_steps() - 1:
		g._credit_kill()
	_row(g, "7 + %d Schritte" % g.growth_steps)
	while g.growth_steps < Golem.max_growth_steps():
		g._credit_kill()
	_row(g, "7 + %d Schritte (ausgewachsen)" % g.growth_steps)
	g.free()
	quit()


func _row(g: Golem, label: String) -> void:
	var r: float = g.reach_factor()
	var life: String = "unbegrenzt" if g.level >= Balance.GOLEM_FINAL_BONUS_LEVEL \
		else "180 s + 6/Kill + 20/Stufe"
	var straight: String = "%.1f" % g.giant_step_limit() if g.walks_straight() else "-"
	var lane: Vector2 = g._kick_extent()
	print("%s | %d | %.1f | %.2f | %.2f | %d | %d | %.2f | %.1f | %.1f | %d/%d/%d/%d | %.2f/%.2f/%.2f/%.2f | %.2f | %.0f | %d, %.1f, %.1f, %.0f | %d, %.1f x %.1f + %.1f, %.0f | %.1f | %d (Trommeln %d) | %d, %.2f, %.2f | %.2f/%.2f/%.2f | %s | %s | %d, %d, %d" % [
		label, g.kills, g.height_m(), g.trample_radius(), 0.34 * g.selection_ring_scale(),
		g.max_health, int(g.regen_per_second()), g.current_speed(), g.reach(),
		g.aggro_radius(), g.max_targets(), g.max_targets_of(Golem.ATTACK_KICK), g.max_targets_of(Golem.ATTACK_DRUM),
		g.max_targets_of(Golem.ATTACK_STOMP), g.strike_cooldown(), g.cooldown_for(Golem.ATTACK_SLAM),
		g.cooldown_for(Golem.ATTACK_DRUM), g.cooldown_for(Golem.ATTACK_STOMP), g.stance_switch_time(),
		rad_to_deg(g.turn_rate()),
		g.attack_damage(Golem.ATTACK_SLAM), g.slam_radius(), Balance.GOLEM_SLAM_FORWARD * g.limb_factor(),
		PI * pow(g.slam_radius(), 2.0),
		g.attack_damage(Golem.ATTACK_KICK), float(Golem.stand_attack(Golem.ATTACK_KICK)["area"]) * r, lane.x, lane.y,
		float(Golem.stand_attack(Golem.ATTACK_KICK)["area"]) * r * (lane.x + lane.y), g.ground_radius(Golem.ATTACK_DRUM),
		g.trample_damage(), g.attack_damage(Golem.ATTACK_DRUM),
		g.attack_damage(Golem.ATTACK_STOMP), g.stomp_radius(), g.current_windup(Golem.ATTACK_STOMP),
		g.current_windup(Golem.ATTACK_SLAM), g.current_windup(Golem.ATTACK_KICK),
		g.current_windup(Golem.ATTACK_SWAT), life, straight,
		int(g.burn_damage_per_second()), g.lightning_damage(Balance.LIGHTNING_UNIT_DAMAGE),
		g.siege_shock_damage(Balance.SIEGE_SHOT_SHOCK_DAMAGE, 0.0)])
