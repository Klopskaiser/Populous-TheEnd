class_name TornadoSpell extends Spell

## "Tornado": spawns a wandering TornadoVortex (8 s) at the target point.
## All effect values live on the vortex.


func _init() -> void:
	id = &"tornado"
	display_name_de = "Tornado"
	charge_cost = 90.0
	max_charges = 3


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var vortex: TornadoVortex = TornadoVortex.new()
	vortex.setup(tribe.id, target, ctx.unit_manager, ctx.terrain_data,
		ctx.building_manager)
	ctx.unit_manager.register_projectile(vortex)
	return true
