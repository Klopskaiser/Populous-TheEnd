class_name SupertornadoSpell extends Spell

## "Supertornado": spawns one oversized TornadoVortex (twice as wide, 12 m tall,
## 16 s) at the target plus SUPERTORNADO_SATELLITE_COUNT normal-sized tornados
## around it. All effect values live on the vortices; the satellites use the
## plain tornado defaults (setup() without size overrides).


func _init() -> void:
	id = &"supertornado"
	display_name_de = "Supertornado"
	charge_cost = Balance.SPELL_SUPERTORNADO_CHARGE_COST
	max_charges = Balance.SPELL_SUPERTORNADO_MAX_CHARGES
	cast_range = Balance.SPELL_SUPERTORNADO_CAST_RANGE
	effect_delay = Balance.SPELL_EFFECT_DELAY_LATE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	# Big main funnel at the target.
	var main: TornadoVortex = TornadoVortex.new()
	main.setup(tribe.id, target, ctx.unit_manager, ctx.terrain_data,
		ctx.building_manager, Balance.SUPERTORNADO_RADIUS,
		Balance.SUPERTORNADO_TOP_HEIGHT, Balance.SUPERTORNADO_LIFETIME)
	main.sfx_id = id   # only the main funnel roars; the satellites stay silent
	ctx.unit_manager.register_projectile(main)
	# Two normal-sized satellite tornados around it.
	for i in range(Balance.SUPERTORNADO_SATELLITE_COUNT):
		var angle: float = randf() * TAU
		var at: Vector3 = target + Vector3(cos(angle), 0.0, sin(angle)) \
			* Balance.SUPERTORNADO_SATELLITE_DIST
		var inside: Vector2 = TerrainData.clamp_into_world(ctx.terrain_data, at.x, at.z)
		at.x = inside.x
		at.z = inside.y
		var sat: TornadoVortex = TornadoVortex.new()
		sat.sfx_id = &""
		sat.setup(tribe.id, at, ctx.unit_manager, ctx.terrain_data,
			ctx.building_manager)
		ctx.unit_manager.register_projectile(sat)
	return true
