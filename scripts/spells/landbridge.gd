class_name LandbridgeSpell extends Spell

## "Landbrücke": no damage, pure terrain deformation. Raises a broad corridor
## from the shaman's position to the target point: onto coast level when the
## target lies in water, onto the target's height on land — differing start/
## target heights become a walkable ramp (TerrainData.raise_line). Terrain is
## only raised, never lowered.

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


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.terrain_data == null:
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
	var rect: Rect2i = td.raise_line(from, to, HALF_WIDTH, h_from, h_to, EDGE)
	if rect.size == Vector2i.ZERO:
		return false
	ctx.apply_terrain_change(rect)
	return true
