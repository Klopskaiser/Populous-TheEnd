class_name GenesisGolemSpell extends GolemSpell

## Zauber 15 "Genesisgolem beschwören" (Nutzervorgabe 2026-11-17): beschwoert am
## Zielpunkt einen Genesisgolem (scripts/units/genesis_golem.gd) — er waechst aus den
## Braves seines Stammes und aus Holz. Kosten, Ladungen und Reichweite wie beim
## Daemonengolem; Ablauf (Zielpunkt auf die naechste begehbare Zelle, Ladung bleibt
## bei Fehlschlag) geerbt von GolemSpell.
##
## Wie der Daemonengolem im vollen Satz (Spell.create_player_set), seit 2026-11-21 fuer
## jeden Stamm, auch die KI (AIGolems). Sounds: `spell_voice_genesis_golem` (Zauberformel) und
## `spell_genesis_golem` (Erscheinen); fehlen die Dateien, bleibt es stumm.

const GENESIS_GOLEM_SCENE: PackedScene = preload("res://scenes/units/genesis_golem.tscn")


func _init() -> void:
	super._init()
	id = &"genesis_golem"
	display_name_de = "Genesisgolem beschwören"
	charge_cost = Balance.SPELL_GENESIS_GOLEM_CHARGE_COST
	max_charges = Balance.SPELL_GENESIS_GOLEM_MAX_CHARGES
	cast_range = Balance.SPELL_GENESIS_GOLEM_CAST_RANGE


func _scene() -> PackedScene:
	return GENESIS_GOLEM_SCENE
