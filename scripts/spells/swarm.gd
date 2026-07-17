class_name SwarmSpell extends Spell

## "Insektenschwarm": spawns a wandering SwarmCloud (10 s) at the target.
## All effect values live on the cloud.


func _init() -> void:
	id = &"swarm"
	display_name_de = "Insektenschwarm"
	charge_cost = Balance.SPELL_SWARM_CHARGE_COST
	max_charges = Balance.SPELL_SWARM_MAX_CHARGES
	cast_range = Balance.SPELL_SWARM_CAST_RANGE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var cloud: SwarmCloud = SwarmCloud.new()
	cloud.setup(tribe.id, target, ctx.unit_manager, ctx.terrain_data)
	ctx.unit_manager.register_projectile(cloud)
	return true
