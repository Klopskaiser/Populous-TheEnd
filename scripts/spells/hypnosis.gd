class_name HypnosisSpell extends Spell

## "Hypnose" (Zauber 12, Phase 10k): bekehrt gegnerische Anhänger in einem
## kleinen Quadrat VORÜBERGEHEND zum eigenen Stamm. Sie sind für die Dauer
## normal steuerbar und kämpfen für den Kontrolleur; danach fallen sie zurück.
##
## Die Schamanin ist immun (Nutzervorgabe) — Prediger sind es NICHT, anders als
## bei der Bekehrung des Predigers, wo sie es sind. Ein Prediger kann eine
## hypnotisierte Einheit ganz normal bekehren; das gewinnt und ist endgültig
## (Unit.convert_to_tribe löscht den Hypnose-Timer).
##
## Der Stammeswechsel ist absichtlich der VOLLE (Unit.hypnotize ruft
## convert_to_tribe): Bevölkerung, Manaerzeugung und Selektion wandern mit.
## Wer damit die letzten Einheiten eines Stammes hypnotisiert, beendet ihn —
## ausdrückliche Nutzerentscheidung, und sie hält die Umsetzung frei von einer
## zweiten Zugehörigkeitsliste und von Sonderfällen in population(), mana_rate()
## und der Siegprüfung.

## Kantenlänge des Wirkquadrats in Metern (Nutzervorgabe 4 x 4 m).
const AREA_SIZE: float = Balance.HYPNOSIS_AREA_SIZE
const DURATION: float = Balance.HYPNOSIS_DURATION


func _init() -> void:
	id = &"hypnosis"
	display_name_de = "Hypnose"
	charge_cost = Balance.SPELL_HYPNOSIS_CHARGE_COST
	max_charges = Balance.SPELL_HYPNOSIS_MAX_CHARGES
	cast_range = Balance.SPELL_HYPNOSIS_CAST_RANGE


func execute(tribe: Tribe, target: Vector3, ctx: SpellContext) -> bool:
	if ctx == null or ctx.unit_manager == null or tribe == null:
		return false
	var victims: Array[Unit] = units_in_square(ctx.unit_manager, target, tribe.id)
	if victims.is_empty():
		return false   # nothing to hypnotize — the charge is kept (Spell.cast)
	var taken: int = 0
	for u in victims:
		if u.hypnotize(tribe, DURATION):
			taken += 1
	return taken > 0


## Enemy units inside the AREA_SIZE square around `center` that hypnosis can
## actually take. Static and free of side effects so the area rule is testable
## without casting (pattern: Fireball.impact_outcome).
##
## The square is measured FLAT in XZ — like every other area effect in the game.
static func units_in_square(um: UnitManager, center: Vector3,
		caster_tribe_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	if um == null:
		return result
	var half: float = AREA_SIZE * 0.5
	# One radius query over the circumscribed circle, then the square test — the
	# same two-step the flatten/fire-ram rectangles use.
	var radius: float = half * sqrt(2.0)
	for u in um.get_units_in_radius(center, radius):
		if u.tribe_id == caster_tribe_id or u.state == Unit.State.DEAD:
			continue
		if absf(u.position.x - center.x) > half or absf(u.position.z - center.z) > half:
			continue
		if u.unit_kind() == &"shaman":
			continue   # the enemy shaman is immune (user spec)
		if u.garrison_housed:
			continue   # protected tower reserve, like conversion
		result.append(u)
	return result
