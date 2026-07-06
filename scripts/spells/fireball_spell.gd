class_name FireballSpell extends Spell

## "Feuerball" (replaces the old Blast/Druckwelle): launches a FireballBolt
## from the shaman at the target point. All effect values live on the bolt.


func _init() -> void:
	id = &"fireball"
	display_name_de = "Feuerball"
	charge_cost = 40.0
	max_charges = 4


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var caster: Unit = tribe.shaman
	var from: Vector3 = target
	if caster != null and is_instance_valid(caster):
		from = caster.position
	var bolt: FireballBolt = FireballBolt.new()
	bolt.setup(tribe.id, from, target, caster, ctx.unit_manager, ctx.terrain_data)
	ctx.unit_manager.register_projectile(bolt)
	return true
