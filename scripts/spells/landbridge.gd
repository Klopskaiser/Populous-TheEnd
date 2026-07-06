class_name LandbridgeSpell extends Spell

## "Landbrücke": no damage, pure terrain deformation. GRADES a broad corridor
## from the shaman's position to the target point onto a straight profile —
## over water it rises onto coast level (bridge), on land it forms a smooth
## straight ramp from start height to target height (dips filled, bumps
## shaved; a stretch that is already straight changes nothing and the cast
## fails, keeping the charge). The change happens GRADUALLY over
## LandbridgeMorph.DURATION; units/trees/piles/buildings ride along.

## Corridor half width (broad line) and the soft blend beyond it.
const HALF_WIDTH: float = 1.6
const EDGE: float = 1.5
## Bridge deck height above the water line (comfortably walkable).
const COAST_MARGIN: float = 1.2


func _init() -> void:
	id = &"landbridge"
	display_name_de = "Landbrücke"
	charge_cost = 60.0
	max_charges = 4
	cast_range = 9.0


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null or ctx.unit_manager == null:
		return false
	var td: TerrainData = ctx.terrain_data
	var caster: Unit = tribe.shaman if tribe != null else null
	var from3: Vector3 = target
	if caster != null and is_instance_valid(caster):
		from3 = caster.position
	var from: Vector2 = Vector2(from3.x, from3.z)
	var to: Vector2 = Vector2(target.x, target.z)
	var deck: float = TerrainData.SEA_LEVEL + COAST_MARGIN
	# Water start/target snaps onto coast level; land keeps its height (ramp).
	var h_from: float = maxf(td.get_height(from.x, from.y), deck)
	var h_to: float = maxf(td.get_height(to.x, to.y), deck)
	var plan: Dictionary = td.line_raise_targets(from, to, HALF_WIDTH, h_from, h_to, EDGE)
	if (plan.indices as PackedInt32Array).is_empty():
		return false
	var morph: LandbridgeMorph = LandbridgeMorph.new()
	morph.setup(ctx, plan)
	ctx.unit_manager.register_projectile(morph)
	return true
