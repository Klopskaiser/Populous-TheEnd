class_name GolemSpell extends Spell

## Zauber 13 "Golem beschwören" (2026-09-06): beschwört am Zielpunkt einen
## Golem — eine grosse, zeitlich begrenzte Nahkampf-Einheit mit eigenem
## 3D-Modell (scripts/units/golem.gd). Der Golem ist eine normale, steuerbare
## Einheit des Stammes; die Werte stehen in Balance (GOLEM_*).
##
## Der Zielpunkt wird auf die naechste begehbare Zelle geschnappt (kein
## Gebaeude-Grundriss, kein Wasser, kein Void). Findet sich keine oder ist der
## Stamm am Einheiten-Hardcap, schlaegt der Zauber fehl und die Ladung bleibt
## erhalten (Regel aus Spell.cast). Der Effekt-Sound (`spell_golem`) spielt am
## Erscheinungsort; die Zauberformel (`spell_voice_golem`) kommt generisch von
## der Schamanin.

const GOLEM_SCENE: PackedScene = preload("res://scenes/units/golem.tscn")


func _init() -> void:
	id = &"golem"
	display_name_de = "Golem beschwören"
	charge_cost = Balance.SPELL_GOLEM_CHARGE_COST
	max_charges = Balance.SPELL_GOLEM_MAX_CHARGES
	cast_range = Balance.SPELL_GOLEM_CAST_RANGE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var pos: Vector3 = target
	if ctx.nav_grid != null:
		var cell: Vector2i = ctx.nav_grid.nearest_walkable_cell(
			ctx.nav_grid.world_to_cell(target))
		if cell.x < 0:
			return false   # nowhere to stand — the charge is kept
		pos = ctx.nav_grid.cell_to_world(cell)
	var golem: Unit = ctx.unit_manager.spawn_unit(GOLEM_SCENE, tribe.id, pos)
	if golem == null:
		return false   # unit cap reached — the charge is kept
	SpellAudio.play_effect(ctx.unit_manager, id, pos)
	return true
