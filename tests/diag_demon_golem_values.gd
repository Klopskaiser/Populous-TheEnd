extends SceneTree

## DAEMONENGOLEM-WERTE je Groesse — Nachschlagetabelle, aus dem LEBENDEN Code
## gerechnet (wie diag_golem_values.gd fuer den Golem).
##
## Kein Test (keine Sollwerte, faellt nie durch): reine Auskunft.
## Aufruf:
##   godot --headless -s res://tests/diag_demon_golem_values.gd
##   godot --headless -s res://tests/diag_demon_golem_values.gd -- 2,5,10,20,30
##
## Eine Zeile je Groesse (Vorgabe: 2 m, 20 m, 30 m, 50 m, 80 m, 100 m und 119 m —
## bei 120 m zerfaellt er; er waechst 3 m je Stufe, eine Zeile steht fuer die erste
## Stufe, auf der er die Groesse ERREICHT oder ueberschreitet).

const DEMON_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")


func _initialize() -> void:
	var sizes: Array[int] = [2, 20, 30, 50, 80, 100, 119]
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		sizes.clear()
		for s in args[0].split(","):
			if s.is_valid_int():
				sizes.append(int(s))
	var d: DemonGolem = DEMON_SCENE.instantiate() as DemonGolem
	print("Groesse m | Wachstumsstufe | Kills | Kills fuer die naechste Stufe | Koerperbreite m | Koerperradius m | LP max | Heilung/s | Tempo m/s"
		+ " | Reichweite m | Aggro m | Ziele Grund/Tritt/Trommeln/Sprung | Takt s Tritt/Handschlag/Trommeln/Sprung | Haltungswechsel s | Drehrate Grad/s"
		+ " | Handschlag: Schaden (genau), Kreis r, Mitte vor | Tritt: Schaden (genau), breit x vor + zurueck"
		+ " | Trommeln: Schaden (genau), Kreis r | Trampeln | Sprung: Schaden, Kreis r | Ausholen Hand/Tritt/Luft s"
		+ " | Luftschiffe | Riesenpaket | erleidet: Brand/s, Blitz, Katapult-Volltreffer")
	for h in sizes:
		while d.height_m() < float(h) - 0.001 and d.growth_steps < DemonGolem.max_steps() - 1:
			d._credit_kill()
		_row(d)
	d.free()
	quit()


func _row(d: DemonGolem) -> void:
	var r: float = d.reach_factor()
	var lane: Vector2 = d._kick_extent()
	print("%d | %d | %d | %d | %.2f | %.2f | %d | %.2f | %.2f | %.1f | %.1f | %d/%d/%d/%d | %.2f/%.2f/%.2f/%.2f | %.2f | %.0f | %d (%.2f), %.2f, %.1f | %d (%.2f), %.2f x %.1f + %.1f | %d (%.2f), %.2f | %d | %d, %.2f | %.2f/%.2f/%.2f | %s | %s | %d, %d, %d" % [
		int(round(d.height_m())), d.growth_steps, d.kills, DemonGolem.kills_for_step(d.growth_steps + 1),
		2.0 * d.trample_radius(), d.trample_radius(), d.max_health, d.regen_per_second(),
		d.current_speed(), d.reach(), d.aggro_radius(),
		d.max_targets(), d.max_targets_of(Golem.ATTACK_KICK), d.max_targets_of(Golem.ATTACK_DRUM),
		d.max_targets_of(Golem.ATTACK_STOMP), d.strike_cooldown(), d.cooldown_for(Golem.ATTACK_SLAM),
		d.cooldown_for(Golem.ATTACK_DRUM), d.cooldown_for(Golem.ATTACK_STOMP), d.stance_switch_time(),
		rad_to_deg(d.turn_rate()),
		d.attack_damage(Golem.ATTACK_SLAM), d.damage_exact(Golem.ATTACK_SLAM), d.slam_radius(),
		Balance.GOLEM_SLAM_FORWARD * d.limb_factor(),
		d.attack_damage(Golem.ATTACK_KICK), d.damage_exact(Golem.ATTACK_KICK),
		Balance.GOLEM_KICK_WIDTH * r, lane.x, lane.y,
		d.attack_damage(Golem.ATTACK_DRUM), d.damage_exact(Golem.ATTACK_DRUM),
		d.ground_radius(Golem.ATTACK_DRUM), d.trample_damage(),
		d.attack_damage(Golem.ATTACK_STOMP), d.stomp_radius(),
		d.current_windup(Golem.ATTACK_SLAM), d.current_windup(Golem.ATTACK_KICK),
		d.current_windup(Golem.ATTACK_SWAT),
		"ja" if d.can_strike_air() else "-", "ja" if d.is_giant() else "-",
		int(d.burn_damage_per_second()), d.lightning_damage(Balance.LIGHTNING_UNIT_DAMAGE),
		d.siege_shock_damage(Balance.SIEGE_SHOT_SHOCK_DAMAGE, 0.0)])
