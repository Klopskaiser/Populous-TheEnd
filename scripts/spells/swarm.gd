class_name SwarmSpell extends Spell

## "Insektenschwarm": spawns a wandering SwarmCloud (10 s) at the target.
## All effect values live on the cloud.


func _init() -> void:
	id = &"swarm"
	display_name_de = "Insektenschwarm"
	charge_cost = 50.0
	max_charges = 4


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var cloud: SwarmCloud = SwarmCloud.new()
	cloud.setup(tribe.id, target, ctx.unit_manager, ctx.terrain_data)
	ctx.unit_manager.register_projectile(cloud)
	return true
