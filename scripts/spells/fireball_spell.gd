class_name FireballSpell extends Spell

## "Feuerball" (replaces the old Blast/Druckwelle): launches a FireballBolt
## from the shaman at the target point. All effect values live on the bolt.


func _init() -> void:
	id = &"fireball"
	display_name_de = "Feuerball"
	charge_cost = Balance.SPELL_FIREBALL_CHARGE_COST
	max_charges = Balance.SPELL_FIREBALL_MAX_CHARGES
	cast_range = Balance.SPELL_FIREBALL_CAST_RANGE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var caster: Unit = tribe.shaman
	var from: Vector3 = target
	if caster != null and is_instance_valid(caster):
		from = caster.position
	var bolt: FireballBolt = FireballBolt.new()
	bolt.setup(tribe.id, from, target, caster, ctx.unit_manager, ctx.terrain_data)
	bolt.chase_target = acquire_target(ctx.unit_manager, target, tribe.id)
	ctx.unit_manager.register_projectile(bolt)
	return true


## Enemy the bolt will CHASE: the nearest one to the aimed point (10k). There is a
## 1,0-s cast wind-up (SHAMAN_CAST_TIME) in which a unit runs up to 4 m, so a
## purely point-based ball missed a moving target by construction.
##
## Only ACQUIRING happens here; the leash lives on the bolt
## (FIREBALL_CHASE_MAX_DRIFT) so a target that runs out of the aimed area still
## gets the impact on the ground it was aimed at. Static and side-effect free.
static func acquire_target(um: UnitManager, at: Vector3, caster_tribe_id: int):
	if um == null:
		return null
	var best = null
	var best_d: float = INF
	for u in um.get_units_in_radius(at, Balance.FIREBALL_ACQUIRE_RADIUS):
		if u.tribe_id == caster_tribe_id or u.state == Unit.State.DEAD:
			continue
		var d: float = Vector2(u.position.x - at.x, u.position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = u
	return best
