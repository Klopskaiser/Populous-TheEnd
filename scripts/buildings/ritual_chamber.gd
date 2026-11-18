class_name RitualChamber extends TrainingBuilding

## Ritual chamber (Ritualkammer, experimental — user spec 2026-11-16): built
## like a training building and fed like one (braves queue, one goes in), but
## nobody ever comes out — the brave is gone. Every RITUAL_CHAMBER_BRAVES_PER_REWARD
## braves the tribe sacrifices (counted per tribe, over all its chambers) either
## credit ONE kill to a random golem of the tribe (golem or demon golem — with
## everything a kill brings: growth, healing, lifetime) or, without a living golem,
## pay RITUAL_CHAMBER_MANA_REWARD mana into one of the three golem spells (golem, demon golem, genesis
## golem) — one that is switched on (charging) and not full; only when there is none, into any that is
## not full (user spec 2026-11-18).
##
## Only buildable while the option "Ritualkammer (experimentell)" is switched on
## (GameSettings.ritual_chamber_enabled, main menu options); the AI never builds it.
##
## Placeholder mesh: a dark stone ring with four obelisks around an altar and a
## violet glow — unmistakably not a barracks.

const WOOD_COST: int = Balance.RITUAL_CHAMBER_WOOD_COST
const FOOTPRINT: Vector2i = Balance.RITUAL_CHAMBER_FOOTPRINT
const TRAINING_TIME: float = Balance.RITUAL_CHAMBER_TRAINING_TIME

const C_STONE: Color = Color(0.26, 0.24, 0.28)
const C_ALTAR: Color = Color(0.38, 0.34, 0.36)
const C_GLOW: Color = Color(0.62, 0.22, 0.85)

## Dice for the random golem / spell (seeded per chamber; tests set the seed).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = Balance.RITUAL_CHAMBER_HP
	health = max_health
	produces = null   # nobody comes out
	training_time = TRAINING_TIME
	rng.randomize()


func display_name() -> String:
	return "Ritualkammer"


func asset_kind() -> StringName:
	return &"ritual_chamber"


## Mana while a brave is inside: as much per brave as a warrior costs at the
## barracks (TRAINING_MANA_PER_BUILDING over WARRIOR_CAMP_TRAINING_TIME), spread
## over the chamber's own shorter time — user spec "kostet Mana wie die
## Kriegerproduktion".
func training_mana_rate() -> float:
	return Balance.TRAINING_MANA_PER_BUILDING * Balance.WARRIOR_CAMP_TRAINING_TIME \
		/ maxf(training_time, 0.001)


## The brave is gone (the base frees it and, with `produces` null, spawns
## nothing); then the tribe's sacrifice count goes up.
func _finish_one() -> void:
	var had_trainee: bool = is_instance_valid(trainee)
	super._finish_one()
	if had_trainee and tribe != null:
		tribe.ritual_sacrifices += 1
		if tribe.ritual_sacrifices % Balance.RITUAL_CHAMBER_BRAVES_PER_REWARD == 0:
			grant_reward()


## One reward: a kill for a random living golem of the tribe, else mana for one of
## the golem spells that can still take some — a random one of those switched on (charging), and only
## when none of them is, a random one of the rest (user spec 2026-11-18). Returns what happened
## (&"kill", &"mana" or &"none" — both spells full / missing).
func grant_reward() -> StringName:
	if tribe == null:
		return &"none"
	var golems: Array[Golem] = []
	for u in tribe.units:
		# The Genesis golem does not grow by kills: a kill would be lost on him.
		if is_instance_valid(u) and u is Golem and not (u is GenesisGolem) \
				and u.state != Unit.State.DEAD and not u.doomed:
			golems.append(u as Golem)
	if not golems.is_empty():
		golems[rng.randi_range(0, golems.size() - 1)]._credit_kill()
		return &"kill"
	var spells: Array[Spell] = []
	var active: Array[Spell] = []
	for id in [&"golem", &"demon_golem", &"genesis_golem"]:   # (genesis since 2026-11-18, user spec)
		var spell: Spell = tribe.get_spell(id)
		if spell != null and not spell.is_full():
			spells.append(spell)
			if spell.active:
				active.append(spell)
	if spells.is_empty():
		return &"none"
	if not active.is_empty():
		spells = active
	spells[rng.randi_range(0, spells.size() - 1)].add_charge_mana(
		Balance.RITUAL_CHAMBER_MANA_REWARD)
	tribe._emit_spell_charges()
	return &"mana"


## Authored with the entrance facing south (+z); the base rotates the mesh root.
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(footprint.x)

	# Low round stone floor.
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = span * 0.46
	disc.bottom_radius = span * 0.5
	disc.height = 0.3
	floor_mesh.mesh = disc
	floor_mesh.material_override = _make_material(C_STONE)
	floor_mesh.position.y = 0.15
	_mesh_root.add_child(floor_mesh)

	# Four obelisks on the diagonals.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var obelisk: MeshInstance3D = MeshInstance3D.new()
			var ob: CylinderMesh = CylinderMesh.new()
			ob.top_radius = 0.05
			ob.bottom_radius = 0.22
			ob.height = 2.0
			ob.radial_segments = 4
			obelisk.mesh = ob
			obelisk.material_override = _make_material(C_STONE)
			obelisk.position = Vector3(sx * span * 0.32, 1.15, sz * span * 0.32)
			_mesh_root.add_child(obelisk)

	# The altar in the middle and the glow above it.
	var altar: MeshInstance3D = MeshInstance3D.new()
	var ab: BoxMesh = BoxMesh.new()
	ab.size = Vector3(0.9, 0.6, 0.6)
	altar.mesh = ab
	altar.material_override = _make_material(C_ALTAR)
	altar.position.y = 0.6
	_mesh_root.add_child(altar)

	var glow: MeshInstance3D = MeshInstance3D.new()
	var gs: SphereMesh = SphereMesh.new()
	gs.radius = 0.28
	gs.height = 0.56
	glow.mesh = gs
	var mat: StandardMaterial3D = _make_material(C_GLOW)
	mat.emission_enabled = true
	mat.emission = C_GLOW
	mat.emission_energy_multiplier = 1.5
	glow.material_override = mat
	glow.position.y = 1.25
	_mesh_root.add_child(glow)

	_add_flag()
