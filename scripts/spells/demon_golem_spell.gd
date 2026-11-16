class_name DemonGolemSpell extends GolemSpell

## Zauber 14 "Dämonengolem beschwören" (Nutzervorgabe 2026-11-16): beschwoert am
## Zielpunkt einen Daemonengolem (scripts/units/demon_golem.gd) — der zweite
## Golem, klein beginnend und ohne Lebenszeit. Kosten, Ladungen und Reichweite wie
## beim Golem; Ablauf (Zielpunkt auf die naechste begehbare Zelle, Ladung bleibt
## bei Fehlschlag) geerbt von GolemSpell.
##
## Vorerst nur im Satz des menschlichen Spielers (Spell.create_player_set) — die
## KI bekommt ihn nicht. Sounds: `spell_voice_demon_golem` (Zauberformel) und
## `spell_demon_golem` (Erscheinen); fehlen die Dateien, bleibt es stumm.

const DEMON_GOLEM_SCENE: PackedScene = preload("res://scenes/units/demon_golem.tscn")


func _init() -> void:
	super._init()
	id = &"demon_golem"
	display_name_de = "Dämonengolem beschwören"
	charge_cost = Balance.SPELL_DEMON_GOLEM_CHARGE_COST
	max_charges = Balance.SPELL_DEMON_GOLEM_MAX_CHARGES
	cast_range = Balance.SPELL_DEMON_GOLEM_CAST_RANGE


func _scene() -> PackedScene:
	return DEMON_GOLEM_SCENE
